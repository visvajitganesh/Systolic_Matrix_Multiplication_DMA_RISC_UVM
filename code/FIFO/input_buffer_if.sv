// input_buffer_if.sv
// OFFICIAL HARDWARE CONTRACT: Connects Read DMA (AXI-Stream) to Systolic Array Inputs (Parallel Vectors)

interface input_buffer_if #(
    parameter int DATA_WIDTH   = 8,  // Bit-width per data element (e.g., 8-bit for INT8 weights/features)
    parameter int NUM_CHANNELS = 8   // Matrix dimension matching the array edge size (N)
)(
    input logic clk_sys,   // Interconnect / DMA System Clock Domain
    input logic rst_sys_n, // Active-low synchronous system reset
    input logic clk_accel, // Dedicated High-Speed Accelerator Clock Domain
    input logic rst_accel_n// Active-low synchronous accelerator fabric reset
);

    // =========================================================================
    // DMA / SYSTEM SIDE: AXI-Stream Protocol Signals (Packed Data Bus)
    // =========================================================================
    logic [(DATA_WIDTH*NUM_CHANNELS)-1:0] tdata;  // Packed parallel vector stream from DMA
    logic                                 tvalid; // DMA states data is valid and stable
    logic                                 tready; // Input buffer states it has room to accept data
    logic                                 tlast;  // Marks the final vector of a matrix layer block

    // =========================================================================
    // SYSTOLIC ARRAY SIDE: Synchronous Vector Ports (Unpacked Element Array)
    // =========================================================================
    logic [NUM_CHANNELS-1:0][DATA_WIDTH-1:0] array_data; // Parallel vectors directly feeding PE edges
    logic                                    array_valid;// Buffer layers notify array: "Valid inputs ready"
    logic                                    array_ready;// Control FSM states: "Array fabric ready to shift/step"

    // =========================================================================
    // INTERFACE MODPORTS (Directional Enforcements)
    // =========================================================================

    // Assign this modport to the DMA Read Master interface hierarchy block
    modport dma_ports (
        input  clk_sys, rst_sys_n,
        input  tready,
        output tdata, tvalid, tlast
    );

    // Assign this modport to the Systolic Array Input Edge Execution Controller
    modport array_ports (
        input  clk_accel, rst_accel_n,
        input  array_data, array_valid,
        output array_ready
    );

    // Assign this modport to the buffer/FIFO module that actually implements
    // this contract, sitting between the two endpoints above. It drives
    // everything the endpoints read as input, and reads everything they drive.
    modport buf_ports (
        input  clk_sys, rst_sys_n, clk_accel, rst_accel_n,
        input  tdata, tvalid, tlast,
        output tready,
        output array_data, array_valid,
        input  array_ready
    );

endinterface
