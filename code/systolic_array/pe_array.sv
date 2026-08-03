module pe_array #(
    parameter int MATRIX_SIZE = 4,
    parameter int DATA_WIDTH  = 4,
    parameter int PSUM_WIDTH  = 4 
)(
    input  logic clk,
    input  logic rst,

    input  logic start,

    // 2D Input Matrices
    input  logic [DATA_WIDTH - 1 : 0] A [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1],
    input  logic [DATA_WIDTH - 1 : 0] B [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1],

    // Parallel Output Matrix
    output logic [DATA_WIDTH - 1 : 0] OUT [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1],

    output logic valid
);

    // ------------------------------------------------------------------------
    // 1. Control Logic & Counter
    // ------------------------------------------------------------------------

    logic [$clog2(3 * MATRIX_SIZE) - 1 : 0] counter;
    logic running;

    logic pe_en;

    always_ff @(posedge clk or negedge rst_n) begin
        if (rst_n) begin
            running <= 1'b0;
        end else if ( start) begin
            running <= 1'b1;
        end else if ( counter == (3* MATRIX_SIZE - 1)) begin
            running <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (rst_n) begin
            counter <= '0;
        end 
        else if (running || start) begin
            if (counter < (3 * MATRIX_SIZE - 1)) begin
                counter <= counter + 1'b1;
            end
            else begin
                counter <= '0;
            end
        end 
        else begin
            counter <= '0;
        end
    end

    // Enable signal
    assign pe_en = running || start;

    // ------------------------------------------------------------------------
    // 2. Input Skewing Chains (Horizontal Input Delay for A)
    // ------------------------------------------------------------------------
    logic [DATA_WIDTH - 1 : 0] A_transposed [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE - 1];

    always_comb begin
        for (int r = 0; r < MATRIX_SIZE; r++) begin
            for (int c = 0; c < MATRIX_SIZE; c++) begin
                A_transposed[r][c] = A[c][r]; // Transposes A (swaps rows and columns)
            end
        end
    end

    logic [DATA_WIDTH - 1 : 0] data_in_A          [0 : MATRIX_SIZE - 1];
    logic [DATA_WIDTH - 1 : 0] data_in_skewed_A   [0 : MATRIX_SIZE - 1];

    // Load inputs for current cycle based on counter
    genvar row;

    generate
        for (row = 0; row < MATRIX_SIZE; row++) begin : g_input_mux
            assign data_in_A[row] = (pe_en && (counter < MATRIX_SIZE)) 
                                  ? A_transposed[row][counter] 
                                  : '0;
        end
    endgenerate

    // Row 0 has NO delay
    assign data_in_skewed_A[0] = data_in_A[0];

    // Rows 1 to N-1 use flip-flop chains of depth 'k'
    genvar k;

    generate
        for (k = 1; k < MATRIX_SIZE; k++) begin : input_skew
            d_ff_chain #(
                .DATA_WIDTH(DATA_WIDTH),
                .DEPTH(k)
            ) d_ff_skew_in (
                .clk (clk),
                .rst (rst),
                .en  (pe_en),
                .din (data_in_A[k]),
                .dout(data_in_skewed_A[k])
            );
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 3. Systolic Interconnect Wires
    // ------------------------------------------------------------------------
    // Horizontal activation streaming [rows][cols+1]
    logic [DATA_WIDTH - 1 : 0] a_wire [0 : MATRIX_SIZE - 1][0 : MATRIX_SIZE];
    
    // Vertical partial sum streaming [rows+1][cols]
    logic [PSUM_WIDTH - 1 : 0] psum_wire [0 : MATRIX_SIZE][0 : MATRIX_SIZE - 1];

    // Connect skewed inputs to leftmost PE column
    genvar i_in;
    generate
        for (i_in = 0; i_in < MATRIX_SIZE; i_in++) begin : g_left_in
            assign a_wire[i_in][0] = data_in_skewed_A[i_in];
        end
    endgenerate

    // Top boundary partial sums initialized to 0
    genvar j_in;
    generate
        for (j_in = 0; j_in < MATRIX_SIZE; j_in++) begin : g_top_in
            assign psum_wire[0][j_in] = '0;
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 4. 2D PE Array Instantiation
    // ------------------------------------------------------------------------
    genvar r, c;
    generate
        for (r = 0; r < MATRIX_SIZE; r++) begin : g_pe_row
            for (c = 0; c < MATRIX_SIZE; c++) begin : g_pe_col
                processing_element #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .PSUM_WIDTH(PSUM_WIDTH)
                ) u_pe (
                    .clk       (clk),
                    .rst       (rst),
                    
                    // Horizontal activation flow
                    .in        (a_wire[r][c]),
                    .a_out     (a_wire[r][c+1]),
                    
                    // Stationary or passed weights
                    .weight    (B[r][c]), // Weights stationary directly from B
                    
                    .pe_en     (pe_en),
                    
                    // Vertical partial sum flow
                    .psum_in   (psum_wire[r][c]),
                    .psum_out  (psum_wire[r+1][c])
                );
            end
        end
    endgenerate

    // ------------------------------------------------------------------------
    // 5. Output Un-skewing & Sampling Block
    // ------------------------------------------------------------------------

    
    logic [PSUM_WIDTH - 1 : 0] data_out_skewed    [0 : MATRIX_SIZE - 1];
    logic [PSUM_WIDTH - 1 : 0] data_out_unskewed  [0 : MATRIX_SIZE - 1];

    // Grab raw outputs emerging from bottom row of PE array
    genvar col;
    generate
        for (col = 0; col < MATRIX_SIZE; col++) begin : g_out_assign
            assign data_out_skewed[col] = psum_wire[MATRIX_SIZE][col];
        end
    endgenerate

    // Column (N-1) has NO output delay
    assign data_out_unskewed[MATRIX_SIZE - 1] = data_out_skewed[MATRIX_SIZE - 1];

    // Columns 0 to N-2 use un-skew delay chains of depth (N - 1 - col)
    genvar out_col;
    generate
        for (out_col = 0; out_col < MATRIX_SIZE - 1; out_col++) begin : output_unskew
            d_ff_chain #(
                .DATA_WIDTH(PSUM_WIDTH),
                .DEPTH(MATRIX_SIZE - 1 - out_col)
            ) d_ff_unskew_out (
                .clk (clk),
                .rst (rst),
                .en  (pe_en),
                .din (data_out_skewed[out_col]),
                .dout(data_out_unskewed[out_col]) // Re-aligned row output
            );
        end
    endgenerate

    localparam int START_OUT_CYCLE = 2 * MATRIX_SIZE - 1;
    localparam int END_OUT_CYCLE   = 3 * MATRIX_SIZE - 2;

    // Calculate row index directly from main counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (rst_n) begin
            OUT <= '{default: '0};
        end 
        else if (running && (counter >= START_OUT_CYCLE) && (counter <= END_OUT_CYCLE)) begin
            for (int col_idx = 0; col_idx < MATRIX_SIZE; col_idx++) begin
                OUT[counter - START_OUT_CYCLE][col_idx] <= data_out_unskewed[col_idx];
            end
        end
    end

    // Valid signal active during the sampling window
    //assign valid = running && (counter >= START_OUT_CYCLE + 1) && (counter <= END_OUT_CYCLE + 1);
    assign valid = running && (counter == END_OUT_CYCLE + 1);

endmodule
