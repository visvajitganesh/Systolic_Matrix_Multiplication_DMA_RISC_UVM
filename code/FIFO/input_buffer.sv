`timescale 1ns / 1ps

// -----------------------------------------------------------------------
// input_buffer
//
// Implements input_buffer_if.buf_ports. Sits between the DMA (clk_sys,
// AXI-Stream tdata/tvalid/tready) and the systolic array input edge
// (clk_accel, parallel array_data/array_valid/array_ready).
//
// DATA_WIDTH / NUM_CHANNELS here must match the values used to
// instantiate the input_buffer_if interface this module is bound to.
//
// tlast is NOT forwarded -- input_buffer_if has no array-side "last"
// signal for it to land on, so it's only meaningful to the DMA master
// itself and isn't stored in the FIFO.
// -----------------------------------------------------------------------

module input_buffer #(
    parameter int DATA_WIDTH   = 8,
    parameter int NUM_CHANNELS = 8,
    parameter int DEPTH        = 16   // must be a power of 2
)(
    input_buffer_if.buf_ports port
);

    localparam int VEC_WIDTH = DATA_WIDTH * NUM_CHANNELS;

    logic fifo_full, fifo_empty;
    logic [VEC_WIDTH-1:0] rd_data_flat;

    assign port.tready = !fifo_full;

    async_fifo #(
        .DATA_WIDTH (VEC_WIDTH),
        .DEPTH      (DEPTH)
    ) u_async_fifo (
        .wr_clk   (port.clk_sys),
        .wr_rst_n (port.rst_sys_n),
        .wr_en    (port.tvalid),
        .wr_data  (port.tdata),
        .full     (fifo_full),

        .rd_clk   (port.clk_accel),
        .rd_rst_n (port.rst_accel_n),
        .rd_en    (port.array_ready),
        .rd_data  (rd_data_flat),
        .empty    (fifo_empty)
    );

    assign port.array_valid = !fifo_empty;

    // Unpack the flat stored vector back into the array's per-channel form
    generate
        genvar i;
        for (i = 0; i < NUM_CHANNELS; i++) begin : g_unpack
            assign port.array_data[i] = rd_data_flat[(i*DATA_WIDTH) +: DATA_WIDTH];
        end
    endgenerate

endmodule
