`timescale 1ns / 1ps
`include "riscv_defs.sv"

module tb_riscv_decode;

    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic [31:0]           instr_i;

    logic                  is_alu_o;
    logic                  is_load_o;
    logic                  is_store_o;
    logic                  is_branch_o;
    logic                  is_jal_o;
    logic                  is_jalr_o;
    logic                  invalid_o;

    logic [`ALU_OP_W - 1:0] alu_op_o;
    logic                  alu_src_b_imm_o;
    logic                  alu_src_a_pc_o;

    logic [4:0]            rd_o;
    logic [4:0]            rs1_o;
    logic [4:0]            rs2_o;
    logic                  rd_valid_o;

    logic [2:0]            branch_funct3_o;

    logic [1:0]            mem_size_o;
    logic                  mem_unsigned_o;

    logic [31:0]           imm_o;

    // Scoreboard tracking
    int pass_count = 0;
    int fail_count = 0;

    // =========================================================================
    // DUT Instantiation
    // =========================================================================
    riscv_decode dut (
        .instr_i         (instr_i),
        .is_alu_o        (is_alu_o),
        .is_load_o       (is_load_o),
        .is_store_o      (is_store_o),
        .is_branch_o     (is_branch_o),
        .is_jal_o        (is_jal_o),
        .is_jalr_o       (is_jalr_o),
        .invalid_o       (invalid_o),
        .alu_op_o        (alu_op_o),
        .alu_src_b_imm_o (alu_src_b_imm_o),
        .alu_src_a_pc_o  (alu_src_a_pc_o),
        .rd_o            (rd_o),
        .rs1_o           (rs1_o),
        .rs2_o           (rs2_o),
        .rd_valid_o      (rd_valid_o),
        .branch_funct3_o (branch_funct3_o),
        .mem_size_o      (mem_size_o),
        .mem_unsigned_o  (mem_unsigned_o),
        .imm_o           (imm_o)
    );

    // =========================================================================
    // Helper Encoding Functions
    // =========================================================================
    function automatic logic [31:0] encode_r(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        return {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] encode_i(
        input logic [11:0] imm,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] encode_s(
        input logic [11:0] imm,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        return {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function automatic logic [31:0] encode_b(
        input logic [12:0] imm, // bit 0 is always 0
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    endfunction

    function automatic logic [31:0] encode_u(
        input logic [19:0] imm20,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm20, rd, opcode};
    endfunction

    function automatic logic [31:0] encode_j(
        input logic [20:0] imm, // bit 0 is always 0
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction

    // =========================================================================
    // Verification Check Task
    // =========================================================================
    task automatic check_outputs(
        input string test_name,
        input logic  exp_is_alu,
        input logic  exp_is_load,
        input logic  exp_is_store,
        input logic  exp_is_branch,
        input logic  exp_is_jal,
        input logic  exp_is_jalr,
        input logic  exp_invalid,
        input logic [`ALU_OP_W-1:0] exp_alu_op,
        input logic  exp_alu_src_b_imm,
        input logic  exp_alu_src_a_pc,
        input logic  exp_rd_valid,
        input logic [1:0] exp_mem_size,
        input logic  exp_mem_unsigned,
        input logic [31:0] exp_imm,
        input logic [4:0] exp_rd,
        input logic [4:0] exp_rs1,
        input logic [4:0] exp_rs2
    );
        #1; // Allow combinatorial logic to settle

        if (is_alu_o        === exp_is_alu        &&
            is_load_o       === exp_is_load       &&
            is_store_o      === exp_is_store      &&
            is_branch_o     === exp_is_branch     &&
            is_jal_o        === exp_is_jal        &&
            is_jalr_o       === exp_is_jalr       &&
            invalid_o       === exp_invalid       &&
            alu_op_o        === exp_alu_op        &&
            alu_src_b_imm_o === exp_alu_src_b_imm &&
            alu_src_a_pc_o  === exp_alu_src_a_pc  &&
            rd_valid_o      === exp_rd_valid      &&
            mem_size_o      === exp_mem_size      &&
            mem_unsigned_o  === exp_mem_unsigned  &&
            imm_o           === exp_imm           &&
            rd_o            === exp_rd            &&
            rs1_o           === exp_rs1           &&
            rs2_o           === exp_rs2) begin
            $display("[PASS] %s", test_name);
            pass_count++;
        end else begin
            $error("[FAIL] %s", test_name);
            $display("       Expected: is_alu=%b load=%b store=%b branch=%b jal=%b jalr=%b inv=%b | alu_op=0x%0h b_imm=%b a_pc=%b rd_v=%b mem_sz=%b mem_u=%b imm=0x%0h rd=%0d rs1=%0d rs2=%0d",
                     exp_is_alu, exp_is_load, exp_is_store, exp_is_branch, exp_is_jal, exp_is_jalr, exp_invalid, exp_alu_op, exp_alu_src_b_imm, exp_alu_src_a_pc, exp_rd_valid, exp_mem_size, exp_mem_unsigned, exp_imm, exp_rd, exp_rs1, exp_rs2);
            $display("       Actual  : is_alu=%b load=%b store=%b branch=%b jal=%b jalr=%b inv=%b | alu_op=0x%0h b_imm=%b a_pc=%b rd_v=%b mem_sz=%b mem_u=%b imm=0x%0h rd=%0d rs1=%0d rs2=%0d",
                     is_alu_o, is_load_o, is_store_o, is_branch_o, is_jal_o, is_jalr_o, invalid_o, alu_op_o, alu_src_b_imm_o, alu_src_a_pc_o, rd_valid_o, mem_size_o, mem_unsigned_o, imm_o, rd_o, rs1_o, rs2_o);
            fail_count++;
        end
    endtask

    // =========================================================================
    // Test Sequence
    // =========================================================================
    initial begin
        $display("==========================================================");
        $display("             STARTING RISC-V DECODER TESTBENCH            ");
        $display("==========================================================");

        // ---------------------------------------------------------------------
        // 1. R-Type Instructions
        // ---------------------------------------------------------------------
        // ADD x3, x1, x2
        instr_i = encode_r(`FUNCT7_ADD, 5'd2, 5'd1, `FUNCT3_ADD_SUB, 5'd3, `OPCODE_OP);
        check_outputs("R-Type ADD", 1,0,0,0,0,0,0, `ALU_ADD, 0,0,1, 2'b00,0, 32'h0, 3, 1, 2);

        // SUB x4, x5, x6
        instr_i = encode_r(`FUNCT7_SUB, 5'd6, 5'd5, `FUNCT3_ADD_SUB, 5'd4, `OPCODE_OP);
        check_outputs("R-Type SUB", 1,0,0,0,0,0,0, `ALU_SUB, 0,0,1, 2'b00,0, 32'h0, 4, 5, 6);

        // SRA x7, x8, x9
        instr_i = encode_r(`FUNCT7_SRA, 5'd9, 5'd8, `FUNCT3_SRL_SRA, 5'd7, `OPCODE_OP);
        check_outputs("R-Type SRA", 1,0,0,0,0,0,0, `ALU_SRA, 0,0,1, 2'b00,0, 32'h0, 7, 8, 9);

        // ---------------------------------------------------------------------
        // 2. I-Type ALU Instructions (Positive and Negative Immediates)
        // ---------------------------------------------------------------------
        // ADDI x10, x11, -5 (0xFB1)
        instr_i = encode_i(12'shFB1, 5'd11, `FUNCT3_ADD_SUB, 5'd10, `OPCODE_OP_IMM);
        check_outputs("I-Type ADDI (-5)", 1,0,0,0,0,0,0, `ALU_ADD, 1,0,1, 2'b00,0, 32'hFFFF_FFB1, 10, 11, 0);

        // SRAI x12, x13, 4
        instr_i = encode_i({`FUNCT7_SRA, 5'd4}, 5'd13, `FUNCT3_SRL_SRA, 5'd12, `OPCODE_OP_IMM);
        check_outputs("I-Type SRAI", 1,0,0,0,0,0,0, `ALU_SRA, 1,0,1, 2'b00,0, 32'h0000_0404, 12, 13, 0);

        // ---------------------------------------------------------------------
        // 3. Load Instructions
        // ---------------------------------------------------------------------
        // LW x14, 16(x15)
        instr_i = encode_i(12'd16, 5'd15, `FUNCT3_WORD, 5'd14, `OPCODE_LOAD);
        check_outputs("Load LW", 0,1,0,0,0,0,0, `ALU_ADD, 1,0,1, 2'b10,0, 32'd16, 14, 15, 0);

        // LBU x16, -1(x17)
        instr_i = encode_i(12'hFFF, 5'd17, `FUNCT3_BYTE_U, 5'd16, `OPCODE_LOAD);
        check_outputs("Load LBU", 0,1,0,0,0,0,0, `ALU_ADD, 1,0,1, 2'b00,1, 32'hFFFF_FFFF, 16, 17, 0);

        // ---------------------------------------------------------------------
        // 4. Store Instructions
        // ---------------------------------------------------------------------
        // SW x18, -8(x19)
        instr_i = encode_s(-12'sd8, 5'd18, 5'd19, `FUNCT3_WORD, `OPCODE_STORE);
        check_outputs("Store SW", 0,0,1,0,0,0,0, `ALU_ADD, 1,0,0, 2'b10,0, 32'hFFFF_FFF8, 0, 19, 18);

        // SB x20, 4(x21)
        instr_i = encode_s(12'd4, 5'd20, 5'd21, `FUNCT3_BYTE, `OPCODE_STORE);
        check_outputs("Store SB", 0,0,1,0,0,0,0, `ALU_ADD, 1,0,0, 2'b00,0, 32'd4, 0, 21, 20);

        // ---------------------------------------------------------------------
        // 5. Branch Instructions
        // ---------------------------------------------------------------------
        // BEQ x22, x23, offset -16
        instr_i = encode_b(-13'sd16, 5'd23, 5'd22, `FUNCT3_BEQ, `OPCODE_BRANCH);
        check_outputs("Branch BEQ", 0,0,0,1,0,0,0, `ALU_SUB, 0,0,0, 2'b00,0, 32'hFFFF_FFF0, 0, 22, 23);

        // BLT x24, x25, offset +32
        instr_i = encode_b(13'sd32, 5'd25, 5'd24, `FUNCT3_BLT, `OPCODE_BRANCH);
        check_outputs("Branch BLT", 0,0,0,1,0,0,0, `ALU_SLT, 0,0,0, 2'b00,0, 32'd32, 0, 24, 25);

        // ---------------------------------------------------------------------
        // 6. Control Flow (JAL / JALR)
        // ---------------------------------------------------------------------
        // JAL x1, -2048
        instr_i = encode_j(-21'sd2048, 5'd1, `OPCODE_JAL);
        check_outputs("JAL", 0,0,0,0,1,0,0, `ALU_ADD, 1,1,1, 2'b00,0, 32'hFFFF_F800, 1, 0, 0);

        // JALR x1, 4(x2)
        instr_i = encode_i(12'd4, 5'd2, 3'b000, 5'd1, `OPCODE_JALR);
        check_outputs("JALR", 0,0,0,0,0,1,0, `ALU_ADD, 1,0,1, 2'b00,0, 32'd4, 1, 2, 0);

        // ---------------------------------------------------------------------
        // 7. Upper Immediate Instructions (LUI / AUIPC)
        // ---------------------------------------------------------------------
        // LUI x26, 0x12345
        instr_i = encode_u(20'h12345, 5'd26, `OPCODE_LUI);
        check_outputs("LUI", 1,0,0,0,0,0,0, `ALU_PASS_B, 1,0,1, 2'b00,0, 32'h1234_5000, 26, 0, 0);

        // AUIPC x27, 0xABCDE
        instr_i = encode_u(20'hABCDE, 5'd27, `OPCODE_AUIPC);
        check_outputs("AUIPC", 1,0,0,0,0,0,0, `ALU_ADD, 1,1,1, 2'b00,0, 32'hABCD_E000, 27, 0, 0);

        // ---------------------------------------------------------------------
        // 8. Invalid Instruction Handling
        // ---------------------------------------------------------------------
        // Reserved/Illegal Opcode
        instr_i = 32'h0000_0000;
        check_outputs("Invalid Opcode", 0,0,0,0,0,0,1, `ALU_ADD, 0,0,0, 2'b00,0, 32'h0, 0, 0, 0);

        // Invalid funct7 in R-Type ADD/SUB
        instr_i = encode_r(7'b1111111, 5'd2, 5'd1, `FUNCT3_ADD_SUB, 5'd3, `OPCODE_OP);
        check_outputs("Invalid Funct7 R-type", 1,0,0,0,0,0,1, `ALU_ADD, 0,0,1, 2'b00,0, 32'h0, 3, 1, 2);

        // Summary
        $display("==========================================================");
        $display("  TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0) begin
            $display(">>> ALL TESTS PASSED SUCCESSFULLY! <<<");
        end else begin
            $display(">>> SOME TESTS FAILED - CHECK TRANSCRIPT <<<");
        end

        $finish;
    end

endmodule