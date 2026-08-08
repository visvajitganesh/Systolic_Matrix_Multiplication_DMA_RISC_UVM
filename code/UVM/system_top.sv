`timescale 1ns / 1ps


// system_top
//
// Full data path: BRAM <-AXI4-> DMA <-4b stream-> input_fifo -> systolic
//                 -> output_fifo <-4b stream-> DMA <-AXI4-> BRAM
//
// Wraps dma_bram (dma.sv + bram_axi_top, both taken from dma_bram.sv --
// do NOT also compile the standalone dma.sv / bram_axi_top.sv files
// alongside this, their module names collide with the copies defined
// inside dma_bram.sv) together with accel_top (input_fifo + systolic +
// output_fifo, from accel_fifo.sv).
//
// Two independent clock domains:
//   clk_sys/rst_sys_n     - DMA, BRAM, and the clk_sys side of both FIFOs
//   clk_accel/rst_accel_n - the systolic array core and the clk_accel
//                           side of both FIFOs


module system_top #(
    parameter int AXI_ADDR_WIDTH  = 32,
    parameter int AXI_DATA_WIDTH  = 32,
    parameter int STREAM_WIDTH    = 4,
    parameter int BRAM_DEPTH      = 48,

    parameter int MATRIX_SIZE      = 4,
    parameter int IN_DATA_WIDTH_M  = 4,   // systolic input element width (A/B)
    parameter int IN_DEPTH         = 32,  // input_fifo async_fifo depth
    parameter int OUT_DATA_WIDTH_M = 4,   // systolic output element width (C / PSUM_WIDTH)
    parameter int OUT_DEPTH        = 16   // output_fifo async_fifo depth
)(
    input logic clk_sys,
    input logic rst_sys_n,
    input logic clk_accel,
    input logic rst_accel_n,

    // 1. Host AXI4-Lite Slave Interface -> DMA Configuration Registers

    input  logic [AXI_ADDR_WIDTH-1:0] s_dma_axi_lite_awaddr,
    input  logic                      s_dma_axi_lite_awvalid,
    output logic                      s_dma_axi_lite_awready,

    input  logic [AXI_DATA_WIDTH-1:0] s_dma_axi_lite_wdata,
    input  logic                      s_dma_axi_lite_wvalid,
    output logic                      s_dma_axi_lite_wready,

    output logic [1:0]                s_dma_axi_lite_bresp,
    output logic                      s_dma_axi_lite_bvalid,
    input  logic                      s_dma_axi_lite_bready,

    input  logic [AXI_ADDR_WIDTH-1:0] s_dma_axi_lite_araddr,
    input  logic                      s_dma_axi_lite_arvalid,
    output logic                      s_dma_axi_lite_arready,

    output logic [AXI_DATA_WIDTH-1:0] s_dma_axi_lite_rdata,
    output logic [1:0]                s_dma_axi_lite_rresp,
    output logic                      s_dma_axi_lite_rvalid,
    input  logic                      s_dma_axi_lite_rready,


    // 2. RISC CPU AXI4-Lite Slave Interface -> Direct Access to Shared BRAM

    input  logic [AXI_ADDR_WIDTH-1:0]     s_bram_axi_lite_awaddr,
    input  logic                          s_bram_axi_lite_awvalid,
    output logic                          s_bram_axi_lite_awready,

    input  logic [AXI_DATA_WIDTH-1:0]     s_bram_axi_lite_wdata,
    input  logic [(AXI_DATA_WIDTH/8)-1:0] s_bram_axi_lite_wstrb,
    input  logic                          s_bram_axi_lite_wvalid,
    output logic                          s_bram_axi_lite_wready,

    output logic [1:0]                    s_bram_axi_lite_bresp,
    output logic                          s_bram_axi_lite_bvalid,
    input  logic                          s_bram_axi_lite_bready,

    input  logic [AXI_ADDR_WIDTH-1:0]     s_bram_axi_lite_araddr,
    input  logic                          s_bram_axi_lite_arvalid,
    output logic                          s_bram_axi_lite_arready,

    output logic [AXI_DATA_WIDTH-1:0]     s_bram_axi_lite_rdata,
    output logic [1:0]                    s_bram_axi_lite_rresp,
    output logic                          s_bram_axi_lite_rvalid,
    input  logic                          s_bram_axi_lite_rready
);


    // Internal stream wires: DMA <-> accel_top

    logic [STREAM_WIDTH-1:0] mm2s_tdata;
    logic                    mm2s_tvalid;
    logic                    mm2s_tready;

    logic [STREAM_WIDTH-1:0] s2mm_tdata;
    logic                    s2mm_tvalid;
    logic                    s2mm_tready;


    // DMA + shared BRAM (single clk_sys/rst_sys_n domain)
    
    dma_bram #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .STREAM_WIDTH   (STREAM_WIDTH),
        .BRAM_DEPTH     (BRAM_DEPTH)
    ) u_dma_bram (
        .clk   (clk_sys),
        .rst_n (rst_sys_n),

        .s_dma_axi_lite_awaddr  (s_dma_axi_lite_awaddr),
        .s_dma_axi_lite_awvalid (s_dma_axi_lite_awvalid),
        .s_dma_axi_lite_awready (s_dma_axi_lite_awready),
        .s_dma_axi_lite_wdata   (s_dma_axi_lite_wdata),
        .s_dma_axi_lite_wvalid  (s_dma_axi_lite_wvalid),
        .s_dma_axi_lite_wready  (s_dma_axi_lite_wready),
        .s_dma_axi_lite_bresp   (s_dma_axi_lite_bresp),
        .s_dma_axi_lite_bvalid  (s_dma_axi_lite_bvalid),
        .s_dma_axi_lite_bready  (s_dma_axi_lite_bready),
        .s_dma_axi_lite_araddr  (s_dma_axi_lite_araddr),
        .s_dma_axi_lite_arvalid (s_dma_axi_lite_arvalid),
        .s_dma_axi_lite_arready (s_dma_axi_lite_arready),
        .s_dma_axi_lite_rdata   (s_dma_axi_lite_rdata),
        .s_dma_axi_lite_rresp   (s_dma_axi_lite_rresp),
        .s_dma_axi_lite_rvalid  (s_dma_axi_lite_rvalid),
        .s_dma_axi_lite_rready  (s_dma_axi_lite_rready),

        .s_bram_axi_lite_awaddr  (s_bram_axi_lite_awaddr),
        .s_bram_axi_lite_awvalid (s_bram_axi_lite_awvalid),
        .s_bram_axi_lite_awready (s_bram_axi_lite_awready),
        .s_bram_axi_lite_wdata   (s_bram_axi_lite_wdata),
        .s_bram_axi_lite_wstrb   (s_bram_axi_lite_wstrb),
        .s_bram_axi_lite_wvalid  (s_bram_axi_lite_wvalid),
        .s_bram_axi_lite_wready  (s_bram_axi_lite_wready),
        .s_bram_axi_lite_bresp   (s_bram_axi_lite_bresp),
        .s_bram_axi_lite_bvalid  (s_bram_axi_lite_bvalid),
        .s_bram_axi_lite_bready  (s_bram_axi_lite_bready),
        .s_bram_axi_lite_araddr  (s_bram_axi_lite_araddr),
        .s_bram_axi_lite_arvalid (s_bram_axi_lite_arvalid),
        .s_bram_axi_lite_arready (s_bram_axi_lite_arready),
        .s_bram_axi_lite_rdata   (s_bram_axi_lite_rdata),
        .s_bram_axi_lite_rresp   (s_bram_axi_lite_rresp),
        .s_bram_axi_lite_rvalid  (s_bram_axi_lite_rvalid),
        .s_bram_axi_lite_rready  (s_bram_axi_lite_rready),

        .m_axis_mm2s_tdata  (mm2s_tdata),
        .m_axis_mm2s_tvalid (mm2s_tvalid),
        .m_axis_mm2s_tready (mm2s_tready),
        .s_axis_s2mm_tdata  (s2mm_tdata),
        .s_axis_s2mm_tvalid (s2mm_tvalid),
        .s_axis_s2mm_tready (s2mm_tready)
    );


    // Systolic array + CDC FIFOs (clk_sys <-> clk_accel boundary)

    accel_top #(
        .MATRIX_SIZE     (MATRIX_SIZE),
        .IN_DATA_WIDTH   (STREAM_WIDTH),
        .IN_DATA_WIDTH_M (IN_DATA_WIDTH_M),
        .IN_DEPTH        (IN_DEPTH),
        .OUT_DATA_WIDTH   (STREAM_WIDTH),
        .OUT_DATA_WIDTH_M (OUT_DATA_WIDTH_M),
        .OUT_DEPTH        (OUT_DEPTH)
    ) u_accel_top (
        .clk_sys     (clk_sys),
        .rst_sys_n   (rst_sys_n),
        .clk_accel   (clk_accel),
        .rst_accel_n (rst_accel_n),

        .in_tdata  (mm2s_tdata),
        .in_tvalid (mm2s_tvalid),
        .in_tready (mm2s_tready),
        .in_tlast  (1'b0),           // dma.sv's MM2S stream has no tlast; unused by input_fifo anyway

        .out_tdata  (s2mm_tdata),
        .out_tvalid (s2mm_tvalid),
        .out_tready (s2mm_tready),
        .out_tlast  ()               // dma.sv's S2MM stream has no tlast input; leave dangling
    );

endmodule
