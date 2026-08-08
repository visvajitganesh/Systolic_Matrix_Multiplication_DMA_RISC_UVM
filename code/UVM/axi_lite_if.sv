`timescale 1ns / 1ps
interface axi_lite_if #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32
)(
    input logic clk,
    input logic rst_n
);
    localparam int STRB_WIDTH = AXI_DATA_WIDTH / 8;

    // Write Address Channel
    logic [AXI_ADDR_WIDTH-1:0] awaddr;
    logic                      awvalid;
    logic                      awready;

    // Write Data Channel
    logic [AXI_DATA_WIDTH-1:0] wdata;
    logic [STRB_WIDTH-1:0]     wstrb;
    logic                      wvalid;
    logic                      wready;

    // Write Response Channel
    logic [1:0]                bresp;
    logic                      bvalid;
    logic                      bready;

    // Read Address Channel
    logic [AXI_ADDR_WIDTH-1:0] araddr;
    logic                      arvalid;
    logic                      arready;

    // Read Data Channel
    logic [AXI_DATA_WIDTH-1:0] rdata;
    logic [1:0]                rresp;
    logic                      rvalid;
    logic                      rready;

    // Clocking block for the Driver (Master perspective)
    clocking drv_cb @(posedge clk);
        default input #1step output #1;
        output awaddr, awvalid;
        input  awready;
        
        output wdata, wstrb, wvalid;
        input  wready;
        
        input  bresp, bvalid;
        output bready;
        
        output araddr, arvalid;
        input  arready;
        
        input  rdata, rresp, rvalid;
        output rready;
    endclocking

    // Clocking block for the Monitor (Passive observation)
    clocking mon_cb @(posedge clk);
        default input #1step output #1;
        input awaddr, awvalid, awready;
        input wdata, wstrb, wvalid, wready;
        input bresp, bvalid, bready;
        input araddr, arvalid, arready;
        input rdata, rresp, rvalid, rready;
    endclocking

endinterface