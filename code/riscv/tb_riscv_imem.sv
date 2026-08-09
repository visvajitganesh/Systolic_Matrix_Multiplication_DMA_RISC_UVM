`timescale 1ns/1ps

module tb_riscv_imem;

    // Parameters
    localparam DEPTH      = 256;
    localparam CLK_PERIOD = 10; // 100 MHz clock

    // DUT Signals
    logic        clk_i;
    logic [31:0] addr_i;
    logic [31:0] rdata_o;

    // Test Tracking
    int pass_count = 0;
    int fail_count = 0;

    // Instantiate Instruction Memory DUT
    riscv_imem #(
        .DEPTH(DEPTH),
        .INIT_FILE("") // Empty = populated directly by testbench
    ) dut (
        .clk_i   (clk_i),
        .addr_i  (addr_i),
        .rdata_o (rdata_o)
    );

    // Clock Generation (10ns period)
    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    // Task: Check Instruction Fetch
    task automatic check_fetch(input [31:0] fetch_addr, input [31:0] expected_instr, input string test_name);
        @(negedge clk_i);
        addr_i = fetch_addr;
        @(posedge clk_i); // Synchronous read latches instruction into rdata_o
        #1;
        if (rdata_o === expected_instr) begin
            $display("[PASS] %-35s | PC: 0x%08h | Instr: 0x%08h", 
                     test_name, fetch_addr, rdata_o);
            pass_count++;
        end else begin
            $display("** Error: [FAIL] %-28s | PC: 0x%08h | Expected: 0x%08h | Got: 0x%08h", 
                     test_name, fetch_addr, expected_instr, rdata_o);
            fail_count++;
        end
    endtask

    // Stimulus Process
    initial begin
        // Initialize Signals
        clk_i  = 0;
        addr_i = 0;

        // Pre-load memory array with test instructions
        dut.mem[0] = 32'h00500593; // addi x11, x0, 5    (PC = 0x00)
        dut.mem[1] = 32'h00a00613; // addi x12, x0, 10   (PC = 0x04)
        dut.mem[2] = 32'h00c586b3; // add  x13, x11, x12 (PC = 0x08)
        dut.mem[3] = 32'h00d60733; // add  x14, x12, x13 (PC = 0x0C)
        dut.mem[8] = 32'h0000006f; // jal  x0, 0         (PC = 0x20)

        $display("==========================================================");
        $display("          STARTING RISC-V IMEM TESTBENCH                  ");
        $display("==========================================================");

        // --------------------------------------------------------
        // Test 1: Sequential Fetch (Simulating Instruction Pipeline)
        // --------------------------------------------------------
        check_fetch(32'h0000_0000, 32'h00500593, "Fetch Addr 0x00 (addi x11)");
        check_fetch(32'h0000_0004, 32'h00a00613, "Fetch Addr 0x04 (addi x12)");
        check_fetch(32'h0000_0008, 32'h00c586b3, "Fetch Addr 0x08 (add x13)");
        check_fetch(32'h0000_000C, 32'h00d60733, "Fetch Addr 0x0C (add x14)");

        // --------------------------------------------------------
        // Test 2: Word-Alignment Slicing (addr_i[31:2])
        // Addresses 0x04, 0x05, 0x06, 0x07 must all return word index 1
        // --------------------------------------------------------
        check_fetch(32'h0000_0005, 32'h00a00613, "Unaligned Fetch Addr 0x05");
        check_fetch(32'h0000_0006, 32'h00a00613, "Unaligned Fetch Addr 0x06");
        check_fetch(32'h0000_0007, 32'h00a00613, "Unaligned Fetch Addr 0x07");

        // --------------------------------------------------------
        // Test 3: Non-Sequential Jump / Branch Fetch Target
        // --------------------------------------------------------
        check_fetch(32'h0000_0020, 32'h0000006f, "Branch/Jump Target Addr 0x20");

        // --------------------------------------------------------
        // Final Test Summary
        // --------------------------------------------------------
        $display("==========================================================");
        $display("   TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0)
            $display(" >>> ALL IMEM TESTS PASSED <<<");
        else
            $display(" >>> SOME IMEM TESTS FAILED - CHECK TRANSCRIPT <<<");

        $finish;
    end

endmodule