`timescale 1ns/1ps

module tb_systolic;

    // ------------------------------------------------------------------------
    // 1. Parameters & Signals
    // ------------------------------------------------------------------------
    localparam int MATRIX_SIZE = 4;
    localparam int DATA_WIDTH  = 4;
    localparam int PSUM_WIDTH  = 4; // Using 16-bit to prevent overflow [cite: 668]

    localparam int LIN_SIZE = MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH;

    logic clk;
    logic rst;
    logic start;
    
    // Flat 128-bit input (64 bits for A, 64 bits for B)
    logic [2 * LIN_SIZE - 1 : 0] input_data; 
    
    // Flat 64-bit output
    logic [LIN_SIZE - 1 : 0]     output_data;
    logic valid;

    // 2D Arrays to make test vector assignment human-readable
    logic [DATA_WIDTH - 1 : 0] test_mat_A [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1];
    logic [DATA_WIDTH - 1 : 0] test_mat_B [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1];
    logic [DATA_WIDTH - 1 : 0] out_mat_Y  [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1];

    // ------------------------------------------------------------------------
    // 2. Instantiate the Device Under Test (DUT)
    // ------------------------------------------------------------------------
    systolic #(
        .MATRIX_SIZE(MATRIX_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .PSUM_WIDTH(PSUM_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .input_data(input_data),
        .output_data(output_data),
        .valid(valid)
    );

    // ------------------------------------------------------------------------
    // 3. Clock Generation (100 MHz)
    // ------------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------------
    // 4. Test Sequence / Stimulus
    // ------------------------------------------------------------------------
    initial begin
        // --- Initialization ---
        rst   = 1;
        start = 0;
        input_data = '0;

        // Initialize Test Matrices
        // Matrix A (Inputs) - Filled with 1s and 2s
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                test_mat_A[i][j] = (i + j) % 3 + 1; // Arbitrary small values
            end
        end

        // Matrix B (Weights) - Identity Matrix for easy verification
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                if (i == j) test_mat_B[i][j] = 4'd1;
                else        test_mat_B[i][j] = 4'd0;
            end
        end

        // Pack 2D matrices into the flat Big-Endian 1D vector
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                // Pack A into upper half [127:64]
                input_data[2*LIN_SIZE - 1 - (i*MATRIX_SIZE + j)*DATA_WIDTH -: DATA_WIDTH] = test_mat_A[i][j];
                // Pack B into lower half [63:0]
                input_data[LIN_SIZE - 1 - (i*MATRIX_SIZE + j)*DATA_WIDTH -: DATA_WIDTH] = test_mat_B[i][j];
            end
        end

        // --- Release Reset ---
        #20;
        rst = 0;
        
        // --- Start the computation ---
        #10;
        $display("[%0t] Triggering start signal...", $time);
        start = 1;
        
        #10;
        start = 0; // De-assert start (pulse)

        // --- Wait for calculation to complete ---
        // The array takes (3 * MATRIX_SIZE - 1) cycles + output registering cycles
        wait(valid == 1'b1);
        $display("[%0t] Valid output detected!", $time);

        // Wait a couple more cycles to ensure the full sampling window completes
        #20; 
        
        // Unpack the flat output string into a 2D matrix for printing
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                out_mat_Y[i][j] = output_data[LIN_SIZE - 1 - (i*MATRIX_SIZE + j)*DATA_WIDTH -: DATA_WIDTH];
            end
        end

        // --- Display Results ---
        $display("\n--- MATRIX A (INPUTS) ---");
        print_matrix(test_mat_A);

        $display("\n--- MATRIX B (WEIGHTS) ---");
        print_matrix(test_mat_B);

        $display("\n--- MATRIX Y (OUTPUTS) ---");
        print_matrix(out_mat_Y);

        $display("\n--- Simulation Complete ---");
        $finish;
    end

    // ------------------------------------------------------------------------
    // 5. Helper Task to Print 4x4 Matrices
    // ------------------------------------------------------------------------
    task print_matrix(input logic [DATA_WIDTH - 1 : 0] mat [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1]);
        begin
            for (int i = 0; i < MATRIX_SIZE; i++) begin
                $display("  [%2d] [%2d] [%2d] [%2d]", mat[i][0], mat[i][1], mat[i][2], mat[i][3]);
            end
        end
    endtask

endmodule
