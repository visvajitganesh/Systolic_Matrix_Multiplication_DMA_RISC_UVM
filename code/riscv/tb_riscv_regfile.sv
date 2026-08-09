`timescale 1ns/1ps

module tb_riscv_regfile;

    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10; // 100 MHz clock

    // DUT Signals
    logic                  clk_i;
    logic                  rst_i;

    logic [4:0]            rd0_i;
    logic [DATA_WIDTH-1:0] rd0_value_i;
    logic                  rd0_wren_i;

    logic [4:0]            ra0_i;
    logic [4:0]            rb0_i;
    logic [DATA_WIDTH-1:0] ra0_value_o;
    logic [DATA_WIDTH-1:0] rb0_value_o;

    // Test Tracking
    int pass_count = 0;
    int fail_count = 0;

    // Instantiate Register File DUT
    riscv_regfile #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk_i       (clk_i),
        .rst_i       (rst_i),
        .rd0_i       (rd0_i),
        .rd0_value_i (rd0_value_i),
        .rd0_wren_i  (rd0_wren_i),
        .ra0_i       (ra0_i),
        .rb0_i       (rb0_i),
        .ra0_value_o (ra0_value_o),
        .rb0_value_o (rb0_value_o)
    );

    // Clock Generation (10ns period)
    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    // Task: Perform Register Write
    task automatic write_reg(input [4:0] reg_addr, input [DATA_WIDTH-1:0] data, input wren = 1'b1);
        @(negedge clk_i);
        rd0_i       = reg_addr;
        rd0_value_i = data;
        rd0_wren_i  = wren;
        @(posedge clk_i); // Write occurs on posedge
        #1;
        rd0_wren_i  = 1'b0;
    endtask

    // Task: Check Asynchronous Reads on Ports A and B
    task automatic check_read(input [4:0] ra_addr, input [DATA_WIDTH-1:0] exp_a,
                              input [4:0] rb_addr, input [DATA_WIDTH-1:0] exp_b,
                              input string test_name);
        ra0_i = ra_addr;
        rb0_i = rb_addr;
        #1; // Combinational evaluation delay

        if ((ra0_value_o === exp_a) && (rb0_value_o === exp_b)) begin
            $display("[PASS] %-35s | RA[x%0d]=0x%08h | RB[x%0d]=0x%08h", 
                     test_name, ra_addr, ra0_value_o, rb_addr, rb0_value_o);
            pass_count++;
        end else begin
            $display("** Error: [FAIL] %-28s | RA[x%0d] Exp:0x%08h Got:0x%08h | RB[x%0d] Exp:0x%08h Got:0x%08h",
                     test_name, ra_addr, exp_a, ra0_value_o, rb_addr, exp_b, rb0_value_o);
            fail_count++;
        end
    endtask

    // Stimulus Process
    initial begin
        // Initialize Signals
        clk_i       = 0;
        rst_i       = 0;
        rd0_i       = 0;
        rd0_value_i = 0;
        rd0_wren_i  = 0;
        ra0_i       = 0;
        rb0_i       = 0;

        $display("==========================================================");
        $display("         STARTING RISC-V REGFILE TESTBENCH                ");
        $display("==========================================================");

        // --------------------------------------------------------
        // Test 1: Reset Behavior Check
        // --------------------------------------------------------
        @(negedge clk_i);
        rst_i = 1'b1;
        @(posedge clk_i);
        #1;
        rst_i = 1'b0;

        check_read(5'd1, 32'h0000_0000, 5'd31, 32'h0000_0000, "Reset Value Check (x1 & x31)");

        // --------------------------------------------------------
        // Test 2: Invariance of x0 (Zero Register)
        // --------------------------------------------------------
        write_reg(5'd0, 32'hDEAD_BEEF, 1'b1); // Attempt to overwrite x0
        check_read(5'd0, 32'h0000_0000, 5'd0, 32'h0000_0000, "x0 Write Suppression Check");

        // --------------------------------------------------------
        // Test 3: Write and Readback Sweep (x1 to x31)
        // --------------------------------------------------------
        for (int i = 1; i < 32; i++) begin
            write_reg(5'(i), 32'h1000_0000 + i);
        end

        // Verify readback across dual ports using 5'() width cast
        for (int i = 1; i < 31; i += 2) begin
            check_read(5'(i), 32'h1000_0000 + i, 
                       5'(i + 1), 32'h1000_0000 + (i + 1), 
                       $sformatf("Dual Read x%0d & x%0d", i, i + 1));
        end

        // --------------------------------------------------------
        // Test 4: Write Enable (wren = 0) Disable Check
        // --------------------------------------------------------
        write_reg(5'd10, 32'hFFFF_FFFF, 1'b0); // Attempt write with wren=0
        check_read(5'd10, 32'h1000_000A, 5'd0, 32'h0000_0000, "wren=0 Disables Write Check");

        // --------------------------------------------------------
        // Test 5: Verify Asynchronous Read (No Clock Edge Required)
        // --------------------------------------------------------
        ra0_i = 5'd15;
        rb0_i = 5'd20;
        #1; // Without toggling clk_i
        if ((ra0_value_o === 32'h1000_000F) && (rb0_value_o === 32'h1000_0014)) begin
            $display("[PASS] %-35s | RA[x15]=0x%08h | RB[x20]=0x%08h", 
                     "Async Read Propagation Check", ra0_value_o, rb0_value_o);
            pass_count++;
        end else begin
            $display("** Error: [FAIL] Async Read Propagation Check");
            fail_count++;
        end

        // --------------------------------------------------------
        // Test Summary
        // --------------------------------------------------------
        $display("==========================================================");
        $display("   TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0)
            $display(" >>> ALL REGFILE TESTS PASSED <<<");
        else
            $display(" >>> SOME REGFILE TESTS FAILED - CHECK TRANSCRIPT <<<");

        $finish;
    end

endmodule