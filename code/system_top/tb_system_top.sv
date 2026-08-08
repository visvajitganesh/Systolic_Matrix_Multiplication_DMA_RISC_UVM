`timescale 1ns / 1ps
// tb_system_top
// End-to-end self-checking testbench: BRAM -> DMA -> input_fifo -> systolic
// -> output_fifo -> DMA -> BRAM, with A and B randomized and the result
// checked against a software C = A*B reference (same truncation convention
// as tb_accel_top: PSUM_WIDTH=4 is still narrow/deferred, so the reference
// truncates to OUT_DATA_WIDTH_M bits to match the HW accumulator width).
//
// Reuses the BRAM/DMA-register AXI-Lite access tasks from dma_bram_tb.sv.

module tb_system_top;

    // --- Parameters ---
    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 32;
    localparam int STREAM_WIDTH   = 4;
    localparam int BRAM_DEPTH     = 48;

    localparam int MATRIX_SIZE      = 4;
    localparam int IN_DATA_WIDTH_M  = 4;
    localparam int IN_DEPTH         = 32;
    localparam int OUT_DATA_WIDTH_M = 4;
    localparam int OUT_DEPTH        = 16;

    localparam int CLK_SYS_PERIOD   = 10.0;  // 100 MHz
    localparam real CLK_ACCEL_PERIOD = 7.0;  // ~142.8 MHz, deliberately unrelated to clk_sys

    localparam int NUM_TESTS = 6; // randomized iterations after the baseline run

    // Register offsets
    localparam logic [31:0] ADDR_CTRL = 32'h00;
    localparam logic [31:0] ADDR_STAT = 32'h04;
    localparam logic [31:0] ADDR_SRC  = 32'h08;
    localparam logic [31:0] ADDR_DEST = 32'h0C;
    localparam logic [31:0] ADDR_LEN  = 32'h10;

    // Fixed SRC/DEST byte offsets used for every test (4 words in, 2 words out)
    localparam logic [31:0] SRC_BASE  = 32'h0000_0000;
    localparam logic [31:0] DEST_BASE = 32'h0000_0040; // clear of the 16B source region

    // --- Clocks / resets ---
    logic clk_sys   = 0;
    logic clk_accel = 0;
    logic rst_sys_n;
    logic rst_accel_n;

    always #(CLK_SYS_PERIOD/2)    clk_sys   = ~clk_sys;
    always #(CLK_ACCEL_PERIOD/2)  clk_accel = ~clk_accel;

    // --- DUT I/O ---
    logic [AXI_ADDR_WIDTH-1:0] s_dma_awaddr;
    logic                      s_dma_awvalid;
    logic                      s_dma_awready;
    logic [AXI_DATA_WIDTH-1:0] s_dma_wdata;
    logic                      s_dma_wvalid;
    logic                      s_dma_wready;
    logic [1:0]                s_dma_bresp;
    logic                      s_dma_bvalid;
    logic                      s_dma_bready;
    logic [AXI_ADDR_WIDTH-1:0] s_dma_araddr;
    logic                      s_dma_arvalid;
    logic                      s_dma_arready;
    logic [AXI_DATA_WIDTH-1:0] s_dma_rdata;
    logic [1:0]                s_dma_rresp;
    logic                      s_dma_rvalid;
    logic                      s_dma_rready;

    logic [AXI_ADDR_WIDTH-1:0]     s_bram_awaddr;
    logic                          s_bram_awvalid;
    logic                          s_bram_awready;
    logic [AXI_DATA_WIDTH-1:0]     s_bram_wdata;
    logic [(AXI_DATA_WIDTH/8)-1:0] s_bram_wstrb;
    logic                          s_bram_wvalid;
    logic                          s_bram_wready;
    logic [1:0]                    s_bram_bresp;
    logic                          s_bram_bvalid;
    logic                          s_bram_bready;
    logic [AXI_ADDR_WIDTH-1:0]     s_bram_araddr;
    logic                          s_bram_arvalid;
    logic                          s_bram_arready;
    logic [AXI_DATA_WIDTH-1:0]     s_bram_rdata;
    logic [1:0]                    s_bram_rresp;
    logic                          s_bram_rvalid;
    logic                          s_bram_rready;

    // --- DUT ---
    system_top #(
        .AXI_ADDR_WIDTH  (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH  (AXI_DATA_WIDTH),
        .STREAM_WIDTH    (STREAM_WIDTH),
        .BRAM_DEPTH      (BRAM_DEPTH),
        .MATRIX_SIZE     (MATRIX_SIZE),
        .IN_DATA_WIDTH_M (IN_DATA_WIDTH_M),
        .IN_DEPTH        (IN_DEPTH),
        .OUT_DATA_WIDTH_M(OUT_DATA_WIDTH_M),
        .OUT_DEPTH       (OUT_DEPTH)
    ) dut (
        .clk_sys     (clk_sys),
        .rst_sys_n   (rst_sys_n),
        .clk_accel   (clk_accel),
        .rst_accel_n (rst_accel_n),

        .s_dma_axi_lite_awaddr  (s_dma_awaddr),
        .s_dma_axi_lite_awvalid (s_dma_awvalid),
        .s_dma_axi_lite_awready (s_dma_awready),
        .s_dma_axi_lite_wdata   (s_dma_wdata),
        .s_dma_axi_lite_wvalid  (s_dma_wvalid),
        .s_dma_axi_lite_wready  (s_dma_wready),
        .s_dma_axi_lite_bresp   (s_dma_bresp),
        .s_dma_axi_lite_bvalid  (s_dma_bvalid),
        .s_dma_axi_lite_bready  (s_dma_bready),
        .s_dma_axi_lite_araddr  (s_dma_araddr),
        .s_dma_axi_lite_arvalid (s_dma_arvalid),
        .s_dma_axi_lite_arready (s_dma_arready),
        .s_dma_axi_lite_rdata   (s_dma_rdata),
        .s_dma_axi_lite_rresp   (s_dma_rresp),
        .s_dma_axi_lite_rvalid  (s_dma_rvalid),
        .s_dma_axi_lite_rready  (s_dma_rready),

        .s_bram_axi_lite_awaddr  (s_bram_awaddr),
        .s_bram_axi_lite_awvalid (s_bram_awvalid),
        .s_bram_axi_lite_awready (s_bram_awready),
        .s_bram_axi_lite_wdata   (s_bram_wdata),
        .s_bram_axi_lite_wstrb   (s_bram_wstrb),
        .s_bram_axi_lite_wvalid  (s_bram_wvalid),
        .s_bram_axi_lite_wready  (s_bram_wready),
        .s_bram_axi_lite_bresp   (s_bram_bresp),
        .s_bram_axi_lite_bvalid  (s_bram_bvalid),
        .s_bram_axi_lite_bready  (s_bram_bready),
        .s_bram_axi_lite_araddr  (s_bram_araddr),
        .s_bram_axi_lite_arvalid (s_bram_arvalid),
        .s_bram_axi_lite_arready (s_bram_arready),
        .s_bram_axi_lite_rdata   (s_bram_rdata),
        .s_bram_axi_lite_rresp   (s_bram_rresp),
        .s_bram_axi_lite_rvalid  (s_bram_rvalid),
        .s_bram_axi_lite_rready  (s_bram_rready)
    );


    // Tasks: BRAM Direct AXI-Lite Access (RISC port) -- same pattern as
    // dma_bram_tb.sv, timed off clk_sys.

    task automatic bram_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk_sys);
        s_bram_awaddr  <= addr;
        s_bram_awvalid <= 1'b1;
        s_bram_wdata   <= data;
        s_bram_wstrb   <= 4'b1111;
        s_bram_wvalid  <= 1'b1;
        s_bram_bready  <= 1'b1;

        fork
            begin
                wait(s_bram_awready && s_bram_awvalid);
                @(posedge clk_sys);
                s_bram_awvalid <= 1'b0;
            end
            begin
                wait(s_bram_wready && s_bram_wvalid);
                @(posedge clk_sys);
                s_bram_wvalid <= 1'b0;
            end
        join

        wait(s_bram_bvalid);
        @(posedge clk_sys);
        s_bram_bready <= 1'b0;
    endtask

    task automatic bram_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk_sys);
        s_bram_araddr  <= addr;
        s_bram_arvalid <= 1'b1;
        s_bram_rready  <= 1'b1;

        wait(s_bram_arready && s_bram_arvalid);
        @(posedge clk_sys);
        s_bram_arvalid <= 1'b0;

        wait(s_bram_rvalid);
        data = s_bram_rdata;
        @(posedge clk_sys);
        s_bram_rready <= 1'b0;
    endtask

    // Tasks: DMA Register AXI-Lite Access

    task automatic dma_reg_write(input logic [31:0] addr, input logic [31:0] data);
        @(posedge clk_sys);
        s_dma_awaddr  <= addr;
        s_dma_awvalid <= 1'b1;
        s_dma_wdata   <= data;
        s_dma_wvalid  <= 1'b1;
        s_dma_bready  <= 1'b1; // fixed typo

        wait(s_dma_awready && s_dma_wready);
        @(posedge clk_sys);
        s_dma_awvalid <= 1'b0;
        s_dma_wvalid  <= 1'b0;

        wait(s_dma_bvalid);
        @(posedge clk_sys);
        s_dma_bready <= 1'b0;
    endtask

    task automatic dma_reg_read(input logic [31:0] addr, output logic [31:0] data);
        @(posedge clk_sys);
        s_dma_araddr  <= addr;
        s_dma_arvalid <= 1'b1;
        s_dma_rready  <= 1'b1;

        wait(s_dma_arready && s_dma_arvalid);
        @(posedge clk_sys);
        s_dma_arvalid <= 1'b0;

        wait(s_dma_rvalid);
        data = s_dma_rdata;
        @(posedge clk_sys);
        s_dma_rready <= 1'b0;
    endtask


    // Matrix <-> RAM-word packing helpers.

    function automatic logic [31:0] pack_word(
        input logic [IN_DATA_WIDTH_M-1:0] e0, e1, e2, e3, e4, e5, e6, e7
    );
        pack_word = {e7, e6, e5, e4, e3, e2, e1, e0};
    endfunction

    // --- Scoreboard storage ---
    logic [IN_DATA_WIDTH_M-1:0]  A [0:MATRIX_SIZE-1][0:MATRIX_SIZE-1];
    logic [IN_DATA_WIDTH_M-1:0]  B [0:MATRIX_SIZE-1][0:MATRIX_SIZE-1];
    logic [OUT_DATA_WIDTH_M-1:0] expected_C [0:MATRIX_SIZE-1][0:MATRIX_SIZE-1];
    logic [OUT_DATA_WIDTH_M-1:0] got_C      [0:MATRIX_SIZE-1][0:MATRIX_SIZE-1];

    int total_errors  = 0;
    int total_checked = 0;

    task automatic run_one_test(input int test_num);
        int sum;
        logic [31:0] w0, w1, w2, w3;   // source words (A rows 0-1, A rows 2-3, B rows 0-1, B rows 2-3)
        logic [31:0] status_val;
        logic [31:0] rd0, rd1;         // dest words (C rows 0-1, C rows 2-3)
        int poll_iter;

        // Randomize A and B
        for (int i = 0; i < MATRIX_SIZE; i++)
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                A[i][j] = $urandom_range(0, (1 << IN_DATA_WIDTH_M) - 1);
                B[i][j] = $urandom_range(0, (1 << IN_DATA_WIDTH_M) - 1);
            end

        // Software reference: C = A*B, truncated to OUT_DATA_WIDTH_M bits
        for (int i = 0; i < MATRIX_SIZE; i++)
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                sum = 0;
                for (int k = 0; k < MATRIX_SIZE; k++)
                    sum += int'(A[i][k]) * int'(B[k][j]);
                expected_C[i][j] = sum[OUT_DATA_WIDTH_M-1:0];
            end

        $display(" [Test %0d] A          =%p", test_num, A);
        $display(" [Test %0d] B          =%p", test_num, B);

        // Pack A, B into 4 source words and write to BRAM
        w0 = pack_word(A[0][0],A[0][1],A[0][2],A[0][3], A[1][0],A[1][1],A[1][2],A[1][3]);
        w1 = pack_word(A[2][0],A[2][1],A[2][2],A[2][3], A[3][0],A[3][1],A[3][2],A[3][3]);
        w2 = pack_word(B[0][0],B[0][1],B[0][2],B[0][3], B[1][0],B[1][1],B[1][2],B[1][3]);
        w3 = pack_word(B[2][0],B[2][1],B[2][2],B[2][3], B[3][0],B[3][1],B[3][2],B[3][3]);

        bram_write(SRC_BASE + 32'h00, w0);
        bram_write(SRC_BASE + 32'h04, w1);
        bram_write(SRC_BASE + 32'h08, w2);
        bram_write(SRC_BASE + 32'h0C, w3);

        // Program and trigger the DMA
        dma_reg_write(ADDR_SRC,  SRC_BASE);
        dma_reg_write(ADDR_DEST, DEST_BASE);
        dma_reg_write(ADDR_LEN,  32'd16);   // 16 bytes read (32 nibbles = A+B)
        dma_reg_write(ADDR_CTRL, 32'h1);    // start_pulse

        // Poll status until done
        poll_iter = 0;
        do begin
            poll_iter++;
            repeat (20) @(posedge clk_sys);
            dma_reg_read(ADDR_STAT, status_val);
        end while (status_val[0] == 1'b1 || status_val[1] == 1'b0);

        if (status_val[2])
            $display(" [Test %0d] WARNING: DMA reported error bit set in status", test_num);

        // Read back C from DEST and unpack
        bram_read(DEST_BASE + 32'h00, rd0);
        bram_read(DEST_BASE + 32'h04, rd1);

        got_C[0][0] = rd0[3:0];   got_C[0][1] = rd0[7:4];
        got_C[0][2] = rd0[11:8];  got_C[0][3] = rd0[15:12];
        got_C[1][0] = rd0[19:16]; got_C[1][1] = rd0[23:20];
        got_C[1][2] = rd0[27:24]; got_C[1][3] = rd0[31:28];
        got_C[2][0] = rd1[3:0];   got_C[2][1] = rd1[7:4];
        got_C[2][2] = rd1[11:8];  got_C[2][3] = rd1[15:12];
        got_C[3][0] = rd1[19:16]; got_C[3][1] = rd1[23:20];
        got_C[3][2] = rd1[27:24]; got_C[3][3] = rd1[31:28];

        // Print Matrix C results (Hardware output vs Reference)
        $display(" [Test %0d] C (HW)     =%p", test_num, got_C);
        $display(" [Test %0d] C (Expected)=%p", test_num, expected_C);

        for (int i = 0; i < MATRIX_SIZE; i++)
            for (int j = 0; j < MATRIX_SIZE; j++) begin
                total_checked++;
                if (got_C[i][j] !== expected_C[i][j]) begin
                    $error(" [Test %0d] C[%0d][%0d] mismatch: got=%0d expected=%0d",
                           test_num, i, j, got_C[i][j], expected_C[i][j]);
                    total_errors++;
                end
            end
    endtask

    // --- Main sequence ---
    initial begin
        rst_sys_n   = 0;
        rst_accel_n = 0;
        s_dma_awaddr='0; s_dma_awvalid=0; s_dma_wdata='0; s_dma_wvalid=0;
        s_dma_bready=0;  s_dma_araddr='0; s_dma_arvalid=0; s_dma_rready=0;
        s_bram_awaddr='0; s_bram_awvalid=0; s_bram_wdata='0; s_bram_wstrb='0; s_bram_wvalid=0;
        s_bram_bready=0;  s_bram_araddr='0; s_bram_arvalid=0; s_bram_rready=0;

        repeat (5) @(posedge clk_sys);
        repeat (5) @(posedge clk_accel);
        rst_sys_n   = 1;
        rst_accel_n = 1;
        repeat (3) @(posedge clk_sys);

        for (int t = 0; t <= NUM_TESTS; t++) begin
            run_one_test(t);
        end

        $display("=======");
        $display(" checked=%0d  errors=%0d", total_checked, total_errors);
        if (total_errors == 0)
            $display(" RESULT: PASS");
        else
            $display(" RESULT: FAIL");
        $display("=======");
        $finish;
    end

    initial begin
        #2_000_000; // safety timeout
        $display(" RESULT: FAIL (timeout -- simulation did not complete)");
        $finish;
    end

endmodule
