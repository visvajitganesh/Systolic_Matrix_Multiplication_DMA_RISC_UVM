`timescale 1ns/1ps

module tb_riscv_lsu;

    // ------------------------------------------------------------------------
    // Clock & Reset Signals
    // ------------------------------------------------------------------------
    logic        clk_i;
    logic        rst_i;

    // Control Inputs
    logic        stall_i;

    // Interface from riscv_pipe_ctrl (MEM stage)
    logic        valid_mem_i;
    logic        is_load_mem_i;
    logic        is_store_mem_i;
    logic [31:0] addr_mem_i;
    logic [31:0] store_data_mem_i;
    logic  [1:0] mem_size_mem_i;
    logic        mem_unsigned_mem_i;

    // Interface to Data Memory
    logic [31:0] dmem_addr_o;
    logic [31:0] dmem_wdata_o;
    logic  [3:0] dmem_wstrb_o;
    logic [31:0] dmem_rdata_i;

    // Interface back to riscv_pipe_ctrl
    logic [31:0] mem_rdata_o;

    // Testbench stats
    int pass_count = 0;
    int fail_count = 0;

    // ------------------------------------------------------------------------
    // Device Under Test (DUT) Instantiation
    // ------------------------------------------------------------------------
    riscv_lsu dut (
        .clk_i               (clk_i),
        .rst_i               (rst_i),
        .stall_i             (stall_i),

        .valid_mem_i         (valid_mem_i),
        .is_load_mem_i       (is_load_mem_i),
        .is_store_mem_i      (is_store_mem_i),
        .addr_mem_i          (addr_mem_i),
        .store_data_mem_i    (store_data_mem_i),
        .mem_size_mem_i      (mem_size_mem_i),
        .mem_unsigned_mem_i  (mem_unsigned_mem_i),

        .dmem_addr_o         (dmem_addr_o),
        .dmem_wdata_o        (dmem_wdata_o),
        .dmem_wstrb_o        (dmem_wstrb_o),
        .dmem_rdata_i        (dmem_rdata_i),

        .mem_rdata_o         (mem_rdata_o)
    );

    // ------------------------------------------------------------------------
    // Clock Generation (100 MHz, 10ns period)
    // ------------------------------------------------------------------------
    always #5 clk_i = ~clk_i;

    // ------------------------------------------------------------------------
    // Helper Tasks
    // ------------------------------------------------------------------------
    task automatic check_val(string msg, logic [31:0] actual, logic [31:0] expected);
        if (actual === expected) begin
            $display("[PASS] %s = 0x%08h", msg, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s = 0x%08h (Expected: 0x%08h)", msg, actual, expected);
            fail_count++;
        end
    endtask

    task automatic check_strb(string msg, logic [3:0] actual, logic [3:0] expected);
        if (actual === expected) begin
            $display("[PASS] %s = 4'b%04b", msg, actual);
            pass_count++;
        end else begin
            $display("[FAIL] %s = 4'b%04b (Expected: 4'b%04b)", msg, actual, expected);
            fail_count++;
        end
    endtask

    task automatic clear_inputs();
        stall_i            = 1'b0;
        valid_mem_i        = 1'b0;
        is_load_mem_i      = 1'b0;
        is_store_mem_i     = 1'b0;
        addr_mem_i         = '0;
        store_data_mem_i   = '0;
        mem_size_mem_i     = '0;
        mem_unsigned_mem_i = 1'b0;
        dmem_rdata_i       = '0;
    endtask

    // ------------------------------------------------------------------------
    // Test Sequence
    // ------------------------------------------------------------------------
    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;
        clear_inputs();

        $display("==========================================================");
        $display("             STARTING RISC-V LSU TESTBENCH                ");
        $display("==========================================================");

        repeat (2) @(posedge clk_i);
        #1;
        rst_i = 1'b0;

        // --------------------------------------------------------------------
        // Test 1: Reset Check
        // --------------------------------------------------------------------
        $display("\n--- Test 1: Reset & Idle State Check ---");
        check_val("mem_rdata_o post-reset", mem_rdata_o, 32'h0);
        check_strb("dmem_wstrb_o idle", dmem_wstrb_o, 4'b0000);

        // --------------------------------------------------------------------
        // Test 2: Store Operations (Combinational Strobe & Data Formatting)
        // --------------------------------------------------------------------
        $display("\n--- Test 2: Store Operations (SB, SH, SW) ---");
        
        valid_mem_i      = 1'b1;
        is_store_mem_i   = 1'b1;
        store_data_mem_i = 32'h1234_5678;

        // Byte Stores (mem_size = 2'b00) across offsets 0, 1, 2, 3
        mem_size_mem_i = 2'b00;
        
        addr_mem_i = 32'h1000_0000; #1; // Byte 0
        check_strb("SB offset 0 wstrb", dmem_wstrb_o, 4'b0001);
        check_val("SB offset 0 wdata", dmem_wdata_o, 32'h7878_7878);

        addr_mem_i = 32'h1000_0001; #1; // Byte 1
        check_strb("SB offset 1 wstrb", dmem_wstrb_o, 4'b0010);

        addr_mem_i = 32'h1000_0002; #1; // Byte 2
        check_strb("SB offset 2 wstrb", dmem_wstrb_o, 4'b0100);

        addr_mem_i = 32'h1000_0003; #1; // Byte 3
        check_strb("SB offset 3 wstrb", dmem_wstrb_o, 4'b1000);

        // Halfword Stores (mem_size = 2'b01)
        mem_size_mem_i = 2'b01;

        addr_mem_i = 32'h1000_0000; #1; // Half 0
        check_strb("SH offset 0 wstrb", dmem_wstrb_o, 4'b0011);
        check_val("SH offset 0 wdata", dmem_wdata_o, 32'h5678_5678);

        addr_mem_i = 32'h1000_0002; #1; // Half 1
        check_strb("SH offset 2 wstrb", dmem_wstrb_o, 4'b1100);

        // Word Store (mem_size = 2'b10)
        mem_size_mem_i = 2'b10;
        addr_mem_i     = 32'h1000_0000; #1;
        check_strb("SW wstrb", dmem_wstrb_o, 4'b1111);
        check_val("SW wdata", dmem_wdata_o, 32'h1234_5678);

        clear_inputs();

        // --------------------------------------------------------------------
        // Test 3: Load Byte Operations (LB and LBU)
        // --------------------------------------------------------------------
        $display("\n--- Test 3: Load Byte (LB - Signed & LBU - Unsigned) ---");
        
        // Setup a load from memory returning 0x80_AB_CD_EF (Byte 3 = 0x80 -> Negative MSB)
        @(negedge clk_i);
        valid_mem_i        = 1'b1;
        is_load_mem_i      = 1'b1;
        mem_size_mem_i     = 2'b00; // Byte
        mem_unsigned_mem_i = 1'b0;  // Signed LB
        addr_mem_i         = 32'h2000_0003; // Point to Byte 3 (0x80)

        @(posedge clk_i); #1; // Register metadata in LSU
        dmem_rdata_i = 32'h80AB_CDEF; #1;
        check_val("LB (Signed) Byte 3 (0x80)", mem_rdata_o, 32'hFFFF_FF80);

        // Unsigned Load Byte (LBU) on same address
        @(negedge clk_i);
        mem_unsigned_mem_i = 1'b1; // LBU
        addr_mem_i         = 32'h2000_0003;

        @(posedge clk_i); #1;
        dmem_rdata_i = 32'h80AB_CDEF; #1;
        check_val("LBU (Unsigned) Byte 3 (0x80)", mem_rdata_o, 32'h0000_0080);

        // --------------------------------------------------------------------
        // Test 4: Load Halfword Operations (LH and LHU)
        // --------------------------------------------------------------------
        $display("\n--- Test 4: Load Halfword (LH - Signed & LHU - Unsigned) ---");

        // LH on upper halfword (0x80AB -> Negative MSB)
        @(negedge clk_i);
        valid_mem_i        = 1'b1;
        is_load_mem_i      = 1'b1;
        mem_size_mem_i     = 2'b01; // Halfword
        mem_unsigned_mem_i = 1'b0;  // LH
        addr_mem_i         = 32'h2000_0002; // Halfword 1

        @(posedge clk_i); #1;
        dmem_rdata_i = 32'h80AB_CDEF; #1;
        check_val("LH (Signed) Upper Half (0x80AB)", mem_rdata_o, 32'hFFFF_80AB);

        // LHU on upper halfword
        @(negedge clk_i);
        mem_unsigned_mem_i = 1'b1; // LHU

        @(posedge clk_i); #1;
        dmem_rdata_i = 32'h80AB_CDEF; #1;
        check_val("LHU (Unsigned) Upper Half (0x80AB)", mem_rdata_o, 32'h0000_80AB);

        // --------------------------------------------------------------------
        // Test 5: Load Word Operation (LW)
        // --------------------------------------------------------------------
        $display("\n--- Test 5: Load Word (LW) ---");

        @(negedge clk_i);
        valid_mem_i        = 1'b1;
        is_load_mem_i      = 1'b1;
        mem_size_mem_i     = 2'b10; // Word
        mem_unsigned_mem_i = 1'b0;
        addr_mem_i         = 32'h2000_0000;

        @(posedge clk_i); #1;
        dmem_rdata_i = 32'hDEAD_BEEF; #1;
        check_val("LW (Full Word)", mem_rdata_o, 32'hDEAD_BEEF);

        clear_inputs();

        // --------------------------------------------------------------------
        // Test 6: Stall Handling (stall_i = 1)
        // --------------------------------------------------------------------
        $display("\n--- Test 6: Pipeline Stall Register Freeze ---");

        // Step 1: Issue LBU for Byte 1
        @(negedge clk_i);
        valid_mem_i        = 1'b1;
        is_load_mem_i      = 1'b1;
        mem_size_mem_i     = 2'b00; // Byte
        mem_unsigned_mem_i = 1'b1;  // LBU
        addr_mem_i         = 32'h3000_0001; // Byte 1

        @(posedge clk_i); #1; // Latch metadata in LSU

        // Step 2: Assert stall_i and change input interface signals to dummy values
        @(negedge clk_i);
        stall_i            = 1'b1;
        valid_mem_i        = 1'b0;
        addr_mem_i         = 32'h4000_0003; // Overwrite input address
        mem_size_mem_i     = 2'b10;

        @(posedge clk_i); #1; // Clock edge occurs during stall

        // Memory response arrives for the frozen request (Byte 1 = 0x44)
        dmem_rdata_i = 32'h1122_4455; #1;
        check_val("Stalled Load (Retains Byte 1 LBU setup)", mem_rdata_o, 32'h0000_0044);

        // Release stall
        @(negedge clk_i);
        stall_i = 1'b0;
        clear_inputs();
        @(posedge clk_i); #1;

        // --------------------------------------------------------------------
        // Test Summary
        // --------------------------------------------------------------------
        $display("\n==========================================================");
        $display("   TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0) begin
            $display(" >>> ALL TESTS PASSED SUCCESSFULLY! <<<\n");
        end else begin
            $display(" >>> SOME TESTS FAILED - CHECK TRANSCRIPT <<< \n");
        end

        $finish;
    end

endmodule