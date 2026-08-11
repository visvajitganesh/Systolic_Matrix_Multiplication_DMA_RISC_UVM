`timescale 1ns / 1ps

module tb_riscv_dmem;

    localparam DEPTH      = 1024;
    localparam CLK_PERIOD = 10;

    // DUT Signals
    logic        clk_i;
    logic        rst_i;
    logic [31:0] addr_i;
    logic [31:0] wdata_i;
    logic [3:0]  wstrb_i;

    logic [31:0] rdata_o;
    logic        error_unaligned_o;
    logic        error_out_of_bounds_o;

    int pass_count = 0;
    int fail_count = 0;

    // Instantiate 1-Cycle Latency DUT
    riscv_dmem #(
        .DEPTH(DEPTH),
        .INIT_FILE("")
    ) dut (
        .clk_i                (clk_i),
        .rst_i                (rst_i),
        .addr_i               (addr_i),
        .wdata_i              (wdata_i),
        .wstrb_i              (wstrb_i),
        .rdata_o              (rdata_o),
        .error_unaligned_o    (error_unaligned_o),
        .error_out_of_bounds_o(error_out_of_bounds_o)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) clk_i = ~clk_i;

    // Output Verification Task (Evaluates 1 Cycle After Driving Command)
    task automatic verify_step(
        input string       test_name,
        input logic [31:0] exp_rdata,
        input logic        exp_unaligned,
        input logic        exp_oob
    );
        @(posedge clk_i);
        #1; // Sample output after clock edge propagation

        if (rdata_o === exp_rdata && 
            error_unaligned_o === exp_unaligned && 
            error_out_of_bounds_o === exp_oob) begin
            $display("[PASS] %-45s | rdata: 0x%08h | unalign: %0b | oob: %0b", 
                     test_name, rdata_o, error_unaligned_o, error_out_of_bounds_o);
            pass_count++;
        end else begin
            $error("[FAIL] %-45s\n       Expected -> rdata: 0x%08h, unaligned: %0b, oob: %0b\n       Actual   -> rdata: 0x%08h, unaligned: %0b, oob: %0b", 
                   test_name, exp_rdata, exp_unaligned, exp_oob, 
                   rdata_o, error_unaligned_o, error_out_of_bounds_o);
            fail_count++;
        end
    endtask

    initial begin
        // Signal Initialization
        clk_i   = 1'b0;
        rst_i   = 1'b1;
        addr_i  = '0;
        wdata_i = '0;
        wstrb_i = 4'b0000;

        $display("=======================================================================");
        $display("          STARTING 1-CYCLE LATENCY RISC-V DMEM VERIFICATION           ");
        $display("=======================================================================");

        // -----------------------------------------------------------------
        // [TEST 1] Active Reset State Verification
        // -----------------------------------------------------------------
        repeat (2) @(posedge clk_i);
        #1;
        if (rdata_o === 32'h0 && !error_unaligned_o && !error_out_of_bounds_o) begin
            $display("[PASS] TEST 1: Synchronous Reset Assertion");
            pass_count++;
        end else begin
            $error("[FAIL] TEST 1: Synchronous Reset Assertion failed");
            fail_count++;
        end

        // Release Reset
        @(posedge clk_i);
        rst_i = 1'b0;

        // -----------------------------------------------------------------
        // [TEST 2] Standard 1-Cycle Read/Write Latency
        // -----------------------------------------------------------------
        // Cycle 1: Drive Write Request to 0x0000_0004
        addr_i  = 32'h0000_0004;
        wdata_i = 32'hDEAD_BEEF;
        wstrb_i = 4'b1111;
        
        // Cycle 2: Drive Read Request to 0x0000_0004
        @(posedge clk_i);
        addr_i  = 32'h0000_0004;
        wstrb_i = 4'b0000;

        // Cycle 3: Check read data arriving exactly 1 cycle after read command
        verify_step("TEST 2: Standard 1-Cycle Read Latency", 32'hDEAD_BEEF, 1'b0, 1'b0);

        // -----------------------------------------------------------------
        // [TEST 3] Same-Cycle Read-During-Write Pass-Through Forwarding
        // -----------------------------------------------------------------
        // Simultaneously write and read address 0x0000_0008 in Cycle N
        addr_i  = 32'h0000_0008;
        wdata_i = 32'h1234_5678;
        wstrb_i = 4'b1111;

        // Verify output in Cycle N+1 contains forwarded wdata
        verify_step("TEST 3: Same-Cycle Read-During-Write Forwarding", 32'h1234_5678, 1'b0, 1'b0);

        // -----------------------------------------------------------------
        // [TEST 4] Partial Byte Strobe Read-Through Combination
        // -----------------------------------------------------------------
        // Cycle N: Pre-fill address 0x0000_000C with 0x0000_0000
        addr_i  = 32'h0000_000C;
        wdata_i = 32'h0000_0000;
        wstrb_i = 4'b1111;
        @(posedge clk_i);

        // Cycle N+1: Overwrite upper half-word (bytes 2 & 3) with 0xAA55
        addr_i  = 32'h0000_000C;
        wdata_i = 32'hAA55_0000;
        wstrb_i = 4'b1100; // Strobes [3:2] active

        // Verify in Cycle N+2 that output combines new bytes [3:2] with stored bytes [1:0]
        verify_step("TEST 4: Byte-Strobe Pass-Through Merging", 32'hAA55_0000, 1'b0, 1'b0);

        // -----------------------------------------------------------------
        // [TEST 5] Unaligned Address Exception Handling
        // -----------------------------------------------------------------
        // Issue unaligned address 0x0000_0003 (addr[1:0] = 2'b11)
        addr_i  = 32'h0000_0003;
        wstrb_i = 4'b0000;

        // Verify unaligned flag is set and rdata is zeroed after 1 cycle
        verify_step("TEST 5: Unaligned Access Exception Flag", 32'h0000_0000, 1'b1, 1'b0);

        // -----------------------------------------------------------------
        // [TEST 6] Out-of-Bounds Exception Handling
        // -----------------------------------------------------------------
        // Issue address exceeding DEPTH (1024 words -> 0x0000_1000 = word 1024)
        addr_i  = 32'h0000_1000;
        wstrb_i = 4'b0000;

        // Verify out-of-bounds flag is set and rdata is zeroed after 1 cycle
        verify_step("TEST 6: Out-of-Bounds Access Exception Flag", 32'h0000_0000, 1'b0, 1'b1);

        // Clear control signals
        addr_i  = 32'h0000_0000;
        wstrb_i = 4'b0000;
        @(posedge clk_i);

        // -----------------------------------------------------------------
        // TESTBENCH SUMMARY
        // -----------------------------------------------------------------
        $display("=======================================================================");
        $display("TESTBENCH COMPLETE");
        $display("Total Passed: %0d | Total Failed: %0d", pass_count, fail_count);
        $display("=======================================================================");

        if (fail_count == 0) begin
            $display("SUCCESS: All 1-cycle latency requirements met cleanly.");
        end else begin
            $error("FAILURE: %0d verification check(s) failed.", fail_count);
        end

        $finish;
    end

endmodule
