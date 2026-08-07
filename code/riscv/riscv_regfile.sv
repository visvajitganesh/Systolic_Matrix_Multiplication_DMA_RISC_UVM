module riscv_regfile #(
    parameter DATA_WIDTH = 32
)(
    input                           clk_i,
    input                           rst_i,

    input        [4:0]              rd0_i,        // write address
    input        [DATA_WIDTH - 1:0] rd0_value_i,  // write data
    input                           rd0_wren_i,   // write enable  <-- think about whether you need this, see below

    input        [4:0]              ra0_i,        // read address 1
    input        [4:0]              rb0_i,        // read address 2
    output       [DATA_WIDTH - 1:0] ra0_value_o,  // read data 1
    output       [DATA_WIDTH - 1:0] rb0_value_o   // read data 2
);

    logic [DATA_WIDTH - 1:0] r_xx [0:31]; 

    always_ff @(posedge clk_i or posedge rst_i) begin : regfile
        if (rst_i) begin
            r_xx <= '{default: '0};
        end
        else if (rd0_wren_i && (rd0_i != 5'b00000)) begin
            r_xx[rd0_i] <= rd0_value_i;
        end
    end

    assign ra0_value_o = (ra0_i == 5'b00000) ? '0 : r_xx[ra0_i];
    assign rb0_value_o = (rb0_i == 5'b00000) ? '0 : r_xx[rb0_i];

endmodule
