`timescale 1ns / 1ps

// -----------------------------------------------------------------------
// tb_accel_buffer_top
//
// Self-checking testbench for accel_buffer_top (input_buffer + output_
// buffer + async_fifo underneath). Drives both buffering paths as if
// this TB were the DMA on one side and the systolic array on the other,
// with independent, unrelated clocks on each side of every buffer to
// genuinely stress the CDC logic.
//
// Structure:
//   - Two free-running clocks (clk_sys, clk_accel) with different,
//     non-integer-related periods.
//   - Drivers push randomized words with randomized stalls.
//   - Consumers accept with randomized backpressure (ready toggling).
//   - Monitors auto-record every successful handshake on the push side
//     into a queue, and check every successful handshake on the pop
//     side against that queue (order + value + tlast/array_last).
//   - Three phases: basic passthrough, backpressure/full stress,
//     randomized concurrent stress on both paths together.
// -----------------------------------------------------------------------

module tb_accel_buffer_top;

    // ------------------------------------------------------------
    // Parameters (match accel_buffer_top defaults)
    // ------------------------------------------------------------
    localparam int IN_DATA_WIDTH    = 8;
    localparam int IN_NUM_CHANNELS  = 8;
    localparam int IN_DEPTH         = 16;

    localparam int OUT_DATA_WIDTH   = 32;
    localparam int OUT_NUM_CHANNELS = 8;
    localparam int OUT_DEPTH        = 16;

    localparam int IN_VEC_WIDTH  = IN_DATA_WIDTH  * IN_NUM_CHANNELS;
    localparam int OUT_VEC_WIDTH = OUT_DATA_WIDTH * OUT_NUM_CHANNELS;

    // ------------------------------------------------------------
    // Clocks / resets
    // ------------------------------------------------------------
    logic clk_sys   = 0;
    logic clk_accel = 0;
    logic rst_sys_n;
    logic rst_accel_n;

    always #5.0 clk_sys   = ~clk_sys;   // 100 MHz
    always #3.5 clk_accel = ~clk_accel; // ~142 MHz, deliberately unrelated to clk_sys

    // ------------------------------------------------------------
    // DUT I/O
    // ------------------------------------------------------------
    logic [IN_VEC_WIDTH-1:0] in_tdata;
    logic                    in_tvalid;
    logic                    in_tready;
    logic                    in_tlast;

    logic [IN_NUM_CHANNELS-1:0][IN_DATA_WIDTH-1:0] in_array_data;
    logic                                          in_array_valid;
    logic                                          in_array_ready;

    logic [OUT_NUM_CHANNELS-1:0][OUT_DATA_WIDTH-1:0] out_array_data;
    logic                                             out_array_valid;
    logic                                             out_array_ready;
    logic                                             out_array_last;

    logic [OUT_VEC_WIDTH-1:0] out_tdata;
    logic                     out_tvalid;
    logic                     out_tready;
    logic                     out_tlast;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    accel_buffer_top #(
        .IN_DATA_WIDTH    (IN_DATA_WIDTH),
        .IN_NUM_CHANNELS  (IN_NUM_CHANNELS),
        .IN_DEPTH         (IN_DEPTH),
        .OUT_DATA_WIDTH   (OUT_DATA_WIDTH),
        .OUT_NUM_CHANNELS (OUT_NUM_CHANNELS),
        .OUT_DEPTH        (OUT_DEPTH)
    ) dut (
        .clk_sys         (clk_sys),
        .rst_sys_n       (rst_sys_n),
        .clk_accel       (clk_accel),
        .rst_accel_n     (rst_accel_n),

        .in_tdata        (in_tdata),
        .in_tvalid       (in_tvalid),
        .in_tready       (in_tready),
        .in_tlast        (in_tlast),

        .in_array_data   (in_array_data),
        .in_array_valid  (in_array_valid),
        .in_array_ready  (in_array_ready),

        .out_array_data  (out_array_data),
        .out_array_valid (out_array_valid),
        .out_array_ready (out_array_ready),
        .out_array_last  (out_array_last),

        .out_tdata       (out_tdata),
        .out_tvalid      (out_tvalid),
        .out_tready      (out_tready),
        .out_tlast       (out_tlast)
    );

    // ------------------------------------------------------------
    // Scoreboards
    // ------------------------------------------------------------
    logic [IN_VEC_WIDTH-1:0]  in_expect_q[$];

    logic [OUT_VEC_WIDTH-1:0] out_expect_data_q[$];
    bit                       out_expect_last_q[$];

    int in_errors    = 0;
    int in_checked   = 0;
    int out_errors   = 0;
    int out_checked  = 0;

    // Record every successful DMA-side push into the input buffer
    always @(posedge clk_sys) begin
        if (rst_sys_n && in_tvalid && in_tready) begin
            in_expect_q.push_back(in_tdata);
        end
    end

    // Check every successful pop on the array side of the input buffer
    always @(posedge clk_accel) begin
        logic [IN_VEC_WIDTH-1:0] got, exp;
        if (rst_accel_n && in_array_valid && in_array_ready) begin
            got = in_array_data;
            if (in_expect_q.size() == 0) begin
                $error("[IN ] Unexpected data on array side (queue empty): got=%0h", got);
                in_errors++;
            end else begin
                exp = in_expect_q.pop_front();
                if (got !== exp) begin
                    $error("[IN ] Mismatch: got=%0h expected=%0h", got, exp);
                    in_errors++;
                end
                in_checked++;
            end
        end
    end

    // Record every successful array-side push into the output buffer
    always @(posedge clk_accel) begin
        if (rst_accel_n && out_array_valid && out_array_ready) begin
            out_expect_data_q.push_back(out_array_data);
            out_expect_last_q.push_back(out_array_last);
        end
    end

    // Check every successful pop on the DMA side of the output buffer
    always @(posedge clk_sys) begin
        logic [OUT_VEC_WIDTH-1:0] got_data, exp_data;
        bit                       exp_last;
        if (rst_sys_n && out_tvalid && out_tready) begin
            got_data = out_tdata;
            if (out_expect_data_q.size() == 0) begin
                $error("[OUT] Unexpected data on DMA side (queue empty): got=%0h", got_data);
                out_errors++;
            end else begin
                exp_data = out_expect_data_q.pop_front();
                exp_last = out_expect_last_q.pop_front();
                if (got_data !== exp_data) begin
                    $error("[OUT] Data mismatch: got=%0h expected=%0h", got_data, exp_data);
                    out_errors++;
                end
                if (out_tlast !== exp_last) begin
                    $error("[OUT] tlast mismatch: got=%0b expected=%0b", out_tlast, exp_last);
                    out_errors++;
                end
                out_checked++;
            end
        end
    end

    // ------------------------------------------------------------
    // Reset task
    // ------------------------------------------------------------
    task automatic do_reset();
        rst_sys_n       = 0;
        rst_accel_n     = 0;
        in_tvalid       = 0;
        in_tlast        = 0;
        in_tdata        = '0;
        in_array_ready  = 0;
        out_array_valid = 0;
        out_array_last  = 0;
        out_array_data  = '0;
        out_tready      = 0;
        repeat (5) @(posedge clk_sys);
        repeat (5) @(posedge clk_accel);
        rst_sys_n   = 1;
        rst_accel_n = 1;
        repeat (3) @(posedge clk_sys);
    endtask

    // ------------------------------------------------------------
    // Input-side (DMA -> Array) driver / consumer
    // ------------------------------------------------------------
    task automatic in_drive_word(input logic [IN_VEC_WIDTH-1:0] data, input bit last, input bit allow_stall);
        if (allow_stall && $urandom_range(0, 3) == 0) begin
            in_tvalid = 0;
            repeat ($urandom_range(1, 3)) @(posedge clk_sys);
        end
        in_tdata  = data;
        in_tlast  = last;
        in_tvalid = 1;
        @(posedge clk_sys);
        while (!in_tready) @(posedge clk_sys);
        in_tvalid = 0;
        in_tlast  = 0;
    endtask

    // Toggles in_array_ready randomly; pass full_speed=1 to hold it high
    task automatic in_consumer_run(input int cycles, input bit full_speed);
        for (int i = 0; i < cycles; i++) begin
            in_array_ready = full_speed ? 1 : $urandom_range(0, 1);
            @(posedge clk_accel);
        end
    endtask

    // ------------------------------------------------------------
    // Output-side (Array -> DMA) driver / consumer
    // ------------------------------------------------------------
    task automatic out_drive_word(input logic [OUT_VEC_WIDTH-1:0] data, input bit last, input bit allow_stall);
        if (allow_stall && $urandom_range(0, 3) == 0) begin
            out_array_valid = 0;
            repeat ($urandom_range(1, 3)) @(posedge clk_accel);
        end
        out_array_data  = data;
        out_array_last  = last;
        out_array_valid = 1;
        @(posedge clk_accel);
        while (!out_array_ready) @(posedge clk_accel);
        out_array_valid = 0;
        out_array_last  = 0;
    endtask

    // Toggles out_tready randomly; pass full_speed=1 to hold it high
    task automatic out_consumer_run(input int cycles, input bit full_speed);
        for (int i = 0; i < cycles; i++) begin
            out_tready = full_speed ? 1 : $urandom_range(0, 1);
            @(posedge clk_sys);
        end
    endtask

    // ------------------------------------------------------------
    // Background free-running consumers (kept alive for the whole test;
    // individual phases override behavior by racing their own loops
    // where needed, but for simplicity each phase just calls the
    // *_consumer_run tasks in parallel with its own driver loop).
    // ------------------------------------------------------------

    // ------------------------------------------------------------
    // Main stimulus
    // ------------------------------------------------------------
    logic [IN_VEC_WIDTH-1:0]  in_word;
    logic [OUT_VEC_WIDTH-1:0] out_word;

    initial begin
        do_reset();

        // ---------------- Phase 1: basic passthrough, no backpressure ----------------
        $display("---- Phase 1: basic passthrough ----");
        fork
            begin : in_drv_p1
                for (int i = 0; i < 10; i++) begin
                    in_word = $urandom;
                    in_drive_word(in_word, (i == 9), 0);
                end
            end
            begin : in_cons_p1
                in_consumer_run(200, 1); // full speed
            end
            begin : out_drv_p1
                for (int i = 0; i < 10; i++) begin
                    out_word = {$urandom, $urandom, $urandom, $urandom,
                                $urandom, $urandom, $urandom, $urandom};
                    out_drive_word(out_word, (i == 9), 0);
                end
            end
            begin : out_cons_p1
                out_consumer_run(200, 1); // full speed
            end
        join

        repeat (20) @(posedge clk_sys);

        // ---------------- Phase 2: backpressure / fill-to-full stress ----------------
        $display("---- Phase 2: backpressure stress ----");
        fork
            begin : in_drv_p2
                for (int i = 0; i < 30; i++) begin
                    in_word = $urandom;
                    in_drive_word(in_word, (i == 29), 1); // allow driver stalls
                end
            end
            begin : in_cons_p2
                in_consumer_run(20, 0);   // hold back (mostly stalled) first...
                in_consumer_run(400, 1);  // ...then drain fast
            end
            begin : out_drv_p2
                for (int i = 0; i < 30; i++) begin
                    out_word = {$urandom, $urandom, $urandom, $urandom,
                                $urandom, $urandom, $urandom, $urandom};
                    out_drive_word(out_word, (i == 29), 1);
                end
            end
            begin : out_cons_p2
                out_consumer_run(20, 0);
                out_consumer_run(400, 1);
            end
        join

        repeat (20) @(posedge clk_sys);

        // ---------------- Phase 3: randomized concurrent stress ----------------
        $display("---- Phase 3: randomized concurrent stress ----");
        fork
            begin : in_drv_p3
                for (int i = 0; i < 60; i++) begin
                    in_word = $urandom;
                    in_drive_word(in_word, (i == 59), 1);
                end
            end
            begin : in_cons_p3
                in_consumer_run(1000, 0);
            end
            begin : out_drv_p3
                for (int i = 0; i < 60; i++) begin
                    out_word = {$urandom, $urandom, $urandom, $urandom,
                                $urandom, $urandom, $urandom, $urandom};
                    out_drive_word(out_word, (i == 59), 1);
                end
            end
            begin : out_cons_p3
                out_consumer_run(1000, 0);
            end
        join

        // Drain fully in case consumers were still stalled at end of phase 3
        fork
            in_consumer_run(200, 1);
            out_consumer_run(200, 1);
        join

        repeat (20) @(posedge clk_sys);

        // ---------------- Report ----------------
        $display("==========================================");
        $display(" IN  path: checked=%0d  errors=%0d  leftover_in_queue=%0d",
                  in_checked, in_errors, in_expect_q.size());
        $display(" OUT path: checked=%0d  errors=%0d  leftover_in_queue=%0d",
                  out_checked, out_errors, out_expect_data_q.size());
        if (in_errors == 0 && out_errors == 0 &&
            in_expect_q.size() == 0 && out_expect_data_q.size() == 0) begin
            $display(" RESULT: PASS");
        end else begin
            $display(" RESULT: FAIL");
        end
        $display("==========================================");

        $finish;
    end

    // Safety timeout in case something hangs (deadlocked handshake, etc.)
    initial begin
        #200000;
        $display(" RESULT: FAIL (timeout -- simulation did not complete)");
        $finish;
    end

endmodule
