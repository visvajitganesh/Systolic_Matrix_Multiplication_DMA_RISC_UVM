`timescale 1ns / 1ps

// -----------------------------------------------------------------------
// accel_buffer_top (Updated for 4-bit Nibble Stream Architecture)
//
// Combines input_buffer (DMA -> Array) and output_buffer (Array -> DMA)
// into a single module with flattened ports, configured for a 4-bit 
// streaming interface matching the DMA and systolic adapter.[cite: 28]
// -----------------------------------------------------------------------

module accel_buffer_top #(
    // Input path parameters configured for a 4-bit nibble stream (1 channel)
    parameter int IN_DATA_WIDTH    = 4,    // 4-bit nibble matching DMA stream width
    parameter int IN_NUM_CHANNELS  = 1,    // Single channel stream
    parameter int IN_DEPTH         = 32,   // FIFO depth: power of 2 (32 entries)

    // Output path parameters configured for a 4-bit nibble stream (1 channel)
    parameter int OUT_DATA_WIDTH   = 4,    // 4-bit nibble matching adapter stream width
    parameter int OUT_NUM_CHANNELS = 1,    // Single channel stream
    parameter int OUT_DEPTH        = 32    // FIFO depth: power of 2 (32 entries)
)(
    // Dual-clock domain control signals
    input  logic clk_sys,      // System/DMA clock domain
    input  logic rst_sys_n,    // System/DMA active-low reset
    input  logic clk_accel,    // Accelerator/Array clock domain
    input  logic rst_accel_n,  // Accelerator/Array active-low reset

    // ================= INPUT BUFFER (DMA -> Array) =================
    // AXI-Stream Read Channel (Driven by DMA Master)[cite: 28]
    input  logic [(IN_DATA_WIDTH*IN_NUM_CHANNELS)-1:0]    in_tdata,   // Data payload bus
    input  logic                                          in_tvalid,  // Data valid handshake
    output logic                                          in_tready,  // Buffer ready to accept data
    input  logic                                          in_tlast,   // Packet boundary indicator

    // Parallel Vector Output Channel (Driven to Systolic Array/Adapter)[cite: 28]
    output logic [IN_NUM_CHANNELS-1:0][IN_DATA_WIDTH-1:0] in_array_data,  // Unpacked data elements
    output logic                                          in_array_valid, // Output data valid flag
    input  logic                                          in_array_ready, // Array ready to consume data

    // ================= OUTPUT BUFFER (Array -> DMA) =================
    // Parallel Vector Input Channel (Driven by Systolic Array/Adapter)[cite: 28]
    input  logic [OUT_NUM_CHANNELS-1:0][OUT_DATA_WIDTH-1:0] out_array_data,  // Computed data elements
    input  logic                                            out_array_valid, // Array data valid flag
    output logic                                            out_array_ready, // Buffer ready for output
    input  logic                                            out_array_last,  // Matrix block boundary indicator

    // AXI-Stream Write Channel (Driven to DMA Slave)[cite: 28]
    output logic [(OUT_DATA_WIDTH*OUT_NUM_CHANNELS)-1:0]  out_tdata,   // Packed stream output data
    output logic                                          out_tvalid,  // Stream valid handshake
    input  logic                                          out_tready,  // DMA write channel ready
    output logic                                          out_tlast    // Propagated packet completion token
);

    // -----------------------------------------------------------------
    // Input buffer (DMA -> Array Path)
    // -----------------------------------------------------------------
    
    // Instantiate the input buffer interface contract (handles CDC and port mapping)
    input_buffer_if #(
        .DATA_WIDTH   (IN_DATA_WIDTH),
        .NUM_CHANNELS (IN_NUM_CHANNELS)
    ) in_if (
        .clk_sys     (clk_sys),
        .rst_sys_n   (rst_sys_n),
        .clk_accel   (clk_accel),
        .rst_accel_n (rst_accel_n)
    );

    // Wire top-level input ports to the interface system (DMA) side
    assign in_if.tdata       = in_tdata;
    assign in_if.tvalid      = in_tvalid;
    assign in_if.tlast       = in_tlast;
    assign in_tready         = in_if.tready;

    // Wire interface array-side signals to top-level output ports
    assign in_array_data     = in_if.array_data;
    assign in_array_valid    = in_if.array_valid;
    assign in_if.array_ready = in_array_ready;

    // Instantiate the core input_buffer module using the interface's buffer ports
    input_buffer #(
        .DATA_WIDTH   (IN_DATA_WIDTH),
        .NUM_CHANNELS (IN_NUM_CHANNELS),
        .DEPTH        (IN_DEPTH)
    ) u_input_buffer (
        .port (in_if.buf_ports)
    );

    // -----------------------------------------------------------------
    // Output buffer (Array -> DMA Path)
    // -----------------------------------------------------------------
    
    // Instantiate the output buffer interface contract for the return path
    output_buffer_if #(
        .DATA_WIDTH   (OUT_DATA_WIDTH),
        .NUM_CHANNELS (OUT_NUM_CHANNELS)
    ) out_if (
        .clk_sys     (clk_sys),
        .rst_sys_n   (rst_sys_n),
        .clk_accel   (clk_accel),
        .rst_accel_n (rst_accel_n)
    );

    // Wire top-level array input ports to the interface array side
    assign out_if.array_data  = out_array_data;
    assign out_if.array_valid = out_array_valid;
    assign out_if.array_last  = out_array_last;
    assign out_array_ready    = out_if.array_ready;

    // Wire interface system side signals to top-level DMA write ports
    assign out_tdata     = out_if.tdata;
    assign out_tvalid    = out_if.tvalid;
    assign out_tlast     = out_if.tlast;
    assign out_if.tready = out_tready;

    // Instantiate the core output_buffer module using the interface's buffer ports
    output_buffer #(
        .DATA_WIDTH   (OUT_DATA_WIDTH),
        .NUM_CHANNELS (OUT_NUM_CHANNELS),
        .DEPTH        (OUT_DEPTH)
    ) u_output_buffer (
        .port (out_if.buf_ports)
    );

endmodule
