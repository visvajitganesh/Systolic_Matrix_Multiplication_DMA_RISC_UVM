`include "uvm_macros.svh"
import uvm_pkg::*;

class axi_lite_agent extends uvm_agent;
    `uvm_component_utils(axi_lite_agent)

    // Sub-components
    axi_lite_driver    driver;
    axi_lite_monitor   monitor;
    axi_lite_sequencer sequencer;

    // Analysis port to broadcast transactions to the Scoreboard
    uvm_analysis_port #(axi_lite_seq_item) ap;

    function new(string name = "axi_lite_agent", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        ap = new("ap", this);
        monitor = axi_lite_monitor::type_id::create("monitor", this);
        
        // Only build driver and sequencer if the agent is active
        if (get_is_active() == UVM_ACTIVE) begin
            driver    = axi_lite_driver::type_id::create("driver", this);
            sequencer = axi_lite_sequencer::type_id::create("sequencer", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Connect monitor to the agent's analysis port
        monitor.ap.connect(ap);
        
        // Connect sequencer to driver
        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
        end
    endfunction

endclass