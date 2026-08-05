`timescale 1ns / 1ps


// Bridges the Systolic Array output edge (clk_accel, 64-bit parallel matrix) 
// to the DMA write channel (clk_sys, AXI-Stream 4-bit nibble stream).
// Utilizes an FSM and a holding register to serialize 64-bit parallel 
// outputs into 16 sequential 4-bit nibbles stored inside an async_fifo.

module output_fifo #(
    parameter int DATA_WIDTH   = 4,   // Stream width towards DMA (4-bit nibble)
    parameter int DATA_WIDTH_M = 4,   // PSUM element width from systolic array (PSUM_WIDTH = 4)
    parameter int MATRIX_SIZE  = 4,   // Matrix dimension N = 4
    parameter int DEPTH        = 32   // FIFO depth (must be a power of 2)
)(
    // Clock and Reset Domains
    input  logic                      clk_sys,       // System Clock Domain (DMA side)
    input  logic                      rst_sys_n,     // System Reset (Active-Low)
    input  logic                      clk_accel,     // Accelerator Clock Domain
    input  logic                      rst_accel_n,   // Accelerator Reset (Active-Low)

    // SYSTOLIC ARRAY SIDE: Parallel Output Handshaking (clk_accel domain)
   
    input  logic [MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH_M - 1 : 0] array_data, // 64-bit parallel matrix output from array
    input  logic                      array_valid,   // Connects to systolic array 'done' signal
    output logic                      array_ready,   // Backpressure indicator to systolic array

   
    // DMA / SYSTEM SIDE: AXI-Stream Protocol Signals (clk_sys domain)
    
    output logic [DATA_WIDTH-1:0]     tdata,         // 4-bit serial nibble output to DMA
    output logic                      tvalid,        // Data valid signal to DMA
    input  logic                      tready,        // DMA ready handshake input
    output logic                      tlast          // Packet boundary indicator
);

    // Local parameters for serialization
    localparam int TOTAL_ELEMENTS = MATRIX_SIZE * MATRIX_SIZE; // 16 nibbles total (64 bits / 4 bits)
    localparam int CNT_WIDTH      = $clog2(TOTAL_ELEMENTS);    // Counter width (4 bits for 0-15)

    // FSM State Definitions
    localparam IDLE = 1'b0;
    localparam PUSH = 1'b1;

    logic                      current_state, next_state;
    logic [CNT_WIDTH - 1:0]    counter;

    // Internal FIFO and Serialization control wires
    logic                      fifo_full;
    logic                      fifo_empty;
    logic [DATA_WIDTH - 1:0]   fifo_wr_data;
    logic                      fifo_wr_en;
    logic [DATA_WIDTH - 1:0]   fifo_rd_data;
    logic                      fifo_rd_en;

    // Holding register to latch the 64-bit parallel result matrix from the array
    logic [MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH_M - 1 : 0] holding_reg;

    // Array ready status: can accept new data when FSM is IDLE and FIFO has space
    assign array_ready = (current_state == IDLE) && !fifo_full;

    // Async FIFO instance safely bridging clk_accel (write) to clk_sys (read)
    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) u_async_fifo (
        .wr_clk   (clk_accel),
        .wr_rst_n (rst_accel_n),
        .wr_en    (fifo_wr_en),
        .wr_data  (fifo_wr_data),
        .full     (fifo_full),

        .rd_clk   (clk_sys),
        .rd_rst_n (rst_sys_n),
        .rd_en    (fifo_rd_en),
        .rd_data  (fifo_rd_data),
        .empty    (fifo_empty)
    );

    // AXI-Stream DMA Read Side (clk_sys domain)
   
    assign tvalid     = !fifo_empty;
    assign tdata      = fifo_rd_data;
    assign fifo_rd_en = tvalid && tready;
    assign tlast      = 1'b0; // Can be tied or driven based on packet layer tracking

   
    // FSM State Transition Logic (clk_accel domain)
  
    always_ff @(posedge clk_accel or negedge rst_accel_n) begin
        if (!rst_accel_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end


    // FSM Next State Combinational Logic
 
    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                // When systolic array completes computation (array_valid/done) and FIFO has room
                if (array_valid && !fifo_full) begin
                    next_state = PUSH;
                end
            end

            PUSH: begin
                // Return to IDLE once all 16 nibbles have been successfully written to FIFO
                if ((counter == TOTAL_ELEMENTS - 1) && fifo_wr_en) begin
                    next_state = IDLE;
                end
            end

            default: next_state = IDLE;
        endcase
    end

    // Serialization, Holding Register, and Counter Logic (clk_accel domain)
  
    always_ff @(posedge clk_accel or negedge rst_accel_n) begin
        if (!rst_accel_n) begin
            counter      <= '0;
            holding_reg  <= '0;
            fifo_wr_en   <= 1'b0;
            fifo_wr_data <= '0;
        end else begin
            fifo_wr_en <= 1'b0; // Default deasserted for single-cycle pulse control

            case (current_state)
                IDLE: begin
                    counter <= '0;
                    if (array_valid && !fifo_full) begin
                        holding_reg <= array_data; // Latch 64-bit output matrix from systolic array
                    end
                end

                PUSH: begin
                    if (!fifo_full) begin
                        // Slice out the current 4-bit nibble from the holding register sequentially
                        fifo_wr_data <= holding_reg[((TOTAL_ELEMENTS - 1 - counter) * DATA_WIDTH_M) +: DATA_WIDTH_M];
                        fifo_wr_en   => 1'b1; // Trigger async FIFO write

                        if (counter == TOTAL_ELEMENTS - 1) begin
                            counter <= '0;
                        end else begin
                            counter <= counter + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
