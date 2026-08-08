`include "uvm_macros.svh"
import uvm_pkg::*;

// Create custom analysis import ports to handle multiple streams of the same item type
`uvm_analysis_imp_decl(_dma)
`uvm_analysis_imp_decl(_bram)

class system_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(system_scoreboard)

    // Analysis imports from the two agents
    uvm_analysis_imp_dma  #(axi_lite_seq_item, system_scoreboard) dma_export;
    uvm_analysis_imp_bram #(axi_lite_seq_item, system_scoreboard) bram_export;

    // Shadow Memory Model (Associative Arrays)
    bit [31:0] shadow_bram   [int]; // Tracks actual BRAM state
    bit [31:0] expected_bram [int]; // Stores expected output matrix C

    // DMA Configuration State
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

    // ------------------------------------------------------------------------
    // DMA PORT HANDLER: Tracks DMA Configuration & Triggers Predictor
    // ------------------------------------------------------------------------
    virtual function void write_dma(axi_lite_seq_item item);
        if (item.req_type == AXI_WRITE) begin
            case (item.addr[7:0])
                8'h08: dma_src_addr  = item.data; // ADDR_SRC[cite: 6]
                8'h0C: dma_dest_addr = item.data; // ADDR_DEST[cite: 6]
                8'h10: dma_xfer_len  = item.data; // ADDR_LEN[cite: 6]
                8'h00: begin                      // ADDR_CTRL[cite: 6]
                    if (item.data[0] == 1'b1) begin
                        `uvm_info("SCB", "DMA Start Detected! Running Predictor...", UVM_LOW)
                        predict_systolic_result();
                    end
                end
            endcase
        end
    endfunction

    // ------------------------------------------------------------------------
    // BRAM PORT HANDLER: Tracks Memory Writes & Checks Memory Reads
    // ------------------------------------------------------------------------
    virtual function void write_bram(axi_lite_seq_item item);
        if (item.req_type == AXI_WRITE) begin
            // Host is writing A/B matrices into BRAM
            shadow_bram[item.addr] = item.data;
            `uvm_info("SCB_BRAM", $sformatf("Stored BRAM[0x%08h] = 0x%08h", item.addr, item.data), UVM_HIGH)
        end 
        else if (item.req_type == AXI_READ) begin
            // Host is reading BRAM. If it's reading the destination address, verify it!
            if (expected_bram.exists(item.addr)) begin
                if (item.rdata === expected_bram[item.addr]) begin
                    `uvm_info("SCB_PASS", $sformatf("Match at 0x%08h: Read 0x%08h", item.addr, item.rdata), UVM_LOW)
                end else begin
                    `uvm_error("SCB_FAIL", $sformatf("Mismatch at 0x%08h! Expected: 0x%08h, Actual: 0x%08h", item.addr, expected_bram[item.addr], item.rdata))
                end
            end
        end
    endfunction

    // ------------------------------------------------------------------------
    // PREDICTOR: Golden Model for the Matrix Multiplication
    // ------------------------------------------------------------------------
    virtual function void predict_systolic_result();
        bit [3:0] mat_A [0:3][0:3];
        bit [3:0] mat_B [0:3][0:3];
        bit [3:0] mat_C [0:3][0:3]; // 4-bit output (matching PSUM_WIDTH = 4)
        
        bit [31:0] src_data [0:3];
        bit [31:0] expected_word_0 = 0;
        bit [31:0] expected_word_1 = 0;
        
        int idx;

        `uvm_info("SCB_PRED", "Extracting matrices from Shadow BRAM...", UVM_LOW)

        // 1. Read the 4 words (16 bytes) from our shadow memory
        // Word 0 & 1: Matrix B (Weights), Word 2 & 3: Matrix A (Inputs)
        // Note: You may need to swap A and B depending on how your software packs them!
        for (int i = 0; i < 4; i++) begin
            if (shadow_bram.exists(dma_src_addr + (i * 4))) begin
                src_data[i] = shadow_bram[dma_src_addr + (i * 4)];
            end else begin
                `uvm_error("SCB_PRED", $sformatf("Missing BRAM data at 0x%08h", dma_src_addr + (i*4)))
            end
        end

        // 2. Unpack the 32-bit words into 4x4 2D arrays
        // Packing assumes 4 bits per element. 8 elements per 32-bit word.
        idx = 0;
        for (int i = 0; i < 4; i++) begin
            for (int j = 0; j < 4; j++) begin
                // Extract 4 bits at a time.
                // Depending on Little/Big endian, the bit slice `[(idx%8)*4 +: 4]` might need reversing.
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

        // 3. Compute Matrix Multiplication: C = A * B
        `uvm_info("SCB_PRED", "Calculating Golden Math (C = A * B)...", UVM_LOW)
        for (int i = 0; i < 4; i++) begin
            for (int j = 0; j < 4; j++) begin
                bit [7:0] temp_mac = 0;
                for (int k = 0; k < 4; k++) begin
                    // Formula for MAC operation[cite: 11]
                    temp_mac = temp_mac + (mat_A[i][k] * mat_B[k][j]); 
                end
                // Truncate to PSUM_WIDTH (4 bits)[cite: 13, 1]
                mat_C[i][j] = temp_mac[3:0]; 
            end
        end

        // 4. Pack the result back into two 32-bit words
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

        // 5. Save to expected_bram for the read monitor to verify
        expected_bram[dma_dest_addr]     = expected_word_0;
        expected_bram[dma_dest_addr + 4] = expected_word_1;
        
        `uvm_info("SCB_PRED", $sformatf("Expected Word 0: 0x%08h, Word 1: 0x%08h", expected_word_0, expected_word_1), UVM_LOW)

    endfunction

endclass