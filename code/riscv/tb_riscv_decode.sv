`timescale 1ns / 1ps
`include "riscv_defs.sv"

module tb_riscv_decode;

    // DUT Signals
    logic [31:0]            instr_i;
    logic                   is_alu_o;
    logic                   is_load_o;
    logic                   is_store_o;
    logic                   is_branch_o;
    logic                   is_jal_o;
    logic                   is_jalr_o;
    logic                   invalid_o;
    logic [`ALU_OP_W - 1:0] alu_op_o;
    logic                   alu_src_b_imm_o;
    logic                   alu_src_a_pc_o;
    logic [4:0]             rd_o;
    logic [4:0]             rs1_o;
    logic [4:0]             rs2_o;
    logic                   rd_valid_o;
    logic [2:0]             branch_funct3_o;
    logic [1:0]             mem_size_o;
    logic                   mem_unsigned_o;
    logic [31:0]            imm_o;

    int total_errors = 0;

    // DUT Instantiation
    riscv_decode dut (
        .instr_i        (instr_i),
        .is_alu_o       (is_alu_o),
        .is_load_o      (is_load_o),
        .is_store_o     (is_store_o),
        .is_branch_o    (is_branch_o),
        .is_jal_o       (is_jal_o),
        .is_jalr_o      (is_jalr_o),
        .invalid_o      (invalid_o),
        .alu_op_o       (alu_op_o),
        .alu_src_b_imm_o(alu_src_b_imm_o),
        .alu_src_a_pc_o (alu_src_a_pc_o),
        .rd_o           (rd_o),
        .rs1_o          (rs1_o),
        .rs2_o          (rs2_o),
        .rd_valid_o     (rd_valid_o),
        .branch_funct3_o(branch_funct3_o),
        .mem_size_o     (mem_size_o),
        .mem_unsigned_o (mem_unsigned_o),
        .imm_o          (imm_o)
    );

    // Helper task to report DUT failures
    task automatic check_condition(
        input string test_id,
        input string description,
        input logic condition
    );
        if (!condition) begin
            $error("[%s FAIL] %s | Instr: 0x%8h | inv=%b, alu=%b, ld=%b, st=%b, br=%b, rd_val=%b, rd=%0d", 
                   test_id, description, instr_i, invalid_o, is_alu_o, is_load_o, is_store_o, is_branch_o, rd_valid_o, rd_o);
            total_errors++;
        end else begin
            $display("[%s PASS] %s", test_id, description);
        end
    endtask

    initial begin
        $display("==========================================================");
        $display("   STARTING RISC-V DECODER EXHAUSTIVE BUG EXPOSURE TB   ");
        $display("==========================================================");

        #5;

        //---------------------------------------------------------------------
        // BUG 1: Control Signals Remain Active When Sub-Decode Is Invalid
        // When default case sets invalid_o = 1, primary control lines are not cleared.
        //---------------------------------------------------------------------
        $display("\n--- [CATEGORY 1] Control Signal Leakage on Invalid Sub-Decodes ---");

        // Invalid LOAD funct3 (3'b011)
        instr_i = {12'h0, 5'd1, 3'b011, 5'd2, `OPCODE_LOAD}; #5;
        check_condition("TEST_1A", "LOAD with illegal funct3 MUST NOT set is_load_o or rd_valid_o",
                        (invalid_o == 1'b1) && (is_load_o == 1'b0) && (rd_valid_o == 1'b0));

        // Invalid STORE funct3 (3'b100)
        instr_i = {7'h0, 5'd1, 5'd2, 3'b100, 5'h0, `OPCODE_STORE}; #5;
        check_condition("TEST_1B", "STORE with illegal funct3 MUST NOT set is_store_o",
                        (invalid_o == 1'b1) && (is_store_o == 1'b0));

        // Invalid BRANCH funct3 (3'b010)
        instr_i = {7'h0, 5'd1, 5'd2, 3'b010, 4'h0, 1'b0, `OPCODE_BRANCH}; #5;
        check_condition("TEST_1C", "BRANCH with illegal funct3 MUST NOT set is_branch_o",
                        (invalid_o == 1'b1) && (is_branch_o == 1'b0));

        // Invalid R-type ADD/SUB funct7 (7'b1111111)
        instr_i = {7'b1111111, 5'd2, 5'd1, `FUNCT3_ADD_SUB, 5'd3, `OPCODE_OP}; #5;
        check_condition("TEST_1D", "R-type with illegal funct7 MUST NOT set is_alu_o or rd_valid_o",
                        (invalid_o == 1'b1) && (is_alu_o == 1'b0) && (rd_valid_o == 1'b0));

        //---------------------------------------------------------------------
        // BUG 2: Missing Funct7 Check for R-type Logic/Shift Instructions
        // R-type instructions (AND, OR, XOR, SLT, SLTU, SLL) MUST mandate funct7 == 7'b0000000.
        //---------------------------------------------------------------------
        $display("\n--- [CATEGORY 2] Unvalidated funct7 Field in R-Type Operations ---");

        // R-type AND with corrupt funct7 (7'b0100000 - SRA encoding)
        instr_i = {7'b0100000, 5'd2, 5'd1, `FUNCT3_AND, 5'd3, `OPCODE_OP}; #5;
        check_condition("TEST_2A", "AND with corrupt funct7 (0x20) must be flagged invalid",
                        (invalid_o == 1'b1) && (is_alu_o == 1'b0));

        // R-type SLL with corrupt funct7 (7'b0000001 - M-extension encoding)
        instr_i = {7'b0000001, 5'd2, 5'd1, `FUNCT3_SLL, 5'd3, `OPCODE_OP}; #5;
        check_condition("TEST_2B", "SLL with non-zero funct7 must be flagged invalid (if RV32M unsupported)",
                        (invalid_o == 1'b1) && (is_alu_o == 1'b0));

        //---------------------------------------------------------------------
        // BUG 3: Missing Funct3 Verification for JALR
        // RISC-V specification dictates JALR requires funct3 == 3'b000.
        //---------------------------------------------------------------------
        $display("\n--- [CATEGORY 3] Unvalidated funct3 Field for JALR ---");

        instr_i = {12'h10, 5'd1, 3'b101, 5'd2, `OPCODE_JALR}; #5;
        check_condition("TEST_3", "JALR with funct3 != 3'b000 must set invalid_o = 1",
                        (invalid_o == 1'b1) && (is_jalr_o == 1'b0));

        //---------------------------------------------------------------------
        // BUG 4: Missing Bit Validation for Shift-Immediate (SLLI)
        // I-type SLLI requires upper bits [31:25] == 7'b0000000.
        //---------------------------------------------------------------------
        $display("\n--- [CATEGORY 4] Unvalidated Upper Bits for I-type Shift (SLLI) ---");

        instr_i = {7'b0100000, 5'd5, 5'd1, `FUNCT3_SLL, 5'd2, `OPCODE_OP_IMM}; #5;
        check_condition("TEST_4", "SLLI with non-zero upper bits [31:25] must be flagged invalid",
                        (invalid_o == 1'b1) && (is_alu_o == 1'b0));

        //---------------------------------------------------------------------
        // CATEGORY 5: Sanity Verification of Legal Instructions
        //---------------------------------------------------------------------
        $display("\n--- [CATEGORY 5] Standard Legal Instruction Decoding ---");

        // Legal ADD
        instr_i = {`FUNCT7_ADD, 5'd2, 5'd1, `FUNCT3_ADD_SUB, 5'd3, `OPCODE_OP}; #5;
        check_condition("TEST_5A", "Legal ADD decoding",
                        (invalid_o == 1'b0) && (is_alu_o == 1'b1) && (rd_o == 5'd3) && (rs1_o == 5'd1) && (rs2_o == 5'd2));

        // Legal LW
        instr_i = {12'h04, 5'd1, `FUNCT3_WORD, 5'd5, `OPCODE_LOAD}; #5;
        check_condition("TEST_5B", "Legal LW decoding",
                        (invalid_o == 1'b0) && (is_load_o == 1'b1) && (mem_size_o == 2'b10) && (imm_o == 32'h4));

        // Legal LUI
        instr_i = {20'h12345, 5'd10, `OPCODE_LUI}; #5;
        check_condition("TEST_5C", "Legal LUI decoding",
                        (invalid_o == 1'b0) && (is_alu_o == 1'b1) && (imm_o == 32'h12345000));

        // Final Verification Summary
        $display("\n==========================================================");
        if (total_errors == 0)
            $display("TESTBENCH COMPLETED: All tests passed cleanly.");
        else
            $display("TESTBENCH COMPLETED: Detected %0d failure(s) in DUT implementation.", total_errors);
        $display("==========================================================");

        $finish;
    end

endmodule
