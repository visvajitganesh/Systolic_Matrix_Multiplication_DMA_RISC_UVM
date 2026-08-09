`timescale 1ns/1ps

module tb_riscv_fetch;

    localparam CLK_PERIOD = 10; // 100 MHz clock

    // DUT Signals
    logic        clk_i;
    logic        rst_i;

    logic        branch_taken_i;
    logic [31:0] branch_target_i;
    logic        squash_i;
    logic        stall_i;

    logic [31:0] imem_addr_o;
    logic [31:0] imem_rdata_i;

    logic [31:0] pc_o;
    logic [31:0] instr_o;
    logic        valid_o;

    // Test Tracking
    int pass_count = 0;
    int fail_count = 0;

    // --------------------------------------------------------
    // Synchronous Instruction Memory Model
    // --------------------------------------------------------
    logic [31:0] imem [0:255];

    always_ff @(posedge clk_i) begin
        imem_rdata_i <= imem[imem_addr_o[31:2]];
    end

    // Instantiate DUT
    riscv_fetch dut (
        .clk_i           (clk_i),
        .rst_i           (rst_i),
        .branch_taken_i  (branch_taken_i),
        .branch_target_i (branch_target_i),
        .squash_i        (squash_i),
        .stall_i         (stall_i),
        .imem_addr_o     (imem_addr_o),
        .imem_rdata_i    (imem_rdata_i),
        .pc_o            (pc_o),
        .instr_o         (instr_o),
        .valid_o         (valid_o)
    );

    // Clock Generation
    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    // Task to check outputs
    task automatic check_outputs(
        input [31:0] exp_pc,
        input [31:0] exp_instr,
        input        exp_valid,
        input string test_name
    );
        if ((pc_o === exp_pc) && (instr_o === exp_instr) && (valid_o === exp_valid)) begin
            $display("[PASS] %-35s | PC: 0x%08h | Instr: 0x%08h | Valid: %0b", 
                     test_name, pc_o, instr_o, valid_o);
            pass_count++;
        end else begin
            $display("** Error: [FAIL] %-28s | Expected: PC=0x%08h Instr=0x%08h Valid=%0b | Got: PC=0x%08h Instr=0x%08h Valid=%0b",
                     test_name, exp_pc, exp_instr, exp_valid, pc_o, instr_o, valid_o);
            fail_count++;
        end
    endtask

    // Stimulus Process
    initial begin
        // Initialize Memory Array to 0s to prevent 'X' states
        foreach (imem[i]) imem[i] = 32'h0000_0000;

        // Initialize Signals
        clk_i           = 0;
        rst_i           = 1;
        branch_taken_i  = 0;
        branch_target_i = 32'h0;
        squash_i        = 0;
        stall_i         = 0;

        // Populate Memory with Mock RISC-V Instructions
        imem[0]  = 32'h00100093; // 0x00: addi x1, x0, 1
        imem[1]  = 32'h00200113; // 0x04: addi x2, x0, 2
        imem[2]  = 32'h00300193; // 0x08: addi x3, x0, 3
        imem[3]  = 32'h00400213; // 0x0C: addi x4, x0, 4
        imem[4]  = 32'h00500293; // 0x10: addi x5, x0, 5
        imem[8]  = 32'h00A00313; // 0x20: addi x6, x0, 10 (Branch Target)
        imem[9]  = 32'h00B00393; // 0x24: addi x7, x0, 11
        imem[10] = 32'h00000000; // 0x28: nop

        $display("==========================================================");
        $display("          STARTING RISC-V FETCH TESTBENCH                 ");
        $display("==========================================================");

        // --------------------------------------------------------
        // Test 1: Reset Check
        // --------------------------------------------------------
        repeat (2) @(posedge clk_i);
        #1;
        if (valid_o === 1'b0 && imem_addr_o === 32'h0) begin
            $display("[PASS] Reset Verification               | imem_addr: 0x%08h | Valid: %0b", imem_addr_o, valid_o);
            pass_count++;
        end else begin
            $display("** Error: [FAIL] Reset Verification");
            fail_count++;
        end

        // Release Reset
        @(negedge clk_i);
        rst_i = 0;

        // --------------------------------------------------------
        // Test 2: Sequential Instruction Fetch
        // --------------------------------------------------------
        @(posedge clk_i); #1; // Fetching PC 0x00
        check_outputs(32'h0000_0000, 32'h00100093, 1'b1, "Fetch 1 (PC 0x00)");

        @(posedge clk_i); #1; // Fetching PC 0x04
        check_outputs(32'h0000_0004, 32'h00200113, 1'b1, "Fetch 2 (PC 0x04)");

        @(posedge clk_i); #1; // Fetching PC 0x08
        check_outputs(32'h0000_0008, 32'h00300193, 1'b1, "Fetch 3 (PC 0x08)");

        // --------------------------------------------------------
        // Test 3: Stall Behavior & Skid Buffer Test
        // PC 0x08 and its corresponding instruction (0x00300193) should hold
        // --------------------------------------------------------
        @(negedge clk_i);
        stall_i = 1'b1;

        @(posedge clk_i); #1; // Stall Cycle 1
        check_outputs(32'h0000_0008, 32'h00300193, 1'b1, "Stall Cycle 1 (PC 0x08 Held)");

        @(posedge clk_i); #1; // Stall Cycle 2: Skid buffer feeds instr_o
        check_outputs(32'h0000_0008, 32'h00300193, 1'b1, "Stall Cycle 2 (Skid Buffer Active)");

        // De-assert Stall
        @(negedge clk_i);
        stall_i = 1'b0;

        @(posedge clk_i); #1; // Normal operation resumes at PC 0x0C
        check_outputs(32'h0000_000C, 32'h00400213, 1'b1, "Post-Stall Resume (PC 0x0C)");

        // --------------------------------------------------------
        // Test 4: Branch Redirection
        // --------------------------------------------------------
        @(negedge clk_i);
        branch_taken_i  = 1'b1;
        branch_target_i = 32'h0000_0020;

        @(posedge clk_i); #1; // Redirection cycle: valid drops
        branch_taken_i  = 1'b0;
        check_outputs(32'h0000_0010, 32'h00500293, 1'b0, "Branch Redirect Cycle (Invalidated)");

        @(posedge clk_i); #1; // Target instruction arrives at PC 0x20
        check_outputs(32'h0000_0020, 32'h00A00313, 1'b1, "Branch Target Fetch (PC 0x20)");

        // --------------------------------------------------------
        // Test 5: Pipeline Squash (Flush)
        // --------------------------------------------------------
        @(negedge clk_i);
        squash_i = 1'b1;

        @(posedge clk_i); #1;
        squash_i = 1'b0;
        check_outputs(32'h0000_0024, 32'h00B00393, 1'b0, "Pipeline Squash Check (Valid Low)");

        @(posedge clk_i); #1;
        check_outputs(32'h0000_0028, 32'h00000000, 1'b1, "Post-Squash Resume");

        // --------------------------------------------------------
        // Final Summary
        // --------------------------------------------------------
        $display("==========================================================");
        $display("   TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0)
            $display(" >>> ALL FETCH TESTS PASSED <<<");
        else
            $display(" >>> SOME FETCH TESTS FAILED - CHECK TRANSCRIPT <<<");

        $finish;
    end

endmodule
