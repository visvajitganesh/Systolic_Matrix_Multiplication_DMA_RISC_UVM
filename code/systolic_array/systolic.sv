module systolic #(
    parameter MATRIX_SIZE = 4,
    parameter DATA_WIDTH  = 4,
    parameter PSUM_WIDTH  = 4
)(
    input  logic clk,
    input  logic rst,          

    input  logic start,

    input  logic [2 * MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH - 1 : 0] input_data,      /// INPUT MATRICES A ( Input ) and B (weight) Big Endian. 

    output logic [    MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH - 1 : 0] output_data,

    output logic valid                                                                 ///  VALID HIGH  ----   Sample Output. 
);

    localparam int LIN_SIZE = MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH;                 

    logic [LIN_SIZE - 1 : 0] arr_lin_A;
    logic [LIN_SIZE - 1 : 0] arr_lin_B;

    assign arr_lin_A = input_data[2 * LIN_SIZE - 1 : LIN_SIZE];
    assign arr_lin_B = input_data[LIN_SIZE - 1 : 0];

    logic [DATA_WIDTH - 1 : 0] arr_mat_A   [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1];
    logic [DATA_WIDTH - 1 : 0] arr_mat_B   [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1];
    logic [DATA_WIDTH - 1 : 0] arr_mat_out [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1];

    always_comb begin
        for (int i = 0; i < MATRIX_SIZE; i++ ) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                // arr_mat_A[i][j] = arr_lin_A[(LIN_SIZE - 1) - (DATA_WIDTH * MATRIX_SIZE * i) - (DATA_WIDTH * j) : (LIN_SIZE - 1) - (DATA_WIDTH * MATRIX_SIZE * i) - (DATA_WIDTH * (j + 1)) + 1];
                arr_mat_A[i][j] = arr_lin_A[(LIN_SIZE - 1) - (i * MATRIX_SIZE + j) * DATA_WIDTH -: DATA_WIDTH];

                // arr_mat_B[i][j] = arr_lin_B[(LIN_SIZE - 1) - (DATA_WIDTH * MATRIX_SIZE * i) - (DATA_WIDTH * j) : (LIN_SIZE - 1) - (DATA_WIDTH * MATRIX_SIZE * i) - (DATA_WIDTH * (j + 1)) + 1];
                arr_mat_B[i][j] = arr_lin_B[(LIN_SIZE - 1) - (i * MATRIX_SIZE + j) * DATA_WIDTH -: DATA_WIDTH];
            end
        end
    end

    /*
    logic [DATA_WIDTH - 1 : 0] channel_A [0 : MATRIX_SIZE - 1][0 : 2 * MATRIX_SIZE - 2];
    // logic [DATA_WIDTH - 1 : 0] channel_B [0 : MATRIX_SIZE - 1][0 : 2 * MATRIX_SIZE - 2]; // Weights stationary

    always_comb begin
        channel_A = '{default: '0};

        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                channel_A[i][j + (MATRIX_SIZE - 1) - i] = arr_mat_A[i][j];
            end
        end
    end
    */

    pe_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .MATRIX_SIZE(MATRIX_SIZE),
        .PSUM_WIDTH(PSUM_WIDTH)
    ) dut (
        .clk(clk), 
        .rst(rst), 
        .start(start),
        .A(arr_mat_A), 
        .B(arr_mat_B), 
        .OUT(arr_mat_out),
        .valid(valid)
    );

    always_comb begin
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                output_data[(LIN_SIZE - 1) - (i * MATRIX_SIZE + j) * DATA_WIDTH -: DATA_WIDTH] = arr_mat_out[i][j];
            end
        end
    end
    
endmodule
