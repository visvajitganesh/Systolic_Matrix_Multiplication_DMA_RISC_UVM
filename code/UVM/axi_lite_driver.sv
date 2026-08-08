`include "uvm_macros.svh"
import uvm_pkg::*;

class axi_lite_driver extends uvm_driver #(axi_lite_seq_item);
    `uvm_component_utils(axi_lite_driver)

    virtual axi_lite_if vif;

    function new(string name = "axi_lite_driver", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("DRV_NOVIF", "Virtual interface not set for driver!")
        end
    endfunction

    task run_phase(uvm_phase phase);
        // Initialize signals to idle state
        vif.awvalid <= 0;
        vif.wvalid  <= 0;
        vif.bready  <= 0;
        vif.arvalid <= 0;
        vif.rready  <= 0;

        forever begin
            seq_item_port.get_next_item(req);
            
            if (req.req_type == AXI_WRITE) begin
                drive_write(req);
            end else begin
                drive_read(req);
            end
            
            seq_item_port.item_done();
        end
    endtask

    // --- AXI4-Lite Write Transaction ---
    task drive_write(axi_lite_seq_item item);
        `uvm_info("DRV", $sformatf("Driving WRITE to Addr: 0x%08h", item.addr), UVM_HIGH)
        
        // 1. Drive Address and Data concurrently (AXI allows this)
        fork
            // Address Channel (AW)
            begin
                vif.drv_cb.awaddr  <= item.addr;
                vif.drv_cb.awvalid <= 1'b1;
                wait(vif.drv_cb.awready == 1'b1);
                @ (vif.drv_cb);
                vif.drv_cb.awvalid <= 1'b0;
            end
            // Data Channel (W)
            begin
                vif.drv_cb.wdata   <= item.data;
                vif.drv_cb.wstrb   <= item.wstrb;
                vif.drv_cb.wvalid  <= 1'b1;
                wait(vif.drv_cb.wready == 1'b1);
                @ (vif.drv_cb);
                vif.drv_cb.wvalid  <= 1'b0;
            end
        join

        // 2. Wait for Response (B)
        vif.drv_cb.bready <= 1'b1;
        wait(vif.drv_cb.bvalid == 1'b1);
        item.resp = vif.drv_cb.bresp; // Capture the response back into the sequence item
        @ (vif.drv_cb);
        vif.drv_cb.bready <= 1'b0;
    endtask

    // --- AXI4-Lite Read Transaction ---
    task drive_read(axi_lite_seq_item item);
        `uvm_info("DRV", $sformatf("Driving READ from Addr: 0x%08h", item.addr), UVM_HIGH)
        
        // 1. Drive Address (AR)
        vif.drv_cb.araddr  <= item.addr;
        vif.drv_cb.arvalid <= 1'b1;
        wait(vif.drv_cb.arready == 1'b1);
        @ (vif.drv_cb);
        vif.drv_cb.arvalid <= 1'b0;

        // 2. Wait for Data (R)
        vif.drv_cb.rready <= 1'b1;
        wait(vif.drv_cb.rvalid == 1'b1);
        item.rdata = vif.drv_cb.rdata; // Capture read data
        item.resp  = vif.drv_cb.rresp;
        @ (vif.drv_cb);
        vif.drv_cb.rready <= 1'b0;
    endtask

endclass