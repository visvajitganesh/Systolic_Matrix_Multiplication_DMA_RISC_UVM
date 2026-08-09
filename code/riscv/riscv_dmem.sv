module riscv_dmem
#(
    parameter DEPTH = 1024,
    parameter INIT_FILE = ""
)(
    input               clk_i,
    input        [31:0] addr_i,
    input        [31:0] wdata_i,
    input         [3:0] wstrb_i,
    output logic [31:0] rdata_o
);

    logic [31:0] mem [0:DEPTH - 1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
            // if no file given, mem starts as 'x (unknown) in simulation --
            // real hardware wouldn't guarantee zeros either, so for a clean
            // testbench you may want an else-branch that zero-fills instead:
        else
            for (int i = 0; i < DEPTH; i++) mem[i] = 32'b0;
    end

    always @(posedge clk_i) begin
        rdata_o <= mem[addr_i[31:2]];

        if (wstrb_i[0]) 
            mem[addr_i[31:2]][7:0]   <= wdata_i[7:0];
        if (wstrb_i[1]) 
            mem[addr_i[31:2]][15:8]  <= wdata_i[15:8];
        if (wstrb_i[2]) 
            mem[addr_i[31:2]][23:16] <= wdata_i[23:16];
        if (wstrb_i[3]) 
            mem[addr_i[31:2]][31:24] <= wdata_i[31:24];
    end

endmodule
