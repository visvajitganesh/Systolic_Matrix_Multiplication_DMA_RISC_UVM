// Takes a cycle to read an instruction
module riscv_imem
#(
    parameter DEPTH     = 1024,   // number of 32-bit words
    parameter INIT_FILE = ""      // path to a hex file, empty = no preload
)(
    input               clk_i,
    input               rst_i,                // Active-High Reset
    input        [31:0] addr_i,

    output logic [31:0] rdata_o,
    output logic        error_unaligned_o,    // 1 = Misaligned fetch attempt    
    output logic        error_out_of_bounds_o // 1 = Address exceeds memory DEPTH
);
    // Memory array storage 
    logic [31:0] mem [0:DEPTH - 1];

    // Pre-load memory if hex file is provided
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // Combinational address checking logic
    logic error_unaligned_w;
    logic error_out_of_bounds_w;

    assign error_unaligned_w     = (addr_i[1:0] != 2'b00);
    assign error_out_of_bounds_w = (addr_i[31:2] >= DEPTH);

    // Synchronous memory read and exception flagging
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            rdata_o               <= 32'h0000_0013; // Safe reset state: NOP (addi x0, x0, 0)
            error_unaligned_o     <= 1'b0;
            error_out_of_bounds_o <= 1'b0;
        end
        else begin
            // Register error signals
            error_unaligned_o     <= error_unaligned_w;
            error_out_of_bounds_o <= error_out_of_bounds_w;

            // Safe memory read access
            if (!error_unaligned_w && !error_out_of_bounds_w) begin
                rdata_o <= mem[addr_i[31:2]];  // word-addressed: drop the byte-offset bits
            end
            else begin
                rdata_o <= 32'h0000_0013;      // Substitute NOP during illegal access to prevent 'x propagation
            end
        end
    end
endmodule
