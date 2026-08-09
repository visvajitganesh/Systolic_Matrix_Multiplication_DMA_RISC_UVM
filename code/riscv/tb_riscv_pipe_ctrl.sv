`timescale 1ns/1ps

module tb_riscv_pipe_ctrl;

    // ------------------------------------------------------------------------
    // Testbench Clock & Reset Signals
    // ------------------------------------------------------------------------
    logic        clk_i;
    logic        rst_i;

    // Control Inputs
    logic        squash_i;
    logic        stall_i;

    // Inputs from EXECUTE
    logic        valid_exec_i;
    logic [31:0] pc_exec_i;
    logic  [4:0] rd_exec_i;
    logic        rd_valid_exec_i;
    logic        is_load_exec_i;
    logic        is_store_exec_i;
    logic        is_jal_exec_i;
    logic        is_jalr_exec_i;
    logic [31:0] alu_result_exec_i;
    logic [31:0] store_data_exec_i;
    logic  [1:0] mem_size_exec_i;
    logic        mem_unsigned_exec_i;

    // Outputs from MEMORY 1
    logic        valid_mem_o;
    logic [31:0] pc_mem_o;
    logic  [4:0] rd_mem_o;
    logic        rd_valid_mem_o;
    logic        is_load_mem_o;
    logic        is_store_mem_o;
    logic        is_jal_mem_o;
    logic        is_jalr_mem_o;
    logic [31:0] alu_result_mem_o;
    logic [31:0] store_data_mem_o;
    logic  [1:0] mem_size_mem_o;
    logic        mem_unsigned_mem_o;

    // Outputs from MEMORY 2
    logic        valid_mem2_o;
    logic [31:0] pc_mem2_o;
    logic  [4:0] rd_mem2_o;
    logic        rd_valid_mem2_o;
    logic        is_load_mem2_o;
    logic        is_jal_mem2_o;
    logic        is_jalr_mem2_o;
    logic [31:0] alu_result_mem2_o;

    // Input: LSU Read Data
    logic [31:0] mem_rdata_i;

    // Outputs to WRITEBACK
    logic        valid_wb_o;
    logic [31:0] pc_wb_o;
    logic  [4:0] rd_wb_o;
    logic        rd_valid_wb_o;
    logic [31:0] result_wb_o;

    // Track pass/fail statistics
    int pass_count = 0;
    int fail_count = 0;

    // ------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // ------------------------------------------------------------------------
    riscv_pipe_ctrl dut (
        .clk_i                (clk_i),
        .rst_i                (rst_i),
        .squash_i             (squash_i),
        .stall_i              (stall_i),

        .valid_exec_i         (valid_exec_i),
        .pc_exec_i            (pc_exec_i),
        .rd_exec_i            (rd_exec_i),
        .rd_valid_exec_i      (rd_valid_exec_i),
        .is_load_exec_i       (is_load_exec_i),
        .is_store_exec_i      (is_store_exec_i),
        .is_jal_exec_i        (is_jal_exec_i),
        .is_jalr_exec_i       (is_jalr_exec_i),
        .alu_result_exec_i    (alu_result_exec_i),
        .store_data_exec_i    (store_data_exec_i),
        .mem_size_exec_i      (mem_size_exec_i),
        .mem_unsigned_exec_i  (mem_unsigned_exec_i),

        .valid_mem_o          (valid_mem_o),
        .pc_mem_o             (pc_mem_o),
        .rd_mem_o             (rd_mem_o),
        .rd_valid_mem_o       (rd_valid_mem_o),
        .is_load_mem_o        (is_load_mem_o),
        .is_store_mem_o       (is_store_mem_o),
        .is_jal_mem_o         (is_jal_mem_o),
        .is_jalr_mem_o        (is_jalr_mem_o),
        .alu_result_mem_o     (alu_result_mem_o),
        .store_data_mem_o     (store_data_mem_o),
        .mem_size_mem_o       (mem_size_mem_o),
        .mem_unsigned_mem_o   (mem_unsigned_mem_o),

        .valid_mem2_o         (valid_mem2_o),
        .pc_mem2_o            (pc_mem2_o),
        .rd_mem2_o            (rd_mem2_o),
        .rd_valid_mem2_o      (rd_valid_mem2_o),
        .is_load_mem2_o       (is_load_mem2_o),
        .is_jal_mem2_o        (is_jal_mem2_o),
        .is_jalr_mem2_o       (is_jalr_mem2_o),
        .alu_result_mem2_o    (alu_result_mem2_o),

        .mem_rdata_i          (mem_rdata_i),

        .valid_wb_o           (valid_wb_o),
        .pc_wb_o              (pc_wb_o),
        .rd_wb_o              (rd_wb_o),
        .rd_valid_wb_o        (rd_valid_wb_o),
        .result_wb_o          (result_wb_o)
    );

    // ------------------------------------------------------------------------
    // Clock Generation (100 MHz, 10ns period)
    // ------------------------------------------------------------------------
    always #5 clk_i = ~clk_i;

    // ------------------------------------------------------------------------
    // Helper Tasks
    // ------------------------------------------------------------------------
    task automatic check_val(string test_name, logic [31:0] actual, logic [31:0] expected);
        if (actual === expected) begin
            $display("[PASS] %s = 0x%08h", test_name, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s = 0x%08h (Expected: 0x%08h)", test_name, actual, expected);
            fail_count++;
        end
    endtask

    task automatic clear_inputs();
        squash_i            = 1'b0;
        stall_i             = 1'b0;
        valid_exec_i        = 1'b0;
        pc_exec_i           = '0;
        rd_exec_i           = '0;
        rd_valid_exec_i     = 1'b0;
        is_load_exec_i      = 1'b0;
        is_store_exec_i     = 1'b0;
        is_jal_exec_i       = 1'b0;
        is_jalr_exec_i      = 1'b0;
        alu_result_exec_i   = '0;
        store_data_exec_i   = '0;
        mem_size_exec_i     = '0;
        mem_unsigned_exec_i = 1'b0;
        mem_rdata_i         = '0;
    endtask

    // ------------------------------------------------------------------------
    // Test Sequence
    // ------------------------------------------------------------------------
    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_inputs();

        $display("==========================================================");
        $display("          STARTING RISC-V PIPE CTRL TESTBENCH             ");
        $display("==========================================================");

        // Reset stage
        repeat (2) @(posedge clk_i);
        #1;
        rst_i = 1'b0;

        // --------------------------------------------------------------------
        // Test 1: Reset Verification
        // --------------------------------------------------------------------
        $display("\n--- Test 1: Reset Verification ---");
        check_val("valid_mem_o post-reset",  valid_mem_o,  32'h0);
        check_val("valid_mem2_o post-reset", valid_mem2_o, 32'h0);
        check_val("valid_wb_o post-reset",   valid_wb_o,   32'h0);

        // --------------------------------------------------------------------
        // Test 2: Standard Instruction Propagation (ADD x5, x1, x2)
        // --------------------------------------------------------------------
        $display("\n--- Test 2: Pipeline Propagation across EX -> MEM -> MEM2 -> WB ---");
        
        // Cycle 1: Drive instruction into EX
        @(negedge clk_i);
        valid_exec_i      = 1'b1;
        pc_exec_i         = 32'h0000_1000;
        rd_exec_i         = 5'd5;
        rd_valid_exec_i   = 1'b1;
        alu_result_exec_i = 32'h0000_0030; // ADD result

        // Clock 1 -> EX advances to MEM1
        @(posedge clk_i); #1;
        check_val("valid_mem_o (Cycle 1)",      valid_mem_o,      32'h1);
        check_val("pc_mem_o (Cycle 1)",         pc_mem_o,         32'h0000_1000);
        check_val("rd_mem_o (Cycle 1)",         rd_mem_o,         32'd5);
        check_val("alu_result_mem_o (Cycle 1)", alu_result_mem_o, 32'h0000_0030);

        // Clear EXEC input for next cycle
        clear_inputs();

        // Clock 2 -> MEM1 advances to MEM2
        @(posedge clk_i); #1;
        check_val("valid_mem2_o (Cycle 2)",      valid_mem2_o,      32'h1);
        check_val("pc_mem2_o (Cycle 2)",         pc_mem2_o,         32'h0000_1000);
        check_val("alu_result_mem2_o (Cycle 2)", alu_result_mem2_o, 32'h0000_0030);

        // Clock 3 -> MEM2 advances to WB
        @(posedge clk_i); #1;
        check_val("valid_wb_o (Cycle 3)", valid_wb_o, 32'h1);
        check_val("pc_wb_o (Cycle 3)",    pc_wb_o,    32'h0000_1000);
        check_val("rd_wb_o (Cycle 3)",    rd_wb_o,    32'd5);
        check_val("result_wb_o (ALU)",    result_wb_o, 32'h0000_0030);

        // --------------------------------------------------------------------
        // Test 3: Load Data Muxing Verification (LW x6, 0(x2))
        // --------------------------------------------------------------------
        $display("\n--- Test 3: Load Data Muxing (LW Result Selection) ---");
        
        @(negedge clk_i);
        valid_exec_i      = 1'b1;
        pc_exec_i         = 32'h0000_2000;
        rd_exec_i         = 5'd6;
        rd_valid_exec_i   = 1'b1;
        is_load_exec_i    = 1'b1;
        alu_result_exec_i = 32'h2000_0000; // Load Address

        @(posedge clk_i); // Advance to MEM1
        clear_inputs();
        
        @(posedge clk_i); // Advance to MEM2
        // Provide memory read data while instruction is in MEM2
        mem_rdata_i = 32'hDEAD_BEEF;

        @(posedge clk_i); #1; // Advance to WB
        check_val("valid_wb_o (Load)", valid_wb_o, 32'h1);
        check_val("rd_wb_o (Load)",    rd_wb_o,    32'd6);
        check_val("result_wb_o (Load Data Muxed)", result_wb_o, 32'hDEAD_BEEF);

        // --------------------------------------------------------------------
        // Test 4: Branch/Jump Link PC+4 Selection (JAL x1, offset)
        // --------------------------------------------------------------------
        $display("\n--- Test 4: JAL/JALR PC+4 Return Address Muxing ---");
        
        @(negedge clk_i);
        valid_exec_i    = 1'b1;
        pc_exec_i       = 32'h0000_3000;
        rd_exec_i       = 5'd1;
        rd_valid_exec_i = 1'b1;
        is_jal_exec_i   = 1'b1;

        @(posedge clk_i); // EX -> MEM1
        clear_inputs();
        @(posedge clk_i); // MEM1 -> MEM2
        @(posedge clk_i); #1; // MEM2 -> WB

        check_val("result_wb_o (JAL PC+4 Return Addr)", result_wb_o, 32'h0000_3004);

        // --------------------------------------------------------------------
        // Test 5: Pipeline Stall Handling (stall_i = 1)
        // --------------------------------------------------------------------
        $display("\n--- Test 5: AXI/LSU Stall Freeze (stall_i = 1) ---");
        
        // Cycle 1: Load instruction into MEM1
        @(negedge clk_i);
        valid_exec_i      = 1'b1;
        pc_exec_i         = 32'h0000_4000;
        rd_exec_i         = 5'd8;
        rd_valid_exec_i   = 1'b1;
        alu_result_exec_i = 32'hCAFE_BABE;

        @(posedge clk_i); #1; // EX -> MEM1
        
        // Assert stall_i on next cycle
        @(negedge clk_i);
        stall_i      = 1'b1;
        valid_exec_i = 1'b1;
        pc_exec_i    = 32'h0000_4004; // Incoming new instruction in EX

        @(posedge clk_i); #1; // Clock edge while stall active
        check_val("pc_mem_o frozen during stall_i",  pc_mem_o,  32'h0000_4000);
        check_val("pc_mem2_o frozen during stall_i", pc_mem2_o, 32'h0000_0000);

        // Release stall
        @(negedge clk_i);
        stall_i = 1'b0;
        clear_inputs();

        @(posedge clk_i); #1; // Resume pipeline flow
        check_val("pc_mem2_o after stall released", pc_mem2_o, 32'h0000_4000);

        // --------------------------------------------------------------------
        // Test 6: Control Signal Gating for Bubbles
        // --------------------------------------------------------------------
        $display("\n--- Test 6: Bubble Control Signal Gating ---");
        
        @(negedge clk_i);
        valid_exec_i    = 1'b0; // Bubble / Invalid cycle
        rd_valid_exec_i = 1'b1; // Dummy control signals set
        is_load_exec_i  = 1'b1;
        is_store_exec_i = 1'b1;

        @(posedge clk_i); #1;
        check_val("rd_valid_mem_o gated on bubble", rd_valid_mem_o, 32'h0);
        check_val("is_load_mem_o gated on bubble",  is_load_mem_o,  32'h0);
        check_val("is_store_mem_o gated on bubble", is_store_mem_o, 32'h0);

        // --------------------------------------------------------------------
        // Test Summary
        // --------------------------------------------------------------------
        $display("\n==========================================================");
        $display("   TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0) begin
            $display(" >>> ALL TESTS PASSED SUCCESSFULLY! <<<\n");
        end else begin
            $display(" >>> SOME TESTS FAILED - CHECK TRANSCRIPT <<< \n");
        end

        $finish;
    end

endmodule