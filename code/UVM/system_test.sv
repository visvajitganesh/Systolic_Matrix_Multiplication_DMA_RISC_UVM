`include "uvm_macros.svh"
import uvm_pkg::*;
import tb_pkg::*; 

// =========================================================================
// CUSTOM TEST SEQUENCES
// =========================================================================

// --- Sequence for STEP 1: Initialize BRAM with Random Matrices ---
class bram_init_seq extends axi_lite_base_seq;
    `uvm_object_utils(bram_init_seq)
    
    function new(string name="bram_init_seq"); 
        super.new(name); 
    endfunction
    
    task body();
        // Write 4 consecutive 32-bit words ($urandom generates fresh random values each loop)
        for (int i = 0; i < 4; i++) begin
            write_reg(i * 4, $urandom());
        end
    endtask
endclass

// --- Sequence for STEP 3: Poll DMA Status ---
class dma_poll_seq extends axi_lite_base_seq;
    `uvm_object_utils(dma_poll_seq)
    
    function new(string name="dma_poll_seq"); 
        super.new(name); 
    endfunction
    
    task body();
        bit [31:0] status_data = 32'h0;
        int timeout_count = 0;
        
        // Wait for Bit 1 (Done bit) in register 0x04
        while ((status_data & 32'h0000_0002) == 0) begin
            read_reg(32'h04, status_data);
            #50;
            timeout_count++;
            
            if (timeout_count >= 100) begin
                `uvm_fatal("DMA_TIMEOUT", "DMA failed to set Done bit (0x04[1]) within 5000ns!")
            end
        end
    endtask
endclass

// --- Sequence for STEP 4: Read BRAM Results ---
class bram_readback_seq extends axi_lite_base_seq;
    `uvm_object_utils(bram_readback_seq)
    
    function new(string name="bram_readback_seq"); 
        super.new(name); 
    endfunction
    
    task body();
        bit [31:0] dummy_data;
        // Read 2 output words from offset 0x100
        for (int i = 0; i < 2; i++) begin
            read_reg(32'h0100 + (i * 4), dummy_data);
        end
    endtask
endclass


// =========================================================================
// TOP-LEVEL MULTI-TEST
// =========================================================================
class system_sanity_test extends uvm_test;
    `uvm_component_utils(system_sanity_test)

    system_env env;
    int TOTAL_RUNS = 1000; // Number of test iterations

    function new(string name = "system_sanity_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = system_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        bram_init_seq     init_seq;
        dma_config_seq    dma_seq;
        dma_poll_seq      poll_seq;
        bram_readback_seq read_seq;

        phase.raise_objection(this);

        `uvm_info("TEST", "Waiting for hardware reset...", UVM_LOW)
        #100;
        `uvm_info("TEST", "Hardware reset released. Starting 100-Iteration Stress Test...", UVM_LOW)

        // Create sequence instances
        init_seq = bram_init_seq::type_id::create("init_seq");
        dma_seq  = dma_config_seq::type_id::create("dma_seq");
        poll_seq = dma_poll_seq::type_id::create("poll_seq");
        read_seq = bram_readback_seq::type_id::create("read_seq");

        // --- 100 ITERATION LOOP ---
        for (int iter = 1; iter <= TOTAL_RUNS; iter++) begin
            `uvm_info("TEST_LOOP", $sformatf("================ STARTING ITERATION %0d / %0d ================", iter, TOTAL_RUNS), UVM_LOW)

            // Step 1: Write Random Input Matrices to BRAM
            init_seq.start(env.bram_agent.sequencer);

            // Step 2: Configure & Trigger DMA Transfer
            dma_seq.src_addr  = 32'h0000_0000;
            dma_seq.dest_addr = 32'h0000_0100;
            dma_seq.xfer_len  = 32'd16;
            dma_seq.start(env.dma_agent.sequencer);

            // Step 3: Wait for Hardware Acceleration to Finish
            poll_seq.start(env.dma_agent.sequencer);

            // Step 4: Readback Results & Trigger Scoreboard Comparisons
            read_seq.start(env.bram_agent.sequencer);
        end

        `uvm_info("TEST", $sformatf("ALL %0d ITERATIONS FINISHED SUCCESSFULLY!", TOTAL_RUNS), UVM_LOW)
        phase.drop_objection(this);
    endtask

endclass