`timescale 1ns/1ps

module tb_riscv_fetch;

    // Inputs
    logic        clk_i;
    logic        rst_i;
    logic        branch_taken_i;
    logic [31:0] branch_target_i;
    logic        squash_i;
    logic        stall_i;
    logic [31:0] imem_rdata_i;

    // Outputs
    logic [31:0] imem_addr_o;
    logic [31:0] pc_o;
    logic [31:0] instr_o;
    logic        valid_o;

    // Instantiate DUT
    riscv_fetch dut (.*);

    // 100MHz Clock (10ns Period)
    always #5 clk_i = ~clk_i;

    // =========================================================================
    // Standard 1-Cycle Latency Synchronous Instruction Memory
    // =========================================================================
    logic [31:0] mem [0:3];
    initial begin
        mem[0] = 32'hAAAA_0000; // PC 0x00
        mem[1] = 32'hBBBB_0004; // PC 0x04
        mem[2] = 32'hCCCC_0008; // PC 0x08
        mem[3] = 32'hDDDD_000C; // PC 0x0C
    end

    // Memory latches imem_addr_o on edge and outputs data 1 cycle later
    always_ff @(posedge clk_i) begin
        imem_rdata_i <= mem[imem_addr_o[3:2]];
    end

    // =========================================================================
    // Test Sequence & Automated Verification
    // =========================================================================
    initial begin
        //$dumpfile("fetch_fail.vcd");
        //$dumpvars(0, tb_riscv_fetch_fail);

        // Initialize Signals
        clk_i           = 0;
        rst_i           = 1;
        branch_taken_i  = 0;
        branch_target_i = 0;
        squash_i        = 0;
        stall_i         = 0;

        // Release Reset
        #15 rst_i = 0;

        // ---------------------------------------------------------------------
        // Cycle 1: Request PC 0x00 from Memory
        // ---------------------------------------------------------------------
        @(posedge clk_i);

        // ---------------------------------------------------------------------
        // Cycle 2: PC 0x00 instruction arrives (0xAAAA_0000)
        // ---------------------------------------------------------------------
        @(posedge clk_i);
        #1;
        $display("[Cycle 2] Normal: pc_o = 0x%0h | instr_o = 0x%0h", pc_o, instr_o);

        // Downstream asserts STALL
        stall_i = 1'b1;
        $display("[TB STIMULUS] Asserting stall_i = 1");

        // ---------------------------------------------------------------------
        // Cycle 3: STALLED CYCLE (Exposes Bug 1)
        // ---------------------------------------------------------------------
        @(posedge clk_i);
        #1;
        $display("[Cycle 3 - STALLED] pc_o = 0x%0h | instr_o = 0x%0h", pc_o, instr_o);

        if (pc_o == 32'h0000_0000 && instr_o != 32'hAAAA_0000) begin
            $display("\n=======================================================");
            $display("[FAIL 1 DETECTED: CORRUPTED INSTRUCTION DURING STALL]");
            $display("  Target PC  : 0x%0h", pc_o);
            $display("  Expected   : 0xAAAA_0000");
            $display("  Got        : 0x%0h", instr_o);
            $display("Reason: instr_hold_q is gated by (!stall_i), so it failed");
            $display("        to latch imem_rdata_i when stall_i was asserted.");
            $display("=======================================================\n");
        end

        // Release STALL
        stall_i = 1'b0;
        $display("[TB STIMULUS] Releasing stall_i = 0");

        // ---------------------------------------------------------------------
        // Cycle 4: STALL RELEASED (Exposes Bug 2)
        // ---------------------------------------------------------------------
        @(posedge clk_i);
        #1;
        $display("[Cycle 4 - RESUMED] pc_o = 0x%0h | instr_o = 0x%0h", pc_o, instr_o);

        if (pc_o == 32'h0000_0004 && instr_o != 32'hBBBB_0004) begin
            $display("=======================================================");
            $display("[FAIL 2 DETECTED: SKIPPED INSTRUCTION ON RESUME]");
            $display("  Target PC  : 0x%0h", pc_o);
            $display("  Expected   : 0xBBBB_0004");
            $display("  Got        : 0x%0h", instr_o);
            $display("Reason: Memory advanced to PC 0x8 while stalled. When stall");
            $display("        released, pc_e_q became 0x4, but imem_rdata_i");
            $display("        was already delivering 0xCCCC_0008!");
            $display("=======================================================\n");
        end

        #20;
        $finish;
    end

endmodule