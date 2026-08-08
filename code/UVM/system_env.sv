`include "uvm_macros.svh"
import uvm_pkg::*;

class system_env extends uvm_env;
    `uvm_component_utils(system_env)

    // Agents
    axi_lite_agent dma_agent;
    axi_lite_agent bram_agent;
    
    // Scoreboard
    system_scoreboard scoreboard;

    function new(string name = "system_env", uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        // Create the agents
        dma_agent  = axi_lite_agent::type_id::create("dma_agent", this);
        bram_agent = axi_lite_agent::type_id::create("bram_agent", this);
        
        // Create the scoreboard
        scoreboard = system_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        
        // Connect the DMA monitor to the scoreboard's DMA export
        dma_agent.monitor.ap.connect(scoreboard.dma_export);
        
        // Connect the BRAM monitor to the scoreboard's BRAM export
        bram_agent.monitor.ap.connect(scoreboard.bram_export);
    endfunction

endclass