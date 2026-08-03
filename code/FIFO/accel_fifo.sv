`timescale 1ns / 1ps

// -----------------------------------------------------------------------
// accel_buffer_top (Updated for 4-bit Nibble Stream Architecture)
//
// Combines input_buffer (DMA -> Array) and output_buffer (Array -> DMA)
// into a single module with flattened ports, configured for a 4-bit 
// streaming interface matching the DMA and systolic adapter.
// -----------------------------------------------------------------------

module accel_buffer_top #(
    parameter int IN_DATA_WIDTH    = 4,    // 4-bit nibble matching DMA stream width
    parameter int IN_NUM_CHANNELS  = 1,    // Single channel stream
    parameter int IN_DEPTH         = 32,   // power of 2 (32 entries)

    parameter int OUT_DATA_WIDTH   = 4,    // 4-bit nibble matching adapter stream width
    parameter int OUT_NUM_CHANNELS = 1,    // Single channel stream
    parameter int OUT_DEPTH        = 32    // power of 2 (32 entries)
)(
    input  logic clk_sys,
    input  logic rst_sys_n,
    input  logic clk_accel,
    input  logic rst_accel_n,

    // ================= INPUT BUFFER (DMA -> Array) =================
    input  logic [(IN_DATA_WIDTH*IN_NUM_CHANNELS)-1:0]    in_tdata,
    input  logic                                          in_tvalid,
    output logic                                          in_tready,
    input  logic                                          in_tlast,

    output logic [IN_NUM_CHANNELS-1:0][IN_DATA_WIDTH-1:0] in_array_data,
    output logic                                          in_array_valid,
    input  logic                                          in_array_ready,

    // ================= OUTPUT BUFFER (Array -> DMA) =================
    input  logic [OUT_NUM_CHANNELS-1:0][OUT_DATA_WIDTH-1:0] out_array_data,
    input  logic                                            out_array_valid,
    output logic                                            out_array_ready,
    input  logic                                            out_array_last,

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
    );

endmodule
