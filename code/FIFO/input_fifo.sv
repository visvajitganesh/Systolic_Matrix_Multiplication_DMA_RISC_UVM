`timescale 1ns / 1ps

module input_fifo #(
    parameter int DATA_WIDTH   = 4,        // Same as STREAM_WIDTH
    parameter int DATA_WIDTH_M = 4,        // Matrix size element width
    parameter int MATRIX_SIZE  = 4,
    parameter int DEPTH        = 32        // 4 * 32 = 128 bits
)(
    input logic clk_sys,     // System Clock Domain (DMA side)
    input logic rst_sys_n,   // System Reset
    input logic clk_accel,   // Accelerator Clock Domain
    input logic rst_accel_n, // Accelerator Reset

    // DMA / SYSTEM SIDE: AXI-Stream Protocol Signals (clk_sys)
    input  logic [DATA_WIDTH - 1:0] s_axis_tdata,  
    input  logic                    s_axis_tvalid, 
    output logic                    s_axis_tready, 
    input  logic                    s_axis_tlast, 

    // SYSTOLIC ARRAY SIDE : Handshaking Mechanism (clk_accel)
    input  logic                                                      systolic_ready,
    output logic [2 * MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH_M - 1:0] array_data,  
    output logic                                                      array_start 
);

    localparam int TOTAL_ELEMENTS = 2 * MATRIX_SIZE * MATRIX_SIZE;
    localparam int CNT_WIDTH      = $clog2(TOTAL_ELEMENTS);

    localparam IDLE = 1'b0, FILL = 1'b1;

    logic current_state, next_state;
    logic [CNT_WIDTH - 1:0] counter;
    
    logic                    fifo_full;
    logic                    fifo_empty;
    logic [DATA_WIDTH - 1:0] fifo_rd_data;
    logic                    fifo_rd_en;

    // Direct backpressure to DMA on system clock side (Fixed port name mapping)
    assign s_axis_tready = !fifo_full; // becomes low when the fifo is full

    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) u_async_fifo (
        .wr_clk   (clk_sys),
        .wr_rst_n (rst_sys_n),
        .wr_en    (s_axis_tvalid && s_axis_tready),
        .wr_data  (s_axis_tdata),          // Fixed typo: s_sxis_tdata -> s_axis_tdata
        .full     (fifo_full),

        .rd_clk   (clk_accel),
        .rd_rst_n (rst_accel_n),
        .rd_en    (fifo_rd_en),
        .rd_data  (fifo_rd_data),
        .empty    (fifo_empty)
    );

    assign fifo_rd_en  = (current_state == FILL) && !fifo_empty;

    // Deserializer State Register
    always_ff @(posedge clk_accel or negedge rst_accel_n) begin
        if (~rst_accel_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    // FSM Next State Combinational Logic
    always_comb begin
        case (current_state)
            IDLE    : begin
                if (!fifo_empty && systolic_ready)
                    next_state = FILL;
                else
                    next_state = IDLE; // Added missing semicolon
            end

            FILL    : begin
                if ((counter == TOTAL_ELEMENTS - 1) && fifo_rd_en)
                    next_state = IDLE;
                else
                    next_state = FILL;
            end

            default : next_state = IDLE;
        endcase
    end

    // Counter & Array Data Packing (Sequential)
    always_ff @(posedge clk_accel or negedge rst_accel_n) begin
        if (!rst_accel_n) begin
            counter     <= '0;
            array_data  <= '0;
            array_start <= 1'b0;
        end 
        else begin
            array_start <= 1'b0; // Default 0 (ensures single-cycle pulse)

            case (current_state)
                IDLE: begin
                    counter <= '0;
                end

                FILL: begin
                    if (fifo_rd_en) begin
                        array_data[((TOTAL_ELEMENTS - 1 - counter) * DATA_WIDTH_M) +: DATA_WIDTH_M] <= fifo_rd_data;
                        
                        if (counter == TOTAL_ELEMENTS - 1) begin
                            counter     <= '0;
                            array_start <= 1'b1; // 1-cycle active pulse when transitioning to READY
                        end 
                        else begin
                            counter <= counter + 1'b1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
