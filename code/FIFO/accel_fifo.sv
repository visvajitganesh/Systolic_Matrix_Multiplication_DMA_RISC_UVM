`timescale 1ns / 1ps

// -----------------------------------------------------------------------
// accel_buffer_top
//
// Combines input_buffer (DMA -> Array) and output_buffer (Array -> DMA)
// into a single module with flattened ports, so one testbench can
// exercise both buffering paths without needing SystemVerilog virtual
// interfaces on the testbench side.
//
// Internally instantiates:
//   input_buffer_if  + input_buffer   (uses async_fifo)
//   output_buffer_if + output_buffer  (uses async_fifo)
//
// This module does NOT include the dma or systolic_adapter/array
// themselves -- only the two buffer/FIFO paths between them.
//   - Drive in_t*        as if you were the DMA read master.
//   - Drive in_array_*   (ready) / observe (data,valid) as if you were
//     the systolic array input edge.
//   - Drive out_array_*  as if you were the systolic array output edge.
//   - Drive out_tready   / observe out_t* as if you were the DMA write
//     slave.
//
// clk_sys/rst_sys_n and clk_accel/rst_accel_n are shared between both
// buffers (both sit on the same DMA-side clock and the same
// accelerator-side clock).
// -----------------------------------------------------------------------

module accel_buffer_top #(
    parameter int IN_DATA_WIDTH    = 8,
    parameter int IN_NUM_CHANNELS  = 8,
    parameter int IN_DEPTH         = 16,   // power of 2

    parameter int OUT_DATA_WIDTH   = 32,
    parameter int OUT_NUM_CHANNELS = 8,
    parameter int OUT_DEPTH        = 16    // power of 2
)(
    input  logic clk_sys,
    input  logic rst_sys_n,
    input  logic clk_accel,
    input  logic rst_accel_n,

    // ================= INPUT BUFFER (DMA -> Array) =================
    // DMA side -- drive as if you are the read-DMA master
    input  logic [(IN_DATA_WIDTH*IN_NUM_CHANNELS)-1:0]    in_tdata,
    input  logic                                          in_tvalid,
    output logic                                          in_tready,
    input  logic                                          in_tlast,

    // Array side -- drive/observe as if you are the systolic array
    output logic [IN_NUM_CHANNELS-1:0][IN_DATA_WIDTH-1:0] in_array_data,
    output logic                                          in_array_valid,
    input  logic                                          in_array_ready,

    // ================= OUTPUT BUFFER (Array -> DMA) =================
    // Array side -- drive as if you are the systolic array
    input  logic [OUT_NUM_CHANNELS-1:0][OUT_DATA_WIDTH-1:0] out_array_data,
    input  logic                                            out_array_valid,
    output logic                                            out_array_ready,
    input  logic                                            out_array_last,

    // DMA side -- drive/observe as if you are the write-DMA slave
    output logic [(OUT_DATA_WIDTH*OUT_NUM_CHANNELS)-1:0]  out_tdata,
    output logic                                          out_tvalid,
    input  logic                                          out_tready,
    output logic                                          out_tlast
);

    // -----------------------------------------------------------------
    // Input buffer (DMA -> Array)
    // -----------------------------------------------------------------
    input_buffer_if #(
        .DATA_WIDTH   (IN_DATA_WIDTH),
        .NUM_CHANNELS (IN_NUM_CHANNELS)
    ) in_if (
        .clk_sys     (clk_sys),
        .rst_sys_n   (rst_sys_n),
        .clk_accel   (clk_accel),
        .rst_accel_n (rst_accel_n)
    );

    assign in_if.tdata       = in_tdata;
    assign in_if.tvalid      = in_tvalid;
    assign in_if.tlast       = in_tlast;
    assign in_tready         = in_if.tready;

    assign in_array_data     = in_if.array_data;
    assign in_array_valid    = in_if.array_valid;
    assign in_if.array_ready = in_array_ready;

    input_buffer #(
        .DATA_WIDTH   (IN_DATA_WIDTH),
        .NUM_CHANNELS (IN_NUM_CHANNELS),
        .DEPTH        (IN_DEPTH)
    ) u_input_buffer (
        .port (in_if.buf_ports)
    );

    // -----------------------------------------------------------------
    // Output buffer (Array -> DMA)
    // -----------------------------------------------------------------
    output_buffer_if #(
        .DATA_WIDTH   (OUT_DATA_WIDTH),
        .NUM_CHANNELS (OUT_NUM_CHANNELS)
    ) out_if (
        .clk_sys     (clk_sys),
        .rst_sys_n   (rst_sys_n),
        .clk_accel   (clk_accel),
        .rst_accel_n (rst_accel_n)
    );

    assign out_if.array_data  = out_array_data;
    assign out_if.array_valid = out_array_valid;
    assign out_if.array_last  = out_array_last;
    assign out_array_ready    = out_if.array_ready;

    assign out_tdata     = out_if.tdata;
    assign out_tvalid    = out_if.tvalid;
    assign out_tlast     = out_if.tlast;
    assign out_if.tready = out_tready;

    output_buffer #(
        .DATA_WIDTH   (OUT_DATA_WIDTH),
        .NUM_CHANNELS (OUT_NUM_CHANNELS),
        .DEPTH        (OUT_DEPTH)
    ) u_output_buffer (
        .port (out_if.buf_ports)
    ); //

endmodule