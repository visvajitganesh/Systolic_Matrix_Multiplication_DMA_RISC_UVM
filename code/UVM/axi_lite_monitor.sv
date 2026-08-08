`include "uvm_macros.svh"
import uvm_pkg::*;

class axi_lite_monitor extends uvm_monitor;
    `uvm_component_utils(axi_lite_monitor)

    virtual axi_lite_if vif;
    uvm_analysis_port #(axi_lite_seq_item) ap;

    function new(string name = "axi_lite_monitor", uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_lite_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("MON_NOVIF", "Virtual interface not set for monitor!")
        end
    endfunction

    task run_phase(uvm_phase phase);
        // Run read and write monitors concurrently
        fork
            monitor_writes();
            monitor_reads();
        join_none
    endtask

    // --- Monitor Write Transactions ---
    task monitor_writes();
        axi_lite_seq_item wr_item;
        
        forever begin
            wr_item = axi_lite_seq_item::type_id::create("wr_item");
            wr_item.req_type = AXI_WRITE;

            // Wait for Address Phase
            wait(vif.mon_cb.awvalid && vif.mon_cb.awready);
            wr_item.addr = vif.mon_cb.awaddr;
            @ (vif.mon_cb); // Wait next clock tick
            
            // Wait for Data Phase
            wait(vif.mon_cb.wvalid && vif.mon_cb.wready);
            wr_item.data  = vif.mon_cb.wdata;
            wr_item.wstrb = vif.mon_cb.wstrb;
            @ (vif.mon_cb);
            
            // Wait for Response Phase
            wait(vif.mon_cb.bvalid && vif.mon_cb.bready);
            wr_item.resp = vif.mon_cb.bresp;
            
            `uvm_info("MON_WR", $sformatf("Observed WRITE: %s", wr_item.convert2string()), UVM_HIGH)
            ap.write(wr_item); // Broadcast to scoreboard
            @ (vif.mon_cb);
        end
    endtask

    // --- Monitor Read Transactions ---
    task monitor_reads();
        axi_lite_seq_item rd_item;
        
        forever begin
            rd_item = axi_lite_seq_item::type_id::create("rd_item");
            rd_item.req_type = AXI_READ;

            // Wait for Address Phase
            wait(vif.mon_cb.arvalid && vif.mon_cb.arready);
            rd_item.addr = vif.mon_cb.araddr;
            @ (vif.mon_cb);
            
            // Wait for Data Phase
            wait(vif.mon_cb.rvalid && vif.mon_cb.rready);
            rd_item.rdata = vif.mon_cb.rdata;
            rd_item.resp  = vif.mon_cb.rresp;
            
            `uvm_info("MON_RD", $sformatf("Observed READ: %s", rd_item.convert2string()), UVM_HIGH)
            ap.write(rd_item); // Broadcast to scoreboard
            @ (vif.mon_cb);
        end
    endtask

endclass