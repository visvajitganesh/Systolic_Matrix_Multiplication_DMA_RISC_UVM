`include "riscv_defs.sv"

module riscv_decode
(
    input                   [31:0] instr_i,

    output logic                   is_alu_o,        // R-type or I-type ALU op
    output logic                   is_load_o,
    output logic                   is_store_o,
    output logic                   is_branch_o,
    output logic                   is_jal_o,
    output logic                   is_jalr_o,
    output logic                   invalid_o,       // unrecognized opcode

    output logic [`ALU_OP_W - 1:0] alu_op_o,
    output logic                   alu_src_b_imm_o, // 1 = operand_b comes from immediate, not rb
    output logic                   alu_src_a_pc_o,  // 1 = operand_a comes from PC, not rs1

    output logic             [4:0] rd_o,
    output logic             [4:0] rs1_o,
    output logic             [4:0] rs2_o,
    output logic                   rd_valid_o,      // does this instruction write rd?

    output logic             [2:0] branch_funct3_o,

    output logic             [1:0] mem_size_o,      // 00=byte, 01=half, 10=word
    output logic                   mem_unsigned_o,  // 1 = zero-extend (LBU/LHU), 0 = sign-extend

    output logic            [31:0] imm_o            // sign-extended immediate
);

    always_comb begin

        is_alu_o    = 1'b0;
        is_load_o   = 1'b0;
        is_store_o  = 1'b0;
        is_branch_o = 1'b0;
        is_jal_o    = 1'b0;
        is_jalr_o   = 1'b0;
        invalid_o   = 1'b0;

        alu_op_o        = `ALU_ADD;
        alu_src_b_imm_o = 1'b0;
        alu_src_a_pc_o  = 1'b0;
        rd_valid_o      = 1'b0;

        mem_size_o     = '0;
        mem_unsigned_o =  0;

        case (instr_i[`OPCODE_R])
            `OPCODE_OP     : begin
                is_alu_o   = 1'b1;
                rd_valid_o = 1'b1;

                case (instr_i[`FUNCT3_R])
                    `FUNCT3_ADD_SUB : begin
                        if (instr_i[`FUNCT7_R] == `FUNCT7_ADD)
                            alu_op_o = `ALU_ADD;
                        else if (instr_i[`FUNCT7_R] == `FUNCT7_SUB)
                            alu_op_o = `ALU_SUB;
                        else
                            invalid_o = 1'b1;
                    end
                    
                    `FUNCT3_SLT     : alu_op_o = `ALU_SLT;

                    `FUNCT3_SLTU    : alu_op_o = `ALU_SLTU;

                    `FUNCT3_AND     : alu_op_o = `ALU_AND;

                    `FUNCT3_OR      : alu_op_o = `ALU_OR;

                    `FUNCT3_XOR     : alu_op_o = `ALU_XOR;

                    `FUNCT3_SLL     : alu_op_o = `ALU_SLL;

                    `FUNCT3_SRL_SRA : begin 
                        if (instr_i[`FUNCT7_R] == `FUNCT7_SRL)
                            alu_op_o = `ALU_SRL;
                        else if (instr_i[`FUNCT7_R] == `FUNCT7_SRA)
                            alu_op_o = `ALU_SRA;
                        else
                            invalid_o = 1'b1;
                    end

                    default         : invalid_o = 1'b1;
                endcase
            end

            `OPCODE_OP_IMM : begin 
                is_alu_o        = 1'b1;
                rd_valid_o      = 1'b1;
                alu_src_b_imm_o = 1'b1;

                case (instr_i[`FUNCT3_R])
                    `FUNCT3_ADD_SUB : alu_op_o = `ALU_ADD;

                    `FUNCT3_SLT     : alu_op_o = `ALU_SLT;

                    `FUNCT3_SLTU    : alu_op_o = `ALU_SLTU;

                    `FUNCT3_AND     : alu_op_o = `ALU_AND;
                    
                    `FUNCT3_XOR     : alu_op_o = `ALU_XOR;
                    
                    `FUNCT3_OR      : alu_op_o = `ALU_OR;
                    
                    `FUNCT3_SLL     : alu_op_o = `ALU_SLL;
                    
                    `FUNCT3_SRL_SRA : begin
                        if (instr_i[`FUNCT7_R] == `FUNCT7_SRL)
                            alu_op_o = `ALU_SRL;
                        else if (instr_i[`FUNCT7_R] == `FUNCT7_SRA)
                            alu_op_o = `ALU_SRA;
                        else
                            invalid_o = 1'b1;
                    end

                    default         : invalid_o = 1'b1;
                endcase
            end
            
            `OPCODE_LOAD   : begin 
                is_load_o       = 1'b1;
                rd_valid_o      = 1'b1;
                alu_src_b_imm_o = 1'b1;
                alu_op_o        = `ALU_ADD;

                case (instr_i[`FUNCT3_R]) 
                    `FUNCT3_WORD   : begin
                        mem_size_o     = 2'b10;
                        mem_unsigned_o = 1'b0;
                    end

                    `FUNCT3_HALF   : begin
                        mem_size_o     = 2'b01;
                        mem_unsigned_o = 1'b0;
                    end

                    `FUNCT3_BYTE   : begin
                        mem_size_o     = 2'b00;
                        mem_unsigned_o = 1'b0;
                    end

                    `FUNCT3_HALF_U : begin
                        mem_size_o     = 2'b01;
                        mem_unsigned_o = 1'b1;
                    end

                    `FUNCT3_BYTE_U : begin
                        mem_size_o     = 2'b00;
                        mem_unsigned_o = 1'b1;
                    end 

                    default        : invalid_o = 1'b1; 
                endcase
            end

            `OPCODE_STORE  : begin 
                is_store_o      = 1'b1;
                alu_src_b_imm_o = 1'b1;
                alu_op_o        = `ALU_ADD;

                case (instr_i[`FUNCT3_R]) 
                    `FUNCT3_WORD   : begin
                        mem_size_o     = 2'b10;
                        mem_unsigned_o = 1'b0;
                    end

                    `FUNCT3_HALF   : begin
                        mem_size_o     = 2'b01;
                        mem_unsigned_o = 1'b0;
                    end

                    `FUNCT3_BYTE   : begin
                        mem_size_o     = 2'b00;
                        mem_unsigned_o = 1'b0;
                    end

                    default        : invalid_o = 1'b1; 
                endcase
            end
                
            `OPCODE_BRANCH : begin 
                is_branch_o = 1'b1;
                
                case (instr_i[`FUNCT3_R])
                    `FUNCT3_BEQ  : alu_op_o  = `ALU_SUB;
                    `FUNCT3_BNE  : alu_op_o  = `ALU_SUB;
                    `FUNCT3_BLT  : alu_op_o  = `ALU_SLT;
                    `FUNCT3_BGE  : alu_op_o  = `ALU_SLT;
                    `FUNCT3_BLTU : alu_op_o  = `ALU_SLTU;
                    `FUNCT3_BGEU : alu_op_o  = `ALU_SLTU;
                    default      : invalid_o = 1'b1;
                endcase
            end

            `OPCODE_JAL    : begin 
                is_jal_o        = 1'b1;
                rd_valid_o      = 1'b1;
                alu_src_a_pc_o  = 1'b1;
                alu_src_b_imm_o = 1'b1;
                alu_op_o        = `ALU_ADD;
            end

            `OPCODE_JALR   : begin
                is_jalr_o       = 1'b1;
                rd_valid_o      = 1'b1;
                alu_src_b_imm_o = 1'b1;
                alu_op_o        = `ALU_ADD;
            end

            `OPCODE_LUI    : begin
                is_alu_o        = 1'b1;
                rd_valid_o      = 1'b1;
                alu_src_b_imm_o = 1'b1;
                alu_op_o        = `ALU_PASS_B;
            end

            `OPCODE_AUIPC  : begin
                is_alu_o        = 1'b1;
                rd_valid_o      = 1'b1;
                alu_src_a_pc_o  = 1'b1;
                alu_src_b_imm_o = 1'b1;
                alu_op_o        = `ALU_ADD;
            end

            default        : invalid_o   = 1'b1;
        endcase
    end

    assign rd_o  = instr_i[`RD_R];
    assign rs1_o = instr_i[`RS1_R];
    assign rs2_o = instr_i[`RS2_R];

    always_comb begin
        case (instr_i[`OPCODE_R])
            `OPCODE_OP_IMM  : imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
            `OPCODE_LOAD    : imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
            `OPCODE_STORE   : imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
            `OPCODE_BRANCH  : imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
            `OPCODE_JAL     : imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
            `OPCODE_JALR    : imm_o = {{20{instr_i[31]}}, instr_i[31:20]}; 
            `OPCODE_LUI     : imm_o = {instr_i[31:12], 12'b0}; 
            `OPCODE_AUIPC   : imm_o = {instr_i[31:12], 12'b0};
            default         : imm_o = '0;
        endcase
    end

    assign branch_funct3_o = instr_i[`FUNCT3_R];

endmodule