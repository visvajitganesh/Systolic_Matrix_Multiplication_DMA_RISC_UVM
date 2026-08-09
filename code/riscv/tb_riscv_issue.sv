`timescale 1ns/1ps
`include "riscv_defs.sv"

`ifndef ALU_OP_W
`define ALU_OP_W 4
`endif

module tb_riscv_issue;

    // ------------------------------------------------------------------------
    // Clock & Reset
    // ------------------------------------------------------------------------
    logic clk_i;
    logic rst_i;

    localparam CLK_PERIOD = 10;
    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    // ------------------------------------------------------------------------
    // Pipeline Control & Decode Inputs
    // ------------------------------------------------------------------------
    logic                  squash_i;
    logic                  stall_i;

    logic                  valid_dec_i;
    logic           [31:0] pc_dec_i;
    logic            [4:0] rd_dec_i;
    logic            [4:0] rs1_dec_i;
    logic            [4:0] rs2_dec_i;
    logic                  rd_valid_dec_i;
    logic                  is_load_dec_i;
    logic                  is_store_dec_i;
    logic                  is_branch_dec_i;
    logic [`ALU_OP_W - 1:0] alu_op_dec_i;
    logic                  alu_src_b_imm_dec_i;
    logic                  alu_src_a_pc_dec_i;
    logic            [1:0] mem_size_dec_i;
    logic                  mem_unsigned_dec_i;
    logic           [31:0] imm_dec_i;
    logic            [2:0] branch_funct3_dec_i;
    logic                  is_jal_dec_i;
    logic                  is_jalr_dec_i;

    logic           [31:0] alu_result_exec_i;

    // ------------------------------------------------------------------------
    // In-Flight Stage Signals (Scoreboard & Forwarding)
    // ------------------------------------------------------------------------
    logic                  valid_mem_i;
    logic            [4:0] rd_mem_i;
    logic                  rd_valid_mem_i;
    logic           [31:0] alu_result_mem_i;
    logic                  is_load_mem_i;

    logic                  valid_mem2_i;
    logic            [4:0] rd_mem2_i;
    logic                  rd_valid_mem2_i;
    logic           [31:0] alu_result_mem2_i;
    logic                  is_load_mem2_i;

    logic                  valid_wb_i;
    logic            [4:0] rd_wb_i;
    logic                  rd_valid_wb_i;
    logic           [31:0] result_wb_i;

    // ------------------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------------------
    logic                  stall_o;

    logic                  valid_exec_o;
    logic           [31:0] pc_exec_o;
    logic            [4:0] rd_exec_o;
    logic                  rd_valid_exec_o;
    logic                  is_load_exec_o;
    logic                  is_store_exec_o;
    logic [`ALU_OP_W - 1:0] alu_op_exec_o;
    logic           [31:0] operand_a_exec_o;
    logic           [31:0] operand_b_exec_o;
    logic           [31:0] store_data_exec_o;
    logic            [1:0] mem_size_exec_o;
    logic                  mem_unsigned_exec_o;
    logic           [31:0] imm_exec_o;
    logic                  is_branch_exec_o;
    logic            [2:0] branch_funct3_exec_o;
    logic                  is_jal_exec_o;
    logic                  is_jalr_exec_o;

    // Test tracking
    int pass_count = 0;
    int fail_count = 0;

    // ------------------------------------------------------------------------
    // DUT Instantiation
    // ------------------------------------------------------------------------
    riscv_issue dut (
        .clk_i                (clk_i),
        .rst_i                (rst_i),
        .squash_i             (squash_i),
        .stall_i              (stall_i),
        .valid_dec_i          (valid_dec_i),
        .pc_dec_i             (pc_dec_i),
        .rd_dec_i             (rd_dec_i),
        .rs1_dec_i            (rs1_dec_i),
        .rs2_dec_i            (rs2_dec_i),
        .rd_valid_dec_i       (rd_valid_dec_i),
        .is_load_dec_i        (is_load_dec_i),
        .is_store_dec_i       (is_store_dec_i),
        .is_branch_dec_i      (is_branch_dec_i),
        .alu_op_dec_i         (alu_op_dec_i),
        .alu_src_b_imm_dec_i  (alu_src_b_imm_dec_i),
        .alu_src_a_pc_dec_i   (alu_src_a_pc_dec_i),
        .mem_size_dec_i       (mem_size_dec_i),
        .mem_unsigned_dec_i   (mem_unsigned_dec_i),
        .imm_dec_i            (imm_dec_i),
        .branch_funct3_dec_i  (branch_funct3_dec_i),
        .is_jal_dec_i         (is_jal_dec_i),
        .is_jalr_dec_i        (is_jalr_dec_i),
        .alu_result_exec_i    (alu_result_exec_i),
        .valid_mem_i          (valid_mem_i),
        .rd_mem_i             (rd_mem_i),
        .rd_valid_mem_i       (rd_valid_mem_i),
        .alu_result_mem_i     (alu_result_mem_i),
        .is_load_mem_i        (is_load_mem_i),
        .valid_mem2_i         (valid_mem2_i),
        .rd_mem2_i            (rd_mem2_i),
        .rd_valid_mem2_i      (rd_valid_mem2_i),
        .alu_result_mem2_i    (alu_result_mem2_i),
        .is_load_mem2_i       (is_load_mem2_i),
        .valid_wb_i           (valid_wb_i),
        .rd_wb_i              (rd_wb_i),
        .rd_valid_wb_i        (rd_valid_wb_i),
        .result_wb_i          (result_wb_i),
        .stall_o              (stall_o),
        .valid_exec_o         (valid_exec_o),
        .pc_exec_o            (pc_exec_o),
        .rd_exec_o            (rd_exec_o),
        .rd_valid_exec_o      (rd_valid_exec_o),
        .is_load_exec_o       (is_load_exec_o),
        .is_store_exec_o      (is_store_exec_o),
        .alu_op_exec_o        (alu_op_exec_o),
        .operand_a_exec_o     (operand_a_exec_o),
        .operand_b_exec_o     (operand_b_exec_o),
        .store_data_exec_o    (store_data_exec_o),
        .mem_size_exec_o      (mem_size_exec_o),
        .mem_unsigned_exec_o  (mem_unsigned_exec_o),
        .imm_exec_o           (imm_exec_o),
        .is_branch_exec_o     (is_branch_exec_o),
        .branch_funct3_exec_o (branch_funct3_exec_o),
        .is_jal_exec_o        (is_jal_exec_o),
        .is_jalr_exec_o       (is_jalr_exec_o)
    );

    // ------------------------------------------------------------------------
    // Helper Tasks
    // ------------------------------------------------------------------------
    task automatic reset_inputs();
        squash_i             = 1'b0;
        stall_i              = 1'b1; // Default: normal pipeline advancement allowed
        valid_dec_i          = 1'b0;
        pc_dec_i             = 32'h0;
        rd_dec_i             = 5'd0;
        rs1_dec_i            = 5'd0;
        rs2_dec_i            = 5'd0;
        rd_valid_dec_i       = 1'b0;
        is_load_dec_i        = 1'b0;
        is_store_dec_i       = 1'b0;
        is_branch_dec_i      = 1'b0;
        alu_op_dec_i         = '0;
        alu_src_b_imm_dec_i  = 1'b0;
        alu_src_a_pc_dec_i   = 1'b0;
        mem_size_dec_i       = 2'b00;
        mem_unsigned_dec_i   = 1'b0;
        imm_dec_i            = 32'h0;
        branch_funct3_dec_i  = 3'b000;
        is_jal_dec_i         = 1'b0;
        is_jalr_dec_i        = 1'b0;
        alu_result_exec_i    = 32'h0;

        valid_mem_i          = 1'b0;
        rd_mem_i             = 5'd0;
        rd_valid_mem_i       = 1'b0;
        alu_result_mem_i     = 32'h0;
        is_load_mem_i        = 1'b0;

        valid_mem2_i         = 1'b0;
        rd_mem2_i            = 5'd0;
        rd_valid_mem2_i      = 1'b0;
        alu_result_mem2_i    = 32'h0;
        is_load_mem2_i       = 1'b0;

        valid_wb_i           = 1'b0;
        rd_wb_i              = 5'd0;
        rd_valid_wb_i        = 1'b0;
        result_wb_i          = 32'h0;
    endtask

    task automatic write_regfile(input [4:0] rd, input [31:0] value);
        @(negedge clk_i);
        valid_wb_i    = 1'b1;
        rd_wb_i       = rd;
        rd_valid_wb_i = 1'b1;
        result_wb_i   = value;
        @(posedge clk_i);
        #1;
        valid_wb_i    = 1'b0;
        rd_valid_wb_i = 1'b0;
    endtask

    task automatic check_val(input string name, input [31:0] actual, input [31:0] expected);
        if (actual === expected) begin
            $display("[PASS] %s = 0x%08h", name, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s = 0x%08h (Expected: 0x%08h)", name, actual, expected);
            fail_count++;
        end
    endtask

    task automatic check_bool(input string name, input actual, input expected);
        if (actual === expected) begin
            $display("[PASS] %s = %b", name, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s = %b (Expected: %b)", name, actual, expected);
            fail_count++;
        end
    endtask

    // ------------------------------------------------------------------------
    // Main Test Stimulus
    // ------------------------------------------------------------------------
    initial begin
        $display("==========================================================");
        $display("          STARTING RISC-V ISSUE STAGE TESTBENCH           ");
        $display("==========================================================");

        clk_i = 0;
        rst_i = 1;
        reset_inputs();

        // --------------------------------------------------------------------
        // Test 1: Reset Behavior
        // --------------------------------------------------------------------
        repeat (3) @(posedge clk_i);
        rst_i = 0;
        @(posedge clk_i); #1;

        $display("\n--- Test 1: Reset Verification ---");
        check_bool("valid_exec_o post-reset", valid_exec_o, 1'b0);
        check_bool("stall_o post-reset", stall_o, 1'b0);

        // Preload Register File
        $display("\n--- Preloading Register File ---");
        write_regfile(5'd1, 32'h0000_0010); // x1 = 0x10
        write_regfile(5'd2, 32'h0000_0020); // x2 = 0x20
        write_regfile(5'd3, 32'h0000_0030); // x3 = 0x30

        // --------------------------------------------------------------------
        // Test 2: Standard Instruction Issue (No Hazards)
        // --------------------------------------------------------------------
        $display("\n--- Test 2: Standard Issue (ADD x4, x1, x2) ---");
        @(negedge clk_i);
        valid_dec_i          = 1'b1;
        pc_dec_i             = 32'h0000_1000;
        rs1_dec_i            = 5'd1;
        rs2_dec_i            = 5'd2;
        rd_dec_i             = 5'd4;
        rd_valid_dec_i       = 1'b1;
        alu_src_a_pc_dec_i   = 1'b0;
        alu_src_b_imm_dec_i  = 1'b0;
        imm_dec_i            = 32'h0000_00FF;

        #1;
        check_bool("stall_o (no hazard)", stall_o, 1'b0);

        @(posedge clk_i); #1; // Latch into EXEC
        check_bool("valid_exec_o", valid_exec_o, 1'b1);
        check_val("pc_exec_o", pc_exec_o, 32'h0000_1000);
        check_val("rd_exec_o", rd_exec_o, 32'd4);
        check_val("operand_a_exec_o (from x1)", operand_a_exec_o, 32'h0000_0010);
        check_val("operand_b_exec_o (from x2)", operand_b_exec_o, 32'h0000_0020);

        // --------------------------------------------------------------------
        // Test 3: Scoreboard Hazard Detection (Load-Use Hazard)
        // --------------------------------------------------------------------
        $display("\n--- Test 3: Scoreboard Hazard Detection ---");
        
        // Cycle 1: Feed a Load instruction targeting x4 into Decode stage
        @(negedge clk_i);
        valid_dec_i     = 1'b1;
        rd_dec_i        = 5'd4;
        rd_valid_dec_i  = 1'b1;
        is_load_dec_i   = 1'b1; // LOAD instruction
        rs1_dec_i       = 5'd0;
        rs2_dec_i       = 5'd0;

        // Clock the load instruction into the EXEC stage outputs
        @(posedge clk_i);
        #1; 

        // Cycle 2: Present a dependent instruction in Decode stage reading x4
        @(negedge clk_i);
        rs1_dec_i       = 5'd4; // RAW dependency on x4

        #1; // Allow combinational stall logic to evaluate
        check_val("stall_o (Load-Use hazard on x4)", stall_o, 1'b1);

        // Clock the pipeline while stalled to verify a bubble is inserted
        @(posedge clk_i);
        #1;
        check_val("valid_exec_o (bubbled due to stall_o)", valid_exec_o, 1'b0);

        // --------------------------------------------------------------------
        // Test 4: Register x0 Special Handling
        // --------------------------------------------------------------------
        $display("\n--- Test 4: Register x0 Immunity from Hazards ---");
        // Place active destination x0 in WB stage
        @(negedge clk_i);
        valid_wb_i    = 1'b1;
        rd_wb_i       = 5'd0;
        rd_valid_wb_i = 1'b1;

        // Decode reads x0 and writes x0
        valid_dec_i    = 1'b1;
        rs1_dec_i      = 5'd0;
        rs2_dec_i      = 5'd0;
        rd_dec_i       = 5'd0;
        rd_valid_dec_i = 1'b1;

        #1;
        check_bool("stall_o (x0 hazard immune)", stall_o, 1'b0);

        @(negedge clk_i);
        valid_wb_i  = 1'b0;
        valid_dec_i = 1'b0;

        // --------------------------------------------------------------------
        // Test 5: Immediate & PC Operand Muxing
        // --------------------------------------------------------------------
        $display("\n--- Test 5: Immediate & PC Operand Selection ---");
        @(negedge clk_i);
        valid_dec_i         = 1'b1;
        pc_dec_i            = 32'h0000_2000;
        rs1_dec_i           = 5'd1;
        rs2_dec_i           = 5'd2;
        imm_dec_i           = 32'h0000_ABCD;
        alu_src_a_pc_dec_i  = 1'b1; // Select PC for operand_a
        alu_src_b_imm_dec_i = 1'b1; // Select Imm for operand_b
        is_store_dec_i      = 1'b1;

        @(posedge clk_i); #1;
        check_val("operand_a_exec_o (PC selected)", operand_a_exec_o, 32'h0000_2000);
        check_val("operand_b_exec_o (Imm selected)", operand_b_exec_o, 32'h0000_ABCD);
        check_val("store_data_exec_o (raw rs2 value)", store_data_exec_o, 32'h0000_0020);

        // --------------------------------------------------------------------
        // Test 6: Pipeline Freeze Handling (stall_i == 0)
        // --------------------------------------------------------------------
        $display("\n--- Test 6: Pipeline Freeze Handling (stall_i = 0) ---");
        @(negedge clk_i);
        valid_dec_i = 1'b0;
        stall_i     = 1'b0; // Freeze pipeline

        @(posedge clk_i); #1;
        check_val("operand_a_exec_o frozen", operand_a_exec_o, 32'h0000_2000);
        check_val("operand_b_exec_o frozen", operand_b_exec_o, 32'h0000_ABCD);

        stall_i = 1'b1; // Release freeze

        // --------------------------------------------------------------------
        // Test 7: Pipeline Squash (squash_i == 1)
        // --------------------------------------------------------------------
        $display("\n--- Test 7: Pipeline Squash ---");
        @(negedge clk_i);
        squash_i    = 1'b1;
        valid_dec_i = 1'b1;

        @(posedge clk_i); #1;
        check_bool("valid_exec_o squashed to 0", valid_exec_o, 1'b0);
        check_val("pc_exec_o squashed to 0", pc_exec_o, 32'h0);

        squash_i    = 1'b0;
        valid_dec_i = 1'b0;

        // --------------------------------------------------------------------
        // Test 8: Forwarding Priority Verification
        // --------------------------------------------------------------------
        $display("\n--- Test 8: Forwarding Priority Verification ---");
        
        // 1. Reset all decode control inputs to clean state
        reset_inputs();
        rst_i = 1'b0;

        @(negedge clk_i);
        // 2. Setup overlapping forwarding sources for rs1 = 3
        valid_wb_i          = 1'b1;
        rd_wb_i             = 5'd3;
        rd_valid_wb_i       = 1'b1;
        result_wb_i         = 32'hBBBB_BBBB; // Lowest priority

        valid_mem2_i        = 1'b1;
        rd_mem2_i           = 5'd3;
        rd_valid_mem2_i     = 1'b1;
        is_load_mem2_i      = 1'b0;
        alu_result_mem2_i   = 32'h2222_2222;

        valid_mem_i         = 1'b1;
        rd_mem_i            = 5'd3;
        rd_valid_mem_i      = 1'b1;
        is_load_mem_i       = 1'b0;
        alu_result_mem_i    = 32'h1111_1111; // Highest priority

        // 3. Setup Decode stage inputs
        valid_dec_i         = 1'b1;
        rs1_dec_i           = 5'd3;
        alu_src_a_pc_dec_i  = 1'b0;
        is_load_dec_i       = 1'b0;

        // 4. Clock edge latches bypassed operand into EXEC stage
        @(posedge clk_i);
        #1;
        check_val("operand_a_exec_o (MEM stage bypass priority)", operand_a_exec_o, 32'h1111_1111);

        // --------------------------------------------------------------------
        // Summary
        // --------------------------------------------------------------------
        $display("==========================================================");
        $display("   TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0)
            $display(" >>> ALL RISC-V ISSUE STAGE TESTS PASSED <<<");
        else
            $display(" >>> SOME TESTS FAILED - CHECK TRANSCRIPT <<<");

        $finish;
    end

endmodule