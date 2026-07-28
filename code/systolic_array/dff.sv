module dff #(
    parameter DATA_WIDTH = 4
)(
    input clk,
    input rst,

    input en,

    input  logic [DATA_WIDTH - 1 : 0] din,

    output logic [DATA_WIDTH - 1 : 0] dout
);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            dout <= 'b0;
        end
        else begin
            if (en) // holds or updates new data
                dout <= din;
        end
    end
endmodule