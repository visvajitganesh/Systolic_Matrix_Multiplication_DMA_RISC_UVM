`timescale 1ns / 1ps

package tb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Analysis IMP Declarations for Scoreboard and Coverage
    `uvm_analysis_imp_decl(_dma)
    `uvm_analysis_imp_decl(_bram)
    `uvm_analysis_imp_decl(_dma_cov)
    `uvm_analysis_imp_decl(_bram_cov)

    // =========================================================================
    // 1. TYPEDEFS & SEQUENCE ITEMS
    // =========================================================================
    typedef enum bit {
        AXI_READ  = 1'b0,
        AXI_WRITE = 1'b1
    } axi_req_type_e;

    class axi_lite_seq_item extends uvm_sequence_item;
        rand axi_req_type_e req_type;
        rand bit [31:0]     addr;
        rand bit [31:0]     data;
        rand bit [3:0]      wstrb;

        bit [31:0]          rdata;
        bit [1:0]           resp;

        `uvm_object_utils_begin(axi_lite_seq_item)
            `uvm_field_enum(axi_req_type_e, req_type, UVM_ALL_ON)
            `uvm_field_int(addr,  UVM_ALL_ON)
            `uvm_field_int(data,  UVM_ALL_ON)
            `uvm_field_int(wstrb, UVM_ALL_ON)
            `uvm_field_int(rdata, UVM_ALL_ON)
            `uvm_field_int(resp,  UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "axi_lite_seq_item");
            super.new(name);
        endfunction

        constraint align_32 {
            addr % 4 == 0;
            wstrb == 4'b1111; 
        }

        virtual function string convert2string();
            if (req_type == AXI_WRITE)
                return $sformatf("WRITE -> Addr: 0x%08h | Data: 0x%08h | Strb: 4'b%04b | Resp: %0d", addr, data, wstrb, resp);
            else
                return $sformatf("READ  -> Addr: 0x%08h | RData: 0x%08h | Resp: %0d", addr, rdata, resp);
        endfunction
    endclass

    // =========================================================================
    // 2. SEQUENCER
    // =========================================================================
    class axi_lite_sequencer extends uvm_sequencer #(axi_lite_seq_item);
        `uvm_component_utils(axi_lite_sequencer)

        function new(string name = "axi_lite_sequencer", uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    // =========================================================================
    // 3. DRIVER
    // =========================================================================
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
            vif.awvalid <= 1'b0;
            vif.wvalid  <= 1'b0;
            vif.bready  <= 1'b0;
            vif.arvalid <= 1'b0;
            vif.rready  <= 1'b0;

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

        task drive_write(axi_lite_seq_item item);
            int aw_timeout = 0;
            int w_timeout  = 0;
            int b_timeout  = 0;

            `uvm_info("DRV_WR", $sformatf("[%s] Driving WRITE -> Addr: 0x%08h | Data: 0x%08h", get_full_name(), item.addr, item.data), UVM_LOW)

            @ (posedge vif.clk);
            vif.awaddr  <= item.addr;
            vif.awvalid <= 1'b1;
            vif.wdata   <= item.data;
            vif.wstrb   <= item.wstrb;
            vif.wvalid  <= 1'b1;
            vif.bready  <= 1'b1;

            fork
                begin
                    while (!vif.awready) begin
                        @ (posedge vif.clk);
                        aw_timeout++;
                        if (aw_timeout > 100) begin
                            `uvm_fatal("DRV_TIMEOUT", $sformatf("[%s] Timeout waiting for AWREADY at Addr 0x%08h!", get_full_name(), item.addr))
                        end
                    end
                    @ (posedge vif.clk);
                    vif.awvalid <= 1'b0;
                end
                begin
                    while (!vif.wready) begin
                        @ (posedge vif.clk);
                        w_timeout++;
                        if (w_timeout > 100) begin
                            `uvm_fatal("DRV_TIMEOUT", $sformatf("[%s] Timeout waiting for WREADY at Addr 0x%08h!", get_full_name(), item.addr))
                        end
                    end
                    @ (posedge vif.clk);
                    vif.wvalid <= 1'b0; // <-- TYPO FIXED HERE
                end
            join

            while (!vif.bvalid) begin
                @ (posedge vif.clk);
                b_timeout++;
                if (b_timeout > 100) begin
                    `uvm_fatal("DRV_TIMEOUT", $sformatf("[%s] Timeout waiting for BVALID response at Addr 0x%08h!", get_full_name(), item.addr))
                end
            end

            item.resp = vif.bresp;
            @ (posedge vif.clk);
            vif.bready <= 1'b0;
            `uvm_info("DRV_WR", $sformatf("[%s] WRITE COMPLETE -> Addr: 0x%08h", get_full_name(), item.addr), UVM_LOW)
        endtask

        task drive_read(axi_lite_seq_item item);
            int ar_timeout = 0;
            int r_timeout  = 0;

            `uvm_info("DRV_RD", $sformatf("[%s] Driving READ -> Addr: 0x%08h", get_full_name(), item.addr), UVM_LOW)

            @ (posedge vif.clk);
            vif.araddr  <= item.addr;
            vif.arvalid <= 1'b1;
            vif.rready  <= 1'b1;

            while (!vif.arready) begin
                @ (posedge vif.clk);
                ar_timeout++;
                if (ar_timeout > 100) begin
                    `uvm_fatal("DRV_TIMEOUT", $sformatf("[%s] Timeout waiting for ARREADY at Addr 0x%08h!", get_full_name(), item.addr))
                end
            end
            @ (posedge vif.clk);
            vif.arvalid <= 1'b0;

            while (!vif.rvalid) begin
                @ (posedge vif.clk);
                r_timeout++;
                if (r_timeout > 100) begin
                    `uvm_fatal("DRV_TIMEOUT", $sformatf("[%s] Timeout waiting for RVALID response at Addr 0x%08h!", get_full_name(), item.addr))
                end
            end

            item.rdata = vif.rdata;
            item.resp  = vif.rresp;
            @ (posedge vif.clk);
            vif.rready <= 1'b0;
            `uvm_info("DRV_RD", $sformatf("[%s] READ COMPLETE -> Addr: 0x%08h | RData: 0x%08h", get_full_name(), item.addr, item.rdata), UVM_LOW)
        endtask
    endclass

    // =========================================================================
    // 4. MONITOR
    // =========================================================================
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
            fork
                monitor_writes();
                monitor_reads();
            join_none
        endtask

        task monitor_writes();
            axi_lite_seq_item wr_item;
            forever begin
                wr_item = axi_lite_seq_item::type_id::create("wr_item");
                wr_item.req_type = AXI_WRITE;

                fork
                    begin
                        do begin
                            @ (posedge vif.clk);
                        end while (!(vif.awvalid && vif.awready));
                        wr_item.addr = vif.awaddr;
                    end
                    begin
                        do begin
                            @ (posedge vif.clk);
                        end while (!(vif.wvalid && vif.wready));
                        wr_item.data  = vif.wdata;
                        wr_item.wstrb = vif.wstrb;
                    end
                join

                do begin
                    @ (posedge vif.clk);
                end while (!(vif.bvalid && vif.bready));
                
                wr_item.resp = vif.bresp;
                `uvm_info("MON_WR", $sformatf("[%s] Observed WRITE: %s", get_full_name(), wr_item.convert2string()), UVM_LOW)
                ap.write(wr_item); 
            end
        endtask

        task monitor_reads();
            axi_lite_seq_item rd_item;
            forever begin
                rd_item = axi_lite_seq_item::type_id::create("rd_item");
                rd_item.req_type = AXI_READ;

                do begin
                    @ (posedge vif.clk);
                end while (!(vif.arvalid && vif.arready));
                rd_item.addr = vif.araddr;

                do begin
                    @ (posedge vif.clk);
                end while (!(vif.rvalid && vif.rready));
                
                rd_item.rdata = vif.rdata;
                rd_item.resp  = vif.rresp;
                `uvm_info("MON_RD", $sformatf("[%s] Observed READ: %s", get_full_name(), rd_item.convert2string()), UVM_LOW)
                ap.write(rd_item); 
            end
        endtask
    endclass

    // =========================================================================
    // 5. AGENT
    // =========================================================================
    class axi_lite_agent extends uvm_agent;
        `uvm_component_utils(axi_lite_agent)

        axi_lite_driver    driver;
        axi_lite_monitor   monitor;
        axi_lite_sequencer sequencer;

        uvm_analysis_port #(axi_lite_seq_item) ap;

        function new(string name = "axi_lite_agent", uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            
            ap = new("ap", this);
            monitor = axi_lite_monitor::type_id::create("monitor", this);
            
            if (get_is_active() == UVM_ACTIVE) begin
                driver    = axi_lite_driver::type_id::create("driver", this);
                sequencer = axi_lite_sequencer::type_id::create("sequencer", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            monitor.ap.connect(ap);
            if (get_is_active() == UVM_ACTIVE) begin
                driver.seq_item_port.connect(sequencer.seq_item_export);
            end
        endfunction
    endclass

    // =========================================================================
    // 6. LICENSE-SAFE FUNCTIONAL COVERAGE SUBSCRIBER
    // =========================================================================
    class system_coverage extends uvm_component;
        `uvm_component_utils(system_coverage)

        uvm_analysis_imp_dma_cov  #(axi_lite_seq_item, system_coverage) dma_cov_export;
        uvm_analysis_imp_bram_cov #(axi_lite_seq_item, system_coverage) bram_cov_export;

        // Bin Counters
        int hit_reg_ctrl = 0;
        int hit_reg_stat = 0;
        int hit_reg_src  = 0;
        int hit_reg_dst  = 0;
        int hit_reg_len  = 0;
        int hit_bram_in  = 0;
        int hit_bram_out = 0;

        int hit_op_read  = 0;
        int hit_op_write = 0;

        int hit_dma_start = 0;

        int hit_nibble_zero = 0;
        int hit_nibble_max  = 0;
        int hit_nibble_mid  = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            dma_cov_export  = new("dma_cov_export", this);
            bram_cov_export = new("bram_cov_export", this);
        endfunction

        // Track DMA Register Accesses
        virtual function void write_dma_cov(axi_lite_seq_item t);
            if (t.req_type == AXI_READ)  hit_op_read++;
            if (t.req_type == AXI_WRITE) hit_op_write++;

            case (t.addr[7:0])
                8'h00: begin
                    hit_reg_ctrl++;
                    if (t.req_type == AXI_WRITE && t.data[0] == 1'b1) hit_dma_start++;
                end
                8'h04: hit_reg_stat++;
                8'h08: hit_reg_src++;
                8'h0C: hit_reg_dst++;
                8'h10: hit_reg_len++;
            endcase
        endfunction

        // Track BRAM Input Writes and Output Readbacks
        virtual function void write_bram_cov(axi_lite_seq_item t);
            if (t.req_type == AXI_READ)  hit_op_read++;
            if (t.req_type == AXI_WRITE) hit_op_write++;

            if (t.addr >= 32'h0000_0000 && t.addr <= 32'h0000_000C) begin
                hit_bram_in++;
            end else if (t.addr >= 32'h0000_0100 && t.addr <= 32'h0000_0104) begin
                hit_bram_out++;
            end

            if (t.req_type == AXI_WRITE) begin
                for (int i = 0; i < 8; i++) begin
                    bit [3:0] nibble = t.data[i*4 +: 4];
                    if (nibble == 4'h0)      hit_nibble_zero++;
                    else if (nibble == 4'hF) hit_nibble_max++;
                    else                     hit_nibble_mid++;
                end
            end
        endfunction

        virtual function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            print_coverage_report();
        endfunction

        function void print_coverage_report();
            real addr_cov, op_cov, data_cov, total_cov;
            int addr_bins_hit = 0;
            int total_addr_bins = 7;

            if (hit_reg_ctrl > 0) addr_bins_hit++;
            if (hit_reg_stat > 0) addr_bins_hit++;
            if (hit_reg_src  > 0) addr_bins_hit++;
            if (hit_reg_dst  > 0) addr_bins_hit++;
            if (hit_reg_len  > 0) addr_bins_hit++;
            if (hit_bram_in  > 0) addr_bins_hit++;
            if (hit_bram_out > 0) addr_bins_hit++;

            addr_cov = (addr_bins_hit / real'(total_addr_bins)) * 100.0;
            op_cov   = ((hit_op_read > 0 && hit_op_write > 0) ? 100.0 : 50.0);
            
            begin
                int data_bins_hit = 0;
                if (hit_nibble_zero > 0) data_bins_hit++;
                if (hit_nibble_max  > 0) data_bins_hit++;
                if (hit_nibble_mid  > 0) data_bins_hit++;
                data_cov = (data_bins_hit / 3.0) * 100.0;
            end

            total_cov = (addr_cov + op_cov + data_cov) / 3.0;

            `uvm_info("COV_REPORT", "\n==================================================", UVM_NONE)
            `uvm_info("COV_REPORT", "       FUNCTIONAL COVERAGE SUMMARY REPORT         ", UVM_NONE)
            `uvm_info("COV_REPORT", "==================================================", UVM_NONE)
            `uvm_info("COV_REPORT", $sformatf(" Register Address Coverage : %0.2f%% (%0d/%0d registers hit)", addr_cov, addr_bins_hit, total_addr_bins), UVM_NONE)
            `uvm_info("COV_REPORT", $sformatf(" AXI Operation Coverage   : %0.2f%% (Reads: %0d, Writes: %0d)", op_cov, hit_op_read, hit_op_write), UVM_NONE)
            `uvm_info("COV_REPORT", $sformatf(" Data Pattern Coverage    : %0.2f%% (Zero: %0d, Max: %0d, Mid: %0d)", data_cov, hit_nibble_zero, hit_nibble_max, hit_nibble_mid), UVM_NONE)
            `uvm_info("COV_REPORT", $sformatf(" DMA Start Triggers       : %0d Start Pulses", hit_dma_start), UVM_NONE)
            `uvm_info("COV_REPORT", "--------------------------------------------------", UVM_NONE)
            `uvm_info("COV_REPORT", $sformatf(" TOTAL FUNCTIONAL COVERAGE : %0.2f%%", total_cov), UVM_NONE)
            `uvm_info("COV_REPORT", "==================================================\n", UVM_NONE)
        endfunction
    endclass

    // =========================================================================
    // 7. BASE SEQUENCE
    // =========================================================================
    class axi_lite_base_seq extends uvm_sequence #(axi_lite_seq_item);
        `uvm_object_utils(axi_lite_base_seq)

        function new(string name = "axi_lite_base_seq");
            super.new(name);
        endfunction

        task write_reg(input bit [31:0] waddr, input bit [31:0] wdata);
            axi_lite_seq_item req = axi_lite_seq_item::type_id::create("req");
            start_item(req);
            
            req.req_type = AXI_WRITE;
            req.addr     = waddr;
            req.data     = wdata;
            req.wstrb    = 4'b1111;
            
            finish_item(req);
        endtask
        
        task read_reg(input bit [31:0] raddr, output bit [31:0] rdata);
            axi_lite_seq_item req = axi_lite_seq_item::type_id::create("req");
            start_item(req);
            
            req.req_type = AXI_READ;
            req.addr     = raddr;
            req.wstrb    = 4'b1111;
            
            finish_item(req);
            rdata = req.rdata; 
        endtask
    endclass

    class dma_config_seq extends axi_lite_base_seq;
        `uvm_object_utils(dma_config_seq)

        bit [31:0] src_addr;
        bit [31:0] dest_addr;
        bit [31:0] xfer_len;

        function new(string name = "dma_config_seq");
            super.new(name);
        endfunction

        task body();
            `uvm_info("DMA_SEQ", "Starting DMA Configuration...", UVM_LOW)
            write_reg(32'h08, src_addr);
            write_reg(32'h0C, dest_addr);
            write_reg(32'h10, xfer_len);
            write_reg(32'h00, 32'h0000_0001);
            `uvm_info("DMA_SEQ", "DMA Configuration Complete! Transfer started.", UVM_LOW)
        endtask
    endclass

    // =========================================================================
    // 8. SCOREBOARD
    // =========================================================================
    class system_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(system_scoreboard)

        uvm_analysis_imp_dma  #(axi_lite_seq_item, system_scoreboard) dma_export;
        uvm_analysis_imp_bram #(axi_lite_seq_item, system_scoreboard) bram_export;

        bit [31:0] shadow_bram   [int]; 
        bit [31:0] expected_bram [int]; 

        bit [31:0] dma_src_addr;
        bit [31:0] dma_dest_addr;
        bit [31:0] dma_xfer_len;

        function new(string name = "system_scoreboard", uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            dma_export  = new("dma_export", this);
            bram_export = new("bram_export", this);
        endfunction

        virtual function void write_dma(axi_lite_seq_item item);
            if (item.req_type == AXI_WRITE) begin
                case (item.addr[7:0])
                    8'h08: dma_src_addr  = item.data; 
                    8'h0C: dma_dest_addr = item.data; 
                    8'h10: dma_xfer_len  = item.data; 
                    8'h00: begin                      
                        if (item.data[0] == 1'b1) begin
                            `uvm_info("SCB", "DMA Start Detected! Running Predictor...", UVM_LOW)
                            predict_systolic_result();
                        end
                    end
                endcase
            end
        endfunction

        virtual function void write_bram(axi_lite_seq_item item);
            if (item.req_type == AXI_WRITE) begin
                shadow_bram[item.addr] = item.data;
                `uvm_info("SCB_BRAM", $sformatf("Stored BRAM[0x%08h] = 0x%08h", item.addr, item.data), UVM_HIGH)
            end 
            else if (item.req_type == AXI_READ) begin
                if (expected_bram.exists(item.addr)) begin
                    if (item.rdata === expected_bram[item.addr]) begin
                        `uvm_info("SCB_PASS", $sformatf("Match at 0x%08h: Read 0x%08h", item.addr, item.rdata), UVM_LOW)
                    end else begin
                        `uvm_error("SCB_FAIL", $sformatf("Mismatch at 0x%08h! Expected: 0x%08h, Actual: 0x%08h", item.addr, expected_bram[item.addr], item.rdata))
                    end
                end
            end
        endfunction

        virtual function void predict_systolic_result();
            bit [3:0] mat_A [0:3][0:3];
            bit [3:0] mat_B [0:3][0:3];
            bit [3:0] mat_C [0:3][0:3]; 
            
            bit [31:0] src_data [0:3];
            bit [31:0] expected_word_0 = 0;
            bit [31:0] expected_word_1 = 0;
            
            int idx;

            `uvm_info("SCB_PRED", "Extracting matrices from Shadow BRAM...", UVM_LOW)

            for (int i = 0; i < 4; i++) begin
                if (shadow_bram.exists(dma_src_addr + (i * 4))) begin
                    src_data[i] = shadow_bram[dma_src_addr + (i * 4)];
                end else begin
                    `uvm_error("SCB_PRED", $sformatf("Missing BRAM data at 0x%08h", dma_src_addr + (i*4)))
                end
            end

            idx = 0;
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    mat_A[i][j] = src_data[idx / 8][(idx % 8) * 4 +: 4];
                    idx++;
                end
            end

            idx = 0;
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    mat_B[i][j] = src_data[2 + (idx / 8)][(idx % 8) * 4 +: 4];
                    idx++;
                end
            end

            `uvm_info("SCB_PRED", "Calculating Golden Math (C = A * B)...", UVM_LOW)
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    bit [7:0] temp_mac = 0;
                    for (int k = 0; k < 4; k++) begin
                        temp_mac = temp_mac + (mat_A[i][k] * mat_B[k][j]); 
                    end
                    mat_C[i][j] = temp_mac[3:0]; 
                end
            end

            idx = 0;
            for (int i = 0; i < 4; i++) begin
                for (int j = 0; j < 4; j++) begin
                    if (idx < 8) begin
                        expected_word_0[(idx % 8) * 4 +: 4] = mat_C[i][j];
                    end else begin
                        expected_word_1[(idx % 8) * 4 +: 4] = mat_C[i][j];
                    end
                    idx++;
                end
            end

            expected_bram[dma_dest_addr]     = expected_word_0;
            expected_bram[dma_dest_addr + 4] = expected_word_1;
            
            `uvm_info("SCB_PRED", $sformatf("Expected Word 0: 0x%08h, Word 1: 0x%08h", expected_word_0, expected_word_1), UVM_LOW)
        endfunction
    endclass

    // =========================================================================
    // 9. ENVIRONMENT
    // =========================================================================
    class system_env extends uvm_env;
        `uvm_component_utils(system_env)

        axi_lite_agent   dma_agent;
        axi_lite_agent   bram_agent;
        system_scoreboard scoreboard;
        system_coverage   coverage;

        function new(string name = "system_env", uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            dma_agent  = axi_lite_agent::type_id::create("dma_agent", this);
            bram_agent = axi_lite_agent::type_id::create("bram_agent", this);
            scoreboard = system_scoreboard::type_id::create("scoreboard", this);
            coverage   = system_coverage::type_id::create("coverage", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            // Connect agents to scoreboard
            dma_agent.monitor.ap.connect(scoreboard.dma_export);
            bram_agent.monitor.ap.connect(scoreboard.bram_export);

            // Connect agents to coverage collector
            dma_agent.monitor.ap.connect(coverage.dma_cov_export);
            bram_agent.monitor.ap.connect(coverage.bram_cov_export);
        endfunction
    endclass

endpackage