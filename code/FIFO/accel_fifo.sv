`timescale 1ns / 1ps

// accel_top
//
// System top: wires input_fifo -> systolic -> output_fifo together.
//

// Name mapping across the three sub-modules (differs slightly on each
// side of systolic.sv, so called out explicitly here):
//   input_fifo.array_data   -> systolic.input_data
//   input_fifo.array_start  -> systolic.start
//   systolic.output_data    -> output_fifo.array_data
//   systolic.done           -> output_fifo.array_done
//   systolic.busy           -> output_fifo.array_busy
//   output_fifo.systolic_ready -> input_fifo.systolic_ready  (closes the loop:
//     a new computation can't start until the previous result has fully
//     drained out to the DMA)
//
// systolic.sv itself runs on clk_accel/rst_accel_n, matching the
// accelerator-side clock of both FIFOs.

module accel_top #(
    parameter int MATRIX_SIZE     = 4,

    // Input path (DMA -> Array): stream width vs. matrix element width
    parameter int IN_DATA_WIDTH   = 4,  // nibble width on the DMA AXI-Stream side
    parameter int IN_DATA_WIDTH_M = 4,  // matrix A/B element width (= systolic.DATA_WIDTH)
    parameter int IN_DEPTH        = 32, // 2*MATRIX_SIZE*MATRIX_SIZE elements

    // Output path (Array -> DMA): stream width vs. matrix element width
    parameter int OUT_DATA_WIDTH   = 4, // nibble width on the DMA AXI-Stream side
    parameter int OUT_DATA_WIDTH_M = 4, // result element width(= systolic.PSUM_WIDTH
                                        // NOTE: kept at 4 for simplicity; MAC results can
                                        // overflow 4 bits 
                                        // fine as long as test matrix values stay small
    parameter int OUT_DEPTH        = 16 // MATRIX_SIZE*MATRIX_SIZE*(OUT_DATA_WIDTH_M/OUT_DATA_WIDTH) nibbles
)(
    input  logic clk_sys,      // System/DMA clock domain
    input  logic rst_sys_n,    // System/DMA active-low reset
    input  logic clk_accel,    // Accelerator/Array clock domain
    input  logic rst_accel_n,  // Accelerator/Array active-low reset

    // DMA -> input_fifo (clk_sys) 
    input  logic [IN_DATA_WIDTH - 1:0]  in_tdata,
    input  logic                        in_tvalid,
    output logic                        in_tready,
    input  logic                        in_tlast,

    // output_fifo -> DMA (clk_sys) 
    output logic [OUT_DATA_WIDTH - 1:0] out_tdata,
    output logic                        out_tvalid,
    input  logic                        out_tready,
    output logic                        out_tlast
);

    
    // Internal wiring: input_fifo <-> systolic <-> output_fifo
    logic [2 * MATRIX_SIZE * MATRIX_SIZE * IN_DATA_WIDTH_M - 1:0] array_in_data;
    logic array_start;
    logic systolic_ready_w;

    logic [MATRIX_SIZE * MATRIX_SIZE * OUT_DATA_WIDTH_M - 1:0] array_out_data;
    logic sys_done;
    logic sys_busy;

    // Input FIFO: DMA nibble stream -> full input matrix pair
    input_fifo #(
        .DATA_WIDTH   (IN_DATA_WIDTH),
        .DATA_WIDTH_M (IN_DATA_WIDTH_M),
        .MATRIX_SIZE  (MATRIX_SIZE),
        .DEPTH        (IN_DEPTH)
    ) u_input_fifo (
        .clk_sys        (clk_sys),
        .rst_sys_n      (rst_sys_n),
        .clk_accel      (clk_accel),
        .rst_accel_n    (rst_accel_n),

        // FIXED: Matched port names to input_fifo.sv definitions
        .s_axis_tdata   (in_tdata),
        .s_axis_tvalid  (in_tvalid),
        .s_axis_tready  (in_tready),
        .s_axis_tlast   (in_tlast),

        .systolic_ready (systolic_ready_w),
        .array_data     (array_in_data),
        .array_start    (array_start)
    );
    
    // Systolic compute core

    systolic #(
        .MATRIX_SIZE (MATRIX_SIZE),
        .DATA_WIDTH  (IN_DATA_WIDTH_M),
        .PSUM_WIDTH  (OUT_DATA_WIDTH_M)
    ) u_systolic (
        .clk         (clk_accel),
        .rst_n       (rst_accel_n),

        .start       (array_start),
        .input_data  (array_in_data),

        .output_data (array_out_data),
        .done        (sys_done),
        .busy        (sys_busy)
    );

    
    // Output FIFO: full result matrix -> DMA nibble stream

    output_fifo #(
        .DATA_WIDTH   (OUT_DATA_WIDTH),
        .DATA_WIDTH_M (OUT_DATA_WIDTH_M),
        .MATRIX_SIZE  (MATRIX_SIZE),
        .DEPTH        (OUT_DEPTH)
    ) u_output_fifo (
        .clk_sys        (clk_sys),
        .rst_sys_n      (rst_sys_n),
        .clk_accel      (clk_accel),
        .rst_accel_n    (rst_accel_n),

        .array_data     (array_out_data),
        .array_done     (sys_done),
        .array_busy     (sys_busy),
        .systolic_ready (systolic_ready_w),

        .tdata          (out_tdata),
        .tvalid         (out_tvalid),
        .tready         (out_tready),
        .tlast          (out_tlast)
    );

endmodule
