`ifndef RISCV_DEFS_V
`define RISCV_DEFS_V

`define OPCODE_OP      7'b0110011  // R-type ALU: ADD, SUB, AND, OR, XOR, SLT
`define OPCODE_OP_IMM  7'b0010011  // I-type ALU: ADDI, ANDI, ORI, XORI, SLTI
`define OPCODE_LOAD    7'b0000011  // LW
`define OPCODE_STORE   7'b0100011  // SW
`define OPCODE_BRANCH  7'b1100011  // BEQ, BNE
`define OPCODE_JAL     7'b1101111  // JAL
`define OPCODE_JALR    7'b1100111
`define OPCODE_LUI     7'b0110111
`define OPCODE_AUIPC   7'b0010111


// funct3 for OPCODE_OP / OPCODE_OP_IMM (ALU operations)
`define FUNCT3_ADD_SUB  3'b000  // ADD or SUB or ADDI (funct7 tells ADD vs SUB)
`define FUNCT3_SLT      3'b010  // set-less-than (signed)
`define FUNCT3_XOR      3'b100
`define FUNCT3_OR       3'b110
`define FUNCT3_AND      3'b111
`define FUNCT3_SLL      3'b001
`define FUNCT3_SLTU     3'b011
`define FUNCT3_SRL_SRA  3'b101

// funct3 for OPCODE_BRANCH
`define FUNCT3_BEQ      3'b000
`define FUNCT3_BNE      3'b001
`define FUNCT3_BLT      3'b100
`define FUNCT3_BGE      3'b101
`define FUNCT3_BLTU     3'b110
`define FUNCT3_BGEU     3'b111

// funct3 for OPCODE_LOAD / OPCODE_STORE
`define FUNCT3_BYTE     3'b000  // LB / SB
`define FUNCT3_HALF     3'b001  // LH / SH
`define FUNCT3_WORD     3'b010  // LW and SW both use this (word-sized access)
`define FUNCT3_BYTE_U   3'b100  // LBU
`define FUNCT3_HALF_U   3'b101  // LHU 

`define FUNCT7_ADD  7'b0000000
`define FUNCT7_SUB  7'b0100000
`define FUNCT7_SRL  7'b0000000
`define FUNCT7_SRA  7'b0100000


`define OPCODE_R   6:0
`define RD_R       11:7
`define FUNCT3_R   14:12
`define RS1_R      19:15
`define RS2_R      24:20
`define FUNCT7_R   31:25

`define ALU_OP_W    4
`define ALU_ADD     4'd0
`define ALU_SUB     4'd1
`define ALU_AND     4'd2
`define ALU_OR      4'd3
`define ALU_XOR     4'd4
`define ALU_SLT     4'd5
`define ALU_SLTU    4'd6
`define ALU_SLL     4'd7
`define ALU_SRL     4'd8
`define ALU_SRA     4'd9
`define ALU_PASS_B  4'd10

`endif