`timescale 1ns / 1ps

// -----------------------------------------------------------------------
// output_buffer
//
// Implements output_buffer_if.buf_ports. Sits between the systolic array
// output edge (clk_accel, parallel array_data/array_valid/array_ready/
// array_last) and the DMA write channel (clk_sys, AXI-Stream
// tdata/tvalid/tready/tlast).
//
// DATA_WIDTH / NUM_CHANNELS here must match the values used to
// instantiate the output_buffer_if interface this module is bound to.
//
// array_last IS forwarded through to tlast -- both sides have a "last"
// signal here, so it's packed alongside the data vector to survive the
// clock-domain crossing in lock-step with the word it marks.
// -----------------------------------------------------------------------

module output_buffer #(
    parameter int DATA_WIDTH   = 32,
    parameter int NUM_CHANNELS = 8,
    parameter int DEPTH        = 16   // must be a power of 2
)(
    output_buffer_if.buf_ports port
);

    localparam int VEC_WIDTH = DATA_WIDTH * NUM_CHANNELS;

    logic fifo_full, fifo_empty;
    logic [VEC_WIDTH-1:0] array_data_flat;
    logic [VEC_WIDTH:0]   wr_data, rd_data; // MSB carries array_last / tlast

    // Pack the unpacked per-channel array into one flat bus for storage
    generate
        genvar i;
        for (i = 0; i < NUM_CHANNELS; i++) begin : g_pack
            assign array_data_flat[(i*DATA_WIDTH) +: DATA_WIDTH] = port.array_data[i];
        end
    endgenerate

    assign wr_data = {port.array_last, array_data_flat};
    assign port.array_ready = !fifo_full;

    async_fifo #(
        .DATA_WIDTH (VEC_WIDTH + 1),
        .DEPTH      (DEPTH)
    ) u_async_fifo (
        .wr_clk   (port.clk_accel),
        .wr_rst_n (port.rst_accel_n),
        .wr_en    (port.array_valid),
        .wr_data  (wr_data),
        .full     (fifo_full),

        .rd_clk   (port.clk_sys),
        .rd_rst_n (port.rst_sys_n),
        .rd_en    (port.tready),
        .rd_data  (rd_data),
        .empty    (fifo_empty)
    );

    assign port.tvalid = !fifo_empty;
    assign port.tlast  = rd_data[VEC_WIDTH];
    assign port.tdata  = rd_data[VEC_WIDTH-1:0];

endmodule
