module riscv_alu #(
    parameter DATA_WIDTH = 32
)(
    input  logic [`ALU_OP_W  - 1:0] alu_op_i,
    input  logic [DATA_WIDTH - 1:0] operand_a_i,
    input  logic [DATA_WIDTH - 1:0] operand_b_i,
    output logic [DATA_WIDTH - 1:0] result_o
);

    localparam SHIFT_W = $clog2(DATA_WIDTH);   ///shift amount held in the lower 5 bits of operand_b_i.

    always_comb begin

        unique case (alu_op_i)
            `ALU_ADD    : result_o = operand_a_i + operand_b_i;                                                               ///ADDITION
            `ALU_SUB    : result_o = operand_a_i - operand_b_i;                                                               ///SUBTRACTION
            `ALU_AND    : result_o = operand_a_i & operand_b_i;                                                               ///AND
            `ALU_OR     : result_o = operand_a_i | operand_b_i;                                                               ///OR
            `ALU_XOR    : result_o = operand_a_i ^ operand_b_i;                                                               ///XOR
            `ALU_SLT    : result_o = ($signed(operand_a_i) < $signed(operand_b_i)) ? {{(DATA_WIDTH-1){1'b0}}, 1'b1} : '0;     ///Signed Comparison
            `ALU_SLTU   : result_o = operand_a_i < operand_b_i ? {{(DATA_WIDTH-1){1'b0}}, 1'b1} : '0;                         ///Unsigned Comparision
            `ALU_SLL    : result_o = operand_a_i << operand_b_i[SHIFT_W - 1:0];                                               ///Logical Left Shift
            `ALU_SRL    : result_o = operand_a_i >> operand_b_i[SHIFT_W - 1:0];                                               ///Logical Right Shift
            `ALU_SRA    : result_o = $signed(operand_a_i) >>> operand_b_i[SHIFT_W - 1:0];                                     ///Arithmetic Right Shift
            `ALU_PASS_B : result_o = operand_b_i;
            default     : result_o = 'b0;

        endcase
    end

endmodule
