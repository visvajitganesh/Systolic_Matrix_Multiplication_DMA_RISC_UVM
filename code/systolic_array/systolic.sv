module systolic #(
    parameter MATRIX_SIZE = 4,
    parameter DATA_WIDTH  = 4,
    parameter PSUM_WIDTH  = 4
)(
    input  logic clk,
    input  logic rst_n,          

    input  logic start, //single pulse

    input  logic [2 * MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH - 1 : 0] input_data, // INPUT MATRICES A ( Input ) and B (weight) Big Endian. 

    output logic [    MATRIX_SIZE * MATRIX_SIZE * PSUM_WIDTH - 1 : 0] output_data,

    output logic done,
    output logic busy   // Handshake status: 1 = Computing, 0 = Ready for new matrix 
);

    localparam int IN_LIN_SIZE  = MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH;   
    localparam int OUT_LIN_SIZE = MATRIX_SIZE * MATRIX_SIZE * PSUM_WIDTH;   

    // Input Latch Register
    logic [2 * IN_LIN_SIZE - 1 : 0] input_data_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_data_reg <= '0;
        end 
        else if (start && !busy) begin
            input_data_reg <= input_data; // Latch input vector on start pulse when array is idle
        end
    end              

    // Linear & Matrix Unpacking

    logic [IN_LIN_SIZE - 1 : 0] arr_lin_A;
    logic [IN_LIN_SIZE - 1 : 0] arr_lin_B;

    assign arr_lin_A = input_data_reg[2 * IN_LIN_SIZE - 1 : IN_LIN_SIZE];
    assign arr_lin_B = input_data_reg[IN_LIN_SIZE - 1 : 0];

    logic [DATA_WIDTH - 1 : 0] arr_mat_A   [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1];
    logic [DATA_WIDTH - 1 : 0] arr_mat_B   [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1];
    logic [PSUM_WIDTH - 1 : 0] arr_mat_out [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1];

    always_comb begin
        for (int i = 0; i < MATRIX_SIZE; i++ ) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                // arr_mat_A[i][j] = arr_lin_A[(LIN_SIZE - 1) - (DATA_WIDTH * MATRIX_SIZE * i) - (DATA_WIDTH * j) : (LIN_SIZE - 1) - (DATA_WIDTH * MATRIX_SIZE * i) - (DATA_WIDTH * (j + 1)) + 1];
                arr_mat_A[i][j] = arr_lin_A[(IN_LIN_SIZE - 1) - (i * MATRIX_SIZE + j) * DATA_WIDTH -: DATA_WIDTH];

                // arr_mat_B[i][j] = arr_lin_B[(LIN_SIZE - 1) - (DATA_WIDTH * MATRIX_SIZE * i) - (DATA_WIDTH * j) : (LIN_SIZE - 1) - (DATA_WIDTH * MATRIX_SIZE * i) - (DATA_WIDTH * (j + 1)) + 1];
                arr_mat_B[i][j] = arr_lin_B[(IN_LIN_SIZE - 1) - (i * MATRIX_SIZE + j) * DATA_WIDTH -: DATA_WIDTH];
            end
        end
    end

    // Busy Logic Tracker

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
        end 
        else begin
            if (start) begin
                busy <= 1'b1; // Set busy when computation is triggered
            end 
            else if (done) begin
                busy <= 1'b0; // Clear busy when PE array completes
            end
        end
    end


    // Processing Element Array Instance

    pe_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .MATRIX_SIZE(MATRIX_SIZE),
        .PSUM_WIDTH(PSUM_WIDTH)
    ) dut (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(start),
        .A(arr_mat_A), 
        .B(arr_mat_B), 
        .OUT(arr_mat_out),
        .done(done)
    );

    // Output Vector Packing

    always_comb begin
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                output_data[(OUT_LIN_SIZE - 1) - (i * MATRIX_SIZE + j) * PSUM_WIDTH -: PSUM_WIDTH] = arr_mat_out[i][j];
            end
        end
    end
    
endmodule
