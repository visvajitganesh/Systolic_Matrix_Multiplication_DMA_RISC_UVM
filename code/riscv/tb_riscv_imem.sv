`timescale 1ns / 1ps

module tb_riscv_imem;

    localparam DEPTH      = 1024;
    localparam CLK_PERIOD = 10;

    // DUT Signals
    logic        clk_i;
    logic        rst_i;                 // Active-High Reset
    logic [31:0] addr_i;
    logic [31:0] rdata_o;
    logic        error_unaligned_o;
    logic        error_out_of_bounds_o;

    int pass_count = 0;
    int fail_count = 0;

    // Instantiate DUT
    riscv_imem #(
        .DEPTH(DEPTH),
        .INIT_FILE("")
    ) dut (
        .clk_i                (clk_i),
        .rst_i                (rst_i),
        .addr_i               (addr_i),
        .rdata_o              (rdata_o),
        .error_unaligned_o    (error_unaligned_o),
        .error_out_of_bounds_o(error_out_of_bounds_o)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) clk_i = ~clk_i;

    // Helper Task for Response Checking
    task automatic check_response(
        input string       test_name,
        input logic [31:0] exp_rdata,
        input logic        exp_unaligned,
        input logic        exp_oob
    );
        // Sample 1 cycle after clock edge to match 1-cycle read latency
        @(posedge clk_i);
        #1;

        if (rdata_o === exp_rdata && 
            error_unaligned_o === exp_unaligned && 
            error_out_of_bounds_o === exp_oob) begin
            $display("[PASS] %-36s | rdata: 0x%08h | err_unaligned: %0b | err_oob: %0b",
                     test_name, rdata_o, error_unaligned_o, error_out_of_bounds_o);
            pass_count++;
        end else begin
            $error("[FAIL] %-36s\n  Expected -> rdata: 0x%08h, err_unaligned: %0b, err_oob: %0b\n  Actual   -> rdata: 0x%08h, err_unaligned: %0b, err_oob: %0b",
                   test_name, exp_rdata, exp_unaligned, exp_oob, rdata_o, error_unaligned_o, error_out_of_bounds_o);
            fail_count++;
        end
    endtask

    // Main Test Sequence
    initial begin
        clk_i  = 1'b0;
        rst_i  = 1'b0;
        addr_i = '0;

        // Pre-populate memory array directly
        dut.mem[0]           = 32'h00500513; // addi x10, x0, 5
        dut.mem[1]           = 32'h00a00593; // addi x11, x0, 10
        dut.mem[DEPTH / 2]   = 32'h12345678; // Test pattern at midpoint
        dut.mem[DEPTH - 1]   = 32'hDEADBEEF; // Test pattern at max legal index

        $display("==========================================================");
        $display("         STARTING RISC-V IMEM ROBUST VERIFICATION         ");
        $display("==========================================================");

        // -----------------------------------------------------------------
        // [TEST 1] Active-High Reset Asserted State
        // -----------------------------------------------------------------
        rst_i = 1'b1;
        #(CLK_PERIOD);
        
        if (rdata_o === 32'h0000_0013 && 
            error_unaligned_o === 1'b0 && 
            error_out_of_bounds_o === 1'b0) begin
            $display("[PASS] Reset State Check                  | Reset values correct (NOP state & flags clear).");
            pass_count++;
        end else begin
            $error("[FAIL] Reset State Check                  | rdata: 0x%08h (exp 0x00000013), err_unaligned: %0b (exp 0), err_oob: %0b (exp 0)",
                   rdata_o, error_unaligned_o, error_out_of_bounds_o);
            fail_count++;
        end

        // De-assert Reset
        @(posedge clk_i);
        rst_i = 1'b0;

        // -----------------------------------------------------------------
        // [TEST 2] Legal Aligned Access (Base, Mid, and Maximum Boundary)
        // -----------------------------------------------------------------
        addr_i = 32'h0000_0000;
        check_response("Legal Read: Index 0", 32'h00500513, 1'b0, 1'b0);

        addr_i = 32'h0000_0004;
        check_response("Legal Read: Index 1", 32'h00a00593, 1'b0, 1'b0);

        addr_i = (DEPTH / 2) * 4;
        check_response("Legal Read: Midpoint Index", 32'h12345678, 1'b0, 1'b0);

        addr_i = (DEPTH - 1) * 4;
        check_response("Legal Read: Max Index (DEPTH-1)", 32'hDEADBEEF, 1'b0, 1'b0);

        // -----------------------------------------------------------------
        // [TEST 3] Misaligned Fetch Exceptions (Offsets 1, 2, 3)
        // -----------------------------------------------------------------
        addr_i = 32'h0000_0001;
        check_response("Unaligned Fetch: Byte Offset 1", 32'h0000_0013, 1'b1, 1'b0);

        addr_i = 32'h0000_0002;
        check_response("Unaligned Fetch: Byte Offset 2", 32'h0000_0013, 1'b1, 1'b0);

        addr_i = 32'h0000_0003;
        check_response("Unaligned Fetch: Byte Offset 3", 32'h0000_0013, 1'b1, 1'b0);

        // -----------------------------------------------------------------
        // [TEST 4] Out-of-Bounds Exceptions
        // -----------------------------------------------------------------
        addr_i = DEPTH * 4; // Boundary word index 1024
        check_response("OOB Fetch: Exact Boundary (DEPTH)", 32'h0000_0013, 1'b0, 1'b1);

        addr_i = 32'h0001_0000;
        check_response("OOB Fetch: High Memory Address", 32'h0000_0013, 1'b0, 1'b1);

        // -----------------------------------------------------------------
        // [TEST 5] Dual Fault (Out-of-Bounds + Unaligned)
        // -----------------------------------------------------------------
        addr_i = (DEPTH * 4) + 2;
        check_response("Dual Fault: OOB + Unaligned", 32'h0000_0013, 1'b1, 1'b1);

        // -----------------------------------------------------------------
        // [TEST 6] Recovery from Faults
        // -----------------------------------------------------------------
        addr_i = 32'h0000_0000;
        check_response("Recovery: Legal Fetch After Faults", 32'h00500513, 1'b0, 1'b0);

        // -----------------------------------------------------------------
        // [TEST 7] Randomized Stress Read Sequence (100 Vectors)
        // -----------------------------------------------------------------
        $display("----------------------------------------------------------");
        $display("Starting Randomized Access Stress Phase (100 Cycles)...");
        
        for (int i = 0; i < 100; i++) begin
            logic [31:0] rand_addr;
            logic exp_u, exp_oob;
            logic [31:0] exp_data;

            rand_addr = $urandom();
            
            // Mask lower bits every 3rd iteration to hit legal paths periodically
            if (i % 3 == 0) rand_addr[1:0] = 2'b00;

            exp_u   = (rand_addr[1:0] != 2'b00);
            exp_oob = (rand_addr[31:2] >= DEPTH);
            
            if (!exp_u && !exp_oob) begin
                exp_data = dut.mem[rand_addr[31:2]];
            end else begin
                exp_data = 32'h0000_0013;
            end

            addr_i = rand_addr;
            check_response($sformatf("Random Vector #%0d", i + 1), exp_data, exp_u, exp_oob);
        end

        // -----------------------------------------------------------------
        // TEST SUMMARY
        // -----------------------------------------------------------------
        $display("==========================================================");
        $display("TESTBENCH COMPLETE");
        $display("Passed: %0d | Failed: %0d", pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0) begin
            $display(">> RESULT: ALL TESTS PASSED SUCCESSFULLY!");
        end else begin
            $error(">> RESULT: VERIFICATION FAILED WITH %0d ERRORS.", fail_count);
        end

        $finish;
    end

endmodule
