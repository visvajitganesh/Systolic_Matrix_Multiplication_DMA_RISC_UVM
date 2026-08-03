// output_buffer_if.sv
// OFFICIAL HARDWARE CONTRACT: Connects Systolic Array Outputs (Parallel Vectors) to Write DMA (AXI-Stream)

interface output_buffer_if #(
    parameter int DATA_WIDTH   = 32, // Computational accumulator values are wider (e.g., 32-bit INT/FP)
    parameter int NUM_CHANNELS = 8   // Matrix dimension matching the array exit edge size (N)
)(
    input logic clk_sys,   // Interconnect / DMA System Clock Domain
    input logic rst_sys_n, // Active-low synchronous system reset
    input logic clk_accel, // Dedicated High-Speed Accelerator Clock Domain
    input logic rst_accel_n// Active-low synchronous accelerator fabric reset
);

    // =========================================================================
    // SYSTOLIC ARRAY SIDE: Synchronous Vector Ports (Unpacked Element Array)
    // =========================================================================
    logic [NUM_CHANNELS-1:0][DATA_WIDTH-1:0] array_data;  // Accumulator matrix outputs pushing from PEs
    logic                                    array_valid; // Array engine pulses to signal valid output vectors
    logic                                    array_ready; // Output buffer states it has room to capture elements
    logic                                    array_last;  // Array signals the final resulting matrix block boundary

    // =========================================================================
    // DMA / SYSTEM SIDE: AXI-Stream Protocol Signals (Packed Data Bus)
    // =========================================================================
    logic [(DATA_WIDTH*NUM_CHANNELS)-1:0] tdata;  // Packed parallel computation results driven to DMA
    logic                                 tvalid; // Buffer tells DMA: "Processed matrix data available"
    logic                                 tready; // DMA states AXI Master Write channel is ready to absorb burst
    logic                                 tlast;  // Propagated packet completion token for the DMA engine

    // =========================================================================
    // INTERFACE MODPORTS (Directional Enforcements)
    // =========================================================================

    // Assign this modport to the Systolic Array Output Edge Execution Controller
    modport array_ports (
        input  clk_accel, rst_accel_n,
        input  array_ready,
        output array_data, array_valid, array_last
    );

    // Assign this modport to the DMA Write Slave / Channel interface hierarchy block
    modport dma_ports (
        input  clk_sys, rst_sys_n,
        input  tdata, tvalid, tlast,
        output tready
    );

    // Assign this modport to the buffer/FIFO module that actually implements
    // this contract, sitting between the two endpoints above.
    modport buf_ports (
        input  clk_sys, rst_sys_n, clk_accel, rst_accel_n,
        input  array_data, array_valid, array_last,
        output array_ready,
        output tdata, tvalid, tlast,
        input  tready
    );

endinterface
