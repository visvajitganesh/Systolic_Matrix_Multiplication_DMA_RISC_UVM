`timescale 1ns / 1ps

import uvm_pkg::*;
import tb_pkg::*;
`include "uvm_macros.svh"

// Include system test in module scope
`include "system_test.sv"

module tb_top;

    // =========================================================================
    // 1. CLOCK AND RESET GENERATION
    // =========================================================================
    logic clk_sys;
    logic rst_sys_n;
    logic clk_accel;
    logic rst_accel_n;

    // System Clock: 100 MHz (10ns period)
    initial begin
        clk_sys = 0;
        forever #5 clk_sys = ~clk_sys;
    end

    // Accelerator Clock: 100 MHz (10ns period)
    initial begin
        clk_accel = 0;
        forever #5 clk_accel = ~clk_accel;
    end

    // Reset Generator (Held LOW for 100ns)
    initial begin
        rst_sys_n   = 0;
        rst_accel_n = 0;
        #100;
        rst_sys_n   = 1;
        rst_accel_n = 1;
    end

    // =========================================================================
    // 2. INTERFACE INSTANTIATIONS
    // =========================================================================
    // Both AXI4-Lite slave interfaces operate in the clk_sys domain
    axi_lite_if dma_if  (.clk(clk_sys), .rst_n(rst_sys_n));
    axi_lite_if bram_if (.clk(clk_sys), .rst_n(rst_sys_n));

    // =========================================================================
    // 3. DUT INSTANTIATION
    // =========================================================================
    system_top #(
        .AXI_ADDR_WIDTH (32),
        .AXI_DATA_WIDTH (32),
        .STREAM_WIDTH   (4),
        .BRAM_DEPTH     (48)
    ) dut (
        .clk_sys                (clk_sys),
        .rst_sys_n              (rst_sys_n),
        .clk_accel              (clk_accel),
        .rst_accel_n            (rst_accel_n),

        // --- Host AXI4-Lite Slave Interface -> DMA Configuration ---
        .s_dma_axi_lite_awaddr  (dma_if.awaddr),
        .s_dma_axi_lite_awvalid (dma_if.awvalid),
        .s_dma_axi_lite_awready (dma_if.awready),
        .s_dma_axi_lite_wdata   (dma_if.wdata),
        .s_dma_axi_lite_wvalid  (dma_if.wvalid),
        .s_dma_axi_lite_wready  (dma_if.wready),
        .s_dma_axi_lite_bresp   (dma_if.bresp),
        .s_dma_axi_lite_bvalid  (dma_if.bvalid),
        .s_dma_axi_lite_bready  (dma_if.bready),
        .s_dma_axi_lite_araddr  (dma_if.araddr),
        .s_dma_axi_lite_arvalid (dma_if.arvalid),
        .s_dma_axi_lite_arready (dma_if.arready),
        .s_dma_axi_lite_rdata   (dma_if.rdata),
        .s_dma_axi_lite_rresp   (dma_if.rresp),
        .s_dma_axi_lite_rvalid  (dma_if.rvalid),
        .s_dma_axi_lite_rready  (dma_if.rready),

        // --- RISC CPU AXI4-Lite Slave Interface -> BRAM Access ---
        .s_bram_axi_lite_awaddr (bram_if.awaddr),
        .s_bram_axi_lite_awvalid(bram_if.awvalid),
        .s_bram_axi_lite_awready(bram_if.awready),
        .s_bram_axi_lite_wdata  (bram_if.wdata),
        .s_bram_axi_lite_wstrb  (bram_if.wstrb),
        .s_bram_axi_lite_wvalid (bram_if.wvalid),
        .s_bram_axi_lite_wready (bram_if.wready),
        .s_bram_axi_lite_bresp  (bram_if.bresp),
        .s_bram_axi_lite_bvalid (bram_if.bvalid),
        .s_bram_axi_lite_bready (bram_if.bready),
        .s_bram_axi_lite_araddr (bram_if.araddr),
        .s_bram_axi_lite_arvalid(bram_if.arvalid),
        .s_bram_axi_lite_arready(bram_if.arready),
        .s_bram_axi_lite_rdata  (bram_if.rdata),
        .s_bram_axi_lite_rresp  (bram_if.rresp),
        .s_bram_axi_lite_rvalid (bram_if.rvalid),
        .s_bram_axi_lite_rready (bram_if.rready)
    );

    // =========================================================================
    // 4. UVM CONFIGURATION AND SIMULATION START
    // =========================================================================
    initial begin
        // Assign virtual interfaces to UVM Config DB
        uvm_config_db#(virtual axi_lite_if)::set(null, "uvm_test_top.env.dma_agent*",  "vif", dma_if);
        uvm_config_db#(virtual axi_lite_if)::set(null, "uvm_test_top.env.bram_agent*", "vif", bram_if);

        // Run UVM Test
        run_test("system_sanity_test");
    end

    // Waveform Dumper
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
    end

endmodule