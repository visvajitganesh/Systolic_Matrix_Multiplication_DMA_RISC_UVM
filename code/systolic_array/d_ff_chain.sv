module d_ff_chain #(
    parameter DATA_WIDTH = 4,
    parameter DEPTH      = 1
)(
    input logic clk,
    input logic rst,
    input logic en,
    
    input  logic [DATA_WIDTH - 1 : 0] din,
    output logic [DATA_WIDTH - 1 : 0] dout
);

    logic [DATA_WIDTH - 1 : 0] data_wire [0 : DEPTH];

    assign data_wire[0] = din;
    assign dout         = data_wire[DEPTH];

    genvar i;

    generate
        for (i = 0; i < DEPTH; i++) begin : g_dff_chain
            dff #(
                .DATA_WIDTH(DATA_WIDTH)
            ) dff_inst (
                .clk (clk),
                .rst (rst),
                .en  (en),
                .din (data_wire[i]),
                .dout(data_wire[i + 1])
            );
        end
    endgenerate
endmodule