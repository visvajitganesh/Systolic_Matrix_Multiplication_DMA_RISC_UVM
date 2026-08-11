`include "riscv_defs.sv"

module tb_riscv_alu;

    localparam DATA_WIDTH = 32;
    localparam SHIFT_W    = $clog2(DATA_WIDTH);

    logic [`ALU_OP_W - 1:0] alu_op_i;
    logic [DATA_WIDTH - 1:0] operand_a_i;
    logic [DATA_WIDTH - 1:0] operand_b_i;
    logic [DATA_WIDTH - 1:0] result_o;

    int pass_count = 0;
    int fail_count = 0;

    riscv_alu #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .alu_op_i   (alu_op_i),
        .operand_a_i(operand_a_i),
        .operand_b_i(operand_b_i),
        .result_o   (result_o)
    );

    function automatic logic [DATA_WIDTH-1:0] get_expected(
        input logic [`ALU_OP_W-1:0]  op,
        input logic [DATA_WIDTH-1:0] a,
        input logic [DATA_WIDTH-1:0] b
    );
        logic [SHIFT_W-1:0] shamt;
        logic signed [DATA_WIDTH-1:0] signed_a;
        
        shamt    = b[SHIFT_W-1:0];
        signed_a = a;

        case (op)
            `ALU_ADD    : return a + b;
            `ALU_SUB    : return a - b;
            `ALU_AND    : return a & b;
            `ALU_OR     : return a | b;
            `ALU_XOR    : return a ^ b;
            `ALU_SLT    : return ($signed(a) < $signed(b)) ? {{(DATA_WIDTH-1){1'b0}}, 1'b1} : '0;
            `ALU_SLTU   : return (a < b) ? {{(DATA_WIDTH-1){1'b0}}, 1'b1} : '0;
            `ALU_SLL    : return a << shamt;
            `ALU_SRL    : return a >> shamt;
            `ALU_SRA    : return signed_a >>> shamt;
            `ALU_PASS_B : return b;
            default     : return '0;
        endcase
    endfunction

    task automatic check_alu(
        input logic [`ALU_OP_W-1:0]  op,
        input logic [DATA_WIDTH-1:0] a,
        input logic [DATA_WIDTH-1:0] b,
        input string                 test_name = ""
    );
        logic [DATA_WIDTH-1:0] expected;

        alu_op_i    = op;
        operand_a_i = a;
        operand_b_i = b;

        #1;

        expected = get_expected(op, a, b);

        if (result_o === expected) begin
            pass_count++;
        end else begin
            fail_count++;
            $display("[FAIL %0t] %s | Op: 0x%0h | A: 0x%0h | B: 0x%0h | Exp: 0x%0h | Got: 0x%0h",
                     $time, test_name, op, a, b, expected, result_o);
        end
    endtask

    initial begin
        $timeformat(-9, 0, " ns", 10);
        $display("--- STARTING RISC-V ALU TESTBENCH ---");

        // 1. Basic Operations
        check_alu(`ALU_ADD,    32'h0000_0005, 32'h0000_0003, "ADD basic");
        check_alu(`ALU_SUB,    32'h0000_000A, 32'h0000_0004, "SUB basic");
        check_alu(`ALU_AND,    32'hFFFF_0000, 32'h00FF_00FF, "AND basic");
        check_alu(`ALU_OR,     32'hF0F0_0000, 32'h0000_0F0F, "OR basic");
        check_alu(`ALU_XOR,    32'hAAAA_5555, 32'hFFFF_FFFF, "XOR basic");
        check_alu(`ALU_PASS_B, 32'h1234_5678, 32'h8765_4321, "PASS_B basic");

        // 2. Comparisons
        check_alu(`ALU_SLT,  32'hFFFF_FFFF, 32'h0000_0001, "SLT (-1 < +1)");
        check_alu(`ALU_SLTU, 32'hFFFF_FFFF, 32'h0000_0001, "SLTU (MAX_UINT < +1)");

        // 3. Shifts
        check_alu(`ALU_SLL, 32'h0000_0001, 32'd4, "SLL shift by 4");
        check_alu(`ALU_SRL, 32'h8000_0000, 32'd4, "SRL logical shift right");
        check_alu(`ALU_SRA, 32'h8000_0000, 32'd4, "SRA sign extension shift");

        // 4. Randomized Tests (License-Free using $urandom)
        repeat (500) begin
            logic [`ALU_OP_W-1:0]  rand_op;
            logic [DATA_WIDTH-1:0] rand_a;
            logic [DATA_WIDTH-1:0] rand_b;

            rand_op = $urandom_range(0, 10);
            rand_a  = $urandom();
            rand_b  = $urandom();

            check_alu(rand_op, rand_a, rand_b, "Randomized Test");
        end

        // Summary
        $display("------------------------------------------------");
        $display("TEST SUMMARY: PASSED = %0d | FAILED = %0d", pass_count, fail_count);
        $display("------------------------------------------------");

        $finish;
    end

endmodule
