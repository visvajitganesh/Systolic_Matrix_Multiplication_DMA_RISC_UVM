`timescale 1ns / 1ps

// Self-checking testbench for accel_top (input_fifo -> systolic -> output_fifo).
// Bit-ordering: send A then B row-major (32 nibbles in); receive C row-major (16 nibbles out).

module tb_accel_top;

    // --- Parameters ---
    localparam int MATRIX_SIZE     = 4;   // 4x4 matrices

    localparam int IN_DATA_WIDTH   = 4;   // input stream width (bits)
    localparam int IN_DATA_WIDTH_M = 4;   // input element width (bits)
    localparam int IN_DEPTH        = 32;  // input FIFO depth

    localparam int OUT_DATA_WIDTH   = 4;  // output stream width (bits)
    localparam int OUT_DATA_WIDTH_M = 4;  // output element width (bits)
    localparam int OUT_DEPTH        = 16; // output FIFO depth

    localparam int TOTAL_IN_NIBBLES  = 2 * MATRIX_SIZE * MATRIX_SIZE;                // 32: A + B
    localparam int NIBBLES_PER_ELEM  = OUT_DATA_WIDTH_M / OUT_DATA_WIDTH;            // 1 nibble per C element
    localparam int TOTAL_OUT_NIBBLES = MATRIX_SIZE * MATRIX_SIZE * NIBBLES_PER_ELEM; // 16: full C matrix

    localparam int NUM_TESTS = 6; // stress-mode iterations


    // --- Clocks / resets ---
    logic clk_sys   = 0;  // system-side clock (I/O interfaces)
    logic clk_accel = 0;  // accelerator-side clock (systolic array)
    logic rst_sys_n;
    logic rst_accel_n;

    always #5.0 clk_sys   = ~clk_sys;   // 100 MHz
    always #3.5 clk_accel = ~clk_accel; // ~142.8 MHz

    // --- DUT I/O ---
    logic [IN_DATA_WIDTH-1:0]  in_tdata;   // input nibble
    logic                      in_tvalid;
    logic                      in_tready;
    logic                      in_tlast;

    logic [OUT_DATA_WIDTH-1:0] out_tdata;  // output nibble
    logic                      out_tvalid;
    logic                      out_tready;
    logic                      out_tlast;

    // --- DUT instantiation ---
    accel_top #(
        .MATRIX_SIZE     (MATRIX_SIZE),
        .IN_DATA_WIDTH   (IN_DATA_WIDTH),
        .IN_DATA_WIDTH_M (IN_DATA_WIDTH_M),
        .IN_DEPTH        (IN_DEPTH),
        .OUT_DATA_WIDTH   (OUT_DATA_WIDTH),
        .OUT_DATA_WIDTH_M (OUT_DATA_WIDTH_M),
        .OUT_DEPTH        (OUT_DEPTH)
    ) dut (
        .clk_sys     (clk_sys),
        .rst_sys_n   (rst_sys_n),
        .clk_accel   (clk_accel),
        .rst_accel_n (rst_accel_n),

        .in_tdata  (in_tdata),
        .in_tvalid (in_tvalid),
        .in_tready (in_tready),
        .in_tlast  (in_tlast),

        .out_tdata  (out_tdata),
        .out_tvalid (out_tvalid),
        .out_tready (out_tready),
        .out_tlast  (out_tlast)
    );

    // --- Reset: hold both domains in reset, then release and settle ---
    task automatic do_reset();
        rst_sys_n   = 0;
        rst_accel_n = 0;
        in_tvalid   = 0;
        in_tlast    = 0;
        in_tdata    = '0;
        out_tready  = 0;
        repeat (5) @(posedge clk_sys);
        repeat (5) @(posedge clk_accel);
        rst_sys_n   = 1;
        rst_accel_n = 1;
        repeat (3) @(posedge clk_sys);
    endtask


    // --- Input driver: send one nibble with valid/ready handshake.
    //     If allow_stall, randomly insert 1-3 idle cycles before asserting valid. ---
    task automatic send_nibble(input logic [IN_DATA_WIDTH-1:0] data, input bit last, input bit allow_stall);
        if (allow_stall && $urandom_range(0, 3) == 0) begin
            in_tvalid = 0;
            repeat ($urandom_range(1, 3)) @(posedge clk_sys);
        end
        in_tdata  = data;
        in_tlast  = last;
        in_tvalid = 1;
        @(posedge clk_sys);
        while (!in_tready) @(posedge clk_sys); // wait for DUT to accept
        in_tvalid = 0;
        in_tlast  = 0;
    endtask

    // --- Output consumer: drive out_tready for `cycles` clk_sys cycles.
    //     full_speed=1 keeps ready always high; 0 toggles it randomly (backpressure). ---
    task automatic out_consumer_run(input int cycles, input bit full_speed);
        for (int i = 0; i < cycles; i++) begin
            out_tready = full_speed ? 1 : $urandom_range(0, 1);
            @(posedge clk_sys);
        end
    endtask


    // --- Scoreboard storage ---
    logic [IN_DATA_WIDTH_M-1:0]  A [0:MATRIX_SIZE-1][0:MATRIX_SIZE-1];
    logic [IN_DATA_WIDTH_M-1:0]  B [0:MATRIX_SIZE-1][0:MATRIX_SIZE-1];
    logic [OUT_DATA_WIDTH_M-1:0] expected_C [0:MATRIX_SIZE-1][0:MATRIX_SIZE-1]; // SW reference
    logic [OUT_DATA_WIDTH_M-1:0] got_C      [0:MATRIX_SIZE-1][0:MATRIX_SIZE-1]; // captured from DUT

    logic [OUT_DATA_WIDTH-1:0] out_nibbles [0:TOTAL_OUT_NIBBLES-1]; // received output nibbles
    int out_nibble_idx;
    int total_errors  = 0;
    int total_checked = 0;

    // --- Output capture + tlast checker.
    //     On each valid handshake: store nibble, verify tlast position, advance index. ---
    always @(posedge clk_sys) begin
        if (rst_sys_n && out_tvalid && out_tready) begin
            out_nibbles[out_nibble_idx] <= out_tdata;
            if (out_nibble_idx == TOTAL_OUT_NIBBLES - 1) begin
                if (!out_tlast) begin // tlast must assert on the last nibble
                    $error("tlast did not assert on the final output nibble (idx=%0d)", out_nibble_idx);
                    total_errors++;
                end
            end else if (out_tlast) begin // tlast must NOT assert early
                $error("tlast asserted early, at nibble idx=%0d (expected idx=%0d)", out_nibble_idx, TOTAL_OUT_NIBBLES - 1);
                total_errors++;
            end
            out_nibble_idx <= (out_nibble_idx == TOTAL_OUT_NIBBLES - 1) ? 0 : out_nibble_idx + 1;
        end
    end

    // --- Run one matrix multiply: randomize A/B, compute SW reference,
    //     drive DUT in parallel with output consumer, then compare results. ---
    task automatic run_one_test(input bit stress);
        int sum;

        // Randomize A and B (full 4-bit range; overflow/truncation is expected)
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                A[i][j] = $urandom_range(0, (1 << IN_DATA_WIDTH_M) - 1);
                B[i][j] = $urandom_range(0, (1 << IN_DATA_WIDTH_M) - 1);
            end
        end

        // SW reference: C = A*B, truncated to OUT_DATA_WIDTH_M bits to match HW accumulator
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                sum = 0;
                for (int k = 0; k < MATRIX_SIZE; k++) begin
                    sum += int'(A[i][k]) * int'(B[k][j]);
                end
                expected_C[i][j] = sum[OUT_DATA_WIDTH_M-1:0];
            end
        end

        out_nibble_idx = 0; // reset capture index for this test

        fork
            // Driver: send A then B row-major; assert tlast on last B nibble
            begin
                for (int i = 0; i < MATRIX_SIZE; i++)
                    for (int j = 0; j < MATRIX_SIZE; j++)
                        send_nibble(A[i][j], 0, stress);

                for (int i = 0; i < MATRIX_SIZE; i++)
                    for (int j = 0; j < MATRIX_SIZE; j++)
                        send_nibble(B[i][j], (i == MATRIX_SIZE-1 && j == MATRIX_SIZE-1), stress);
            end

            // Consumer: drain output (full speed or random backpressure)
            begin
                if (stress)
                    out_consumer_run(400, 0);
                else
                    out_consumer_run(400, 1);
            end
        join

        repeat (50) @(posedge clk_sys); // allow last handshake to settle

        // Compare captured nibbles against SW reference, element by element
        for (int i = 0; i < MATRIX_SIZE; i++) begin
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                got_C[i][j] = out_nibbles[i * MATRIX_SIZE + j];
                total_checked++;
                if (got_C[i][j] !== expected_C[i][j]) begin
                    $error("C[%0d][%0d] mismatch: got=%0d expected=%0d", i, j, got_C[i][j], expected_C[i][j]);
                    total_errors++;
                end
            end
        end
    endtask


    // --- Main sequence ---
    initial begin
        do_reset();

        $display(" full-speed, no backpressure ");
        run_one_test(0); // baseline: no stalls, always ready

        $display(" randomized stalls + backpressure, %0d iterations ", NUM_TESTS);
        for (int t = 0; t < NUM_TESTS; t++) begin
            run_one_test(1); // stress: random input gaps + output backpressure
        end

        $display(" checked=%0d  errors=%0d", total_checked, total_errors);
        if (total_errors == 0)
            $display(" RESULT: PASS");
        else
            $display(" RESULT: FAIL");

        $finish;
    end

    // --- Safety timeout: fail if simulation doesn't finish within 500us ---
    initial begin
        #500000;
        $display(" RESULT: FAIL (timeout simulation did not complete)");
        $finish;
    end

endmodule
