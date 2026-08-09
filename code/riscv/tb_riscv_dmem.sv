`timescale 1ns/1ps

module tb_riscv_dmem;

    // Parameters
    localparam DEPTH      = 256;
    localparam CLK_PERIOD = 10; // 100 MHz clock

    // DUT Signals
    logic        clk_i;
    logic [31:0] addr_i;
    logic [31:0] wdata_i;
    logic  [3:0] wstrb_i;
    logic [31:0] rdata_o;

    // Test Tracking
    int pass_count = 0;
    int fail_count = 0;

    // Instantiate Data Memory DUT
    riscv_dmem #(
        .DEPTH(DEPTH),
        .INIT_FILE("")
    ) dut (
        .clk_i   (clk_i),
        .addr_i  (addr_i),
        .wdata_i (wdata_i),
        .wstrb_i (wstrb_i),
        .rdata_o (rdata_o)
    );

    // Clock Generation (10ns period)
    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    // Task: Perform Memory Write
    task automatic mem_write(input [31:0] addr, input [31:0] data, input [3:0] strb);
        @(negedge clk_i);
        addr_i  = addr;
        wdata_i = data;
        wstrb_i = strb;
        @(posedge clk_i); // Write occurs on posedge
        #1;
        wstrb_i = 4'b0000; // De-assert write strobe
    endtask

    // Task: Perform Memory Read & Check
    task automatic mem_read_check(input [31:0] addr, input [31:0] expected, input string test_name);
        @(negedge clk_i);
        addr_i  = addr;
        wstrb_i = 4'b0000;
        @(posedge clk_i); // Synchronous read latches data into rdata_o
        #1;
        if (rdata_o === expected) begin
            $display("[PASS] %-35s | Addr: 0x%08h | Expected: 0x%08h | Got: 0x%08h", 
                     test_name, addr, expected, rdata_o);
            pass_count++;
        end else begin
            $display("** Error: [FAIL] %-28s | Addr: 0x%08h | Expected: 0x%08h | Got: 0x%08h", 
                     test_name, addr, expected, rdata_o);
            fail_count++;
        end
    endtask

    // Stimulus Process
    initial begin
        // Initialize Signals
        clk_i   = 0;
        addr_i  = 0;
        wdata_i = 0;
        wstrb_i = 0;

        $display("==========================================================");
        $display("          STARTING RISC-V DMEM TESTBENCH                  ");
        $display("==========================================================");

        // --------------------------------------------------------
        // Test 1: Verify Zero-Fill Initialization
        // --------------------------------------------------------
        mem_read_check(32'h0000_0000, 32'h0000_0000, "Init Check Addr 0");
        mem_read_check(32'h0000_0004, 32'h0000_0000, "Init Check Addr 4");

        // --------------------------------------------------------
        // Test 2: Full-Word Write (SW)
        // --------------------------------------------------------
        mem_write(32'h0000_0000, 32'hDEAD_BEEF, 4'b1111);
        mem_read_check(32'h0000_0000, 32'hDEAD_BEEF, "Word Write (SW) Addr 0");

        mem_write(32'h0000_0004, 32'h1234_5678, 4'b1111);
        mem_read_check(32'h0000_0004, 32'h1234_5678, "Word Write (SW) Addr 4");

        // --------------------------------------------------------
        // Test 3: Byte Writes using wstrb (SB)
        // Target address: 0x0000_0008 (Initially 0x0000_0000)
        // --------------------------------------------------------
        // Write Byte 0 [7:0]
        mem_write(32'h0000_0008, 32'h0000_00AA, 4'b0001);
        mem_read_check(32'h0000_0008, 32'h0000_00AA, "Byte 0 Write (SB)");

        // Write Byte 2 [23:16] without disturbing Byte 0
        mem_write(32'h0000_0008, 32'h00CC_0000, 4'b0100);
        mem_read_check(32'h0000_0008, 32'h00CC_00AA, "Byte 2 Write (Preserve Byte 0)");

        // --------------------------------------------------------
        // Test 4: Half-Word Writes using wstrb (SH)
        // Target address: 0x0000_000C
        // --------------------------------------------------------
        // Write Upper Half-Word [31:16]
        mem_write(32'h0000_000C, 32'hCAFE_0000, 4'b1100);
        mem_read_check(32'h0000_000C, 32'hCAFE_0000, "Upper Half-Word Write (SH)");

        // Write Lower Half-Word [15:0]
        mem_write(32'h0000_000C, 32'h0000_BABE, 4'b0011);
        mem_read_check(32'h0000_000C, 32'hCAFE_BABE, "Lower Half-Word Write (SH)");

        // --------------------------------------------------------
        // Test 5: Word-Alignment Slicing Verification
        // Addresses 0x10, 0x11, 0x12, 0x13 should all map to memory index 4
        // --------------------------------------------------------
        mem_write(32'h0000_0010, 32'hA5A5_5A5A, 4'b1111);
        mem_read_check(32'h0000_0013, 32'hA5A5_5A5A, "Unaligned Address Read (Addr 0x13)");

        // --------------------------------------------------------
        // Final Test Summary
        // --------------------------------------------------------
        $display("==========================================================");
        $display("   TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0)
            $display(" >>> ALL DMEM TESTS PASSED <<<");
        else
            $display(" >>> SOME DMEM TESTS FAILED - CHECK TRANSCRIPT <<<");

        $finish;
    end

endmodule