`include "riscv_defs.sv"

module riscv_imem
#(
    parameter DEPTH     = 1024,   // number of 32-bit words
    parameter INIT_FILE = ""      // path to a hex file, empty = no preload
)(
    input               clk_i,
    input        [31:0] addr_i,
    output logic [31:0] rdata_o
);

    logic [31:0] mem [0:DEPTH - 1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    always_ff @(posedge clk_i)
        rdata_o <= mem[addr_i[31:2]];   // word-addressed: drop the byte-offset bits

endmodule