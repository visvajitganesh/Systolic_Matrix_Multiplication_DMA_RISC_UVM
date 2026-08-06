module output_fifo #(
    parameter int DATA_WIDTH   = 4,  // Same as STREAM_WIDTH (to DMA)
    parameter int DATA_WIDTH_M = 4,  // Matrix element width (= systolic PSUM_WIDTH)
    parameter int MATRIX_SIZE  = 4,
    parameter int DEPTH        = 16  // 4 * 16 = 64 bits (one full result matrix)
)(
    input  logic clk_sys,      // System Clock Domain (DMA side)
    input  logic rst_sys_n,    // System Reset

    input  logic clk_accel,    // Accelerator Clock Domain
    input  logic rst_accel_n,  // Accelerator Reset

    // SYSTOLIC ARRAY SIDE: Handshaking Mechanism (clk_accel)
    input  logic [MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH_M - 1:0] array_data, // Result matrix from systolic.output_data, Big Endian
    input  logic array_done,      // 1-cycle pulse from systolic.done -- result is valid this cycle
    input  logic array_busy,      // systolic.busy -- held high while a computation is in flight
    output logic systolic_ready,  // High when this buffer has fully drained and the array may safely start a new computation

    // DMA  SYSTEM SIDE: AXI-Stream Protocol Signals (clk_sys)
    output logic [DATA_WIDTH - 1:0] tdata,
    output logic                    tvalid,
    input  logic                    tready,
    output logic                    tlast
);

    localparam int TOTAL_ELEMENTS = MATRIX_SIZE * MATRIX_SIZE;
    localparam int CNT_WIDTH      = $clog2(TOTAL_ELEMENTS);

    localparam IDLE = 1'b0, DRAIN = 1'b1;

    logic current_state, next_state;
    logic [CNT_WIDTH - 1:0] counter;      // write-side (clk_accel) element index
    logic [CNT_WIDTH - 1:0] rd_elem_cnt;  // read-side  (clk_sys)   element index, for tlast

    logic [MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH_M - 1:0] result_reg;

    logic fifo_full;
    logic fifo_empty;
    logic [DATA_WIDTH - 1:0] fifo_wr_data;
    logic fifo_wr_en;
    logic [DATA_WIDTH - 1:0] fifo_rd_data;
    logic fifo_rd_en;

    // Only ready for a new result once fully drained AND the array itself
    // isn't mid-computation -- mirrors the busy/done protocol systolic.sv
    // already uses internally (start is ignored while busy is high), just
    // surfaced here so an upstream input_fifo.systolic_ready can gate on it.
    assign systolic_ready = (current_state == IDLE) && !array_busy;

    // Select the current element out of the latched result matrix,
    // big-endian, matching systolic.sv's output packing convention.
    assign fifo_wr_data = result_reg[((TOTAL_ELEMENTS - 1 - counter) * DATA_WIDTH_M) +: DATA_WIDTH_M];
    assign fifo_wr_en   = (current_state == DRAIN) && !fifo_full;

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

    // Serializer FSM (clk_accel side) -- reverse of input_fifo's deserializer

    always_ff @(posedge clk_accel or negedge rst_accel_n) begin
        if (!rst_accel_n)
            current_state <= IDLE;
        else
            current_state <= next_state;
    end

    always_comb begin
        case (current_state)
            IDLE: begin
                if (array_done)
                    next_state = DRAIN;
                else
                    next_state = IDLE;
            end

            DRAIN: begin
                if ((counter == TOTAL_ELEMENTS - 1) && fifo_wr_en)
                    next_state = IDLE;
                else
                    next_state = DRAIN;
            end

            default: next_state = IDLE;
        endcase
    end

    // Counter & Result Latch (Sequential)
    always_ff @(posedge clk_accel or negedge rst_accel_n) begin
        if (!rst_accel_n) begin
            counter    <= '0;
            result_reg <= '0;
        end else begin
            case (current_state)
                IDLE: begin
                    counter <= '0;
                    if (array_done) begin
                        result_reg <= array_data; // Latch the full result matrix on the done pulse
                    end
                end

                DRAIN: begin
                    if (fifo_wr_en) begin
                        if (counter == TOTAL_ELEMENTS - 1) begin
                            counter <= '0;
                        end else begin
                            counter <= counter + 1'b1;
                        end
                    end
                end

                default: counter <= '0;
            endcase
        end
    end

    // DMA SYSTEM SIDE: plain AXI-Stream passthrough (clk_sys)

    assign tvalid     = !fifo_empty;
    assign tdata       = fifo_rd_data;
    assign fifo_rd_en = tvalid && tready;

    // tlast: pulse on the handshake that reads out the final nibble of
    // each drained result matrix.
    always_ff @(posedge clk_sys or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            rd_elem_cnt <= '0;
        end else if (fifo_rd_en) begin
            if (rd_elem_cnt == TOTAL_ELEMENTS - 1)
                rd_elem_cnt <= '0;
            else
                rd_elem_cnt <= rd_elem_cnt + 1'b1;
        end
    end

    assign tlast = fifo_rd_en && (rd_elem_cnt == TOTAL_ELEMENTS - 1);

endmodule
