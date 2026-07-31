`ifndef RISCV_DEFS_V
`define RISCV_DEFS_V

`define OPCODE_OP      7'b0110011  // R-type ALU: ADD, SUB, AND, OR, XOR, SLT
`define OPCODE_OP_IMM  7'b0010011  // I-type ALU: ADDI, ANDI, ORI, XORI, SLTI
`define OPCODE_LOAD    7'b0000011  // LW
`define OPCODE_STORE   7'b0100011  // SW
`define OPCODE_BRANCH  7'b1100011  // BEQ, BNE
`define OPCODE_JAL     7'b1101111  // JAL

// funct3 for OPCODE_OP / OPCODE_OP_IMM (ALU operations)
`define FUNCT3_ADD_SUB  3'b000  // ADD or SUB or ADDI (funct7 tells ADD vs SUB)
`define FUNCT3_SLT      3'b010  // set-less-than (signed)
`define FUNCT3_XOR      3'b100
`define FUNCT3_OR       3'b110
`define FUNCT3_AND      3'b111

// funct3 for OPCODE_BRANCH
`define FUNCT3_BEQ      3'b000
`define FUNCT3_BNE      3'b001

// funct3 for OPCODE_LOAD / OPCODE_STORE
`define FUNCT3_WORD     3'b010  // LW and SW both use this (word-sized access)

`define FUNCT7_ADD  7'b0000000
`define FUNCT7_SUB  7'b0100000

`define OPCODE_R   6:0
`define RD_R       11:7
`define FUNCT3_R   14:12
`define RS1_R      19:15
`define RS2_R      24:20
`define FUNCT7_R   31:25

`define ALU_OP_W    3
`define ALU_ADD     3'd0
`define ALU_SUB     3'd1
`define ALU_AND     3'd2
`define ALU_OR      3'd3
`define ALU_XOR     3'd4
`define ALU_SLT     3'd5

`endif