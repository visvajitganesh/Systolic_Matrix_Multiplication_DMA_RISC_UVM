// =============================================================================
// tb_dma_bram_sys.sv
// Testbench for Integrated DMA + BRAM System
// =============================================================================

`timescale 1ns / 1ps

module tb_dma_bram_sys;

    // Parameters
    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 32;
    localparam int STREAM_WIDTH   = 4;
    localparam int BRAM_DEPTH     = 48;
    localparam int CLK_PERIOD     = 10; // 100 MHz

    // Register Offsets
    localparam logic [31:0] ADDR_CTRL = 32'h00;
    localparam logic [31:0] ADDR_STAT = 32'h04;
    localparam logic [31:0] ADDR_SRC  = 32'h08;
    localparam logic [31:0] ADDR_DEST = 32'h0C;
    localparam logic [31:0] ADDR_LEN  = 32'h10;

    // DUT Signals
    logic clk;
    logic rst_n;

    // DMA AXI-Lite
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

    // BRAM AXI-Lite (RISC Port)
    logic [AXI_ADDR_WIDTH-1:0] s_bram_awaddr;
    logic                      s_bram_awvalid;
    logic                      s_bram_awready;
    logic [AXI_DATA_WIDTH-1:0] s_bram_wdata;
    logic [(AXI_DATA_WIDTH/8)-1:0] s_bram_wstrb;
    logic                      s_bram_wvalid;
    logic                      s_bram_wready;
    logic [1:0]                s_bram_bresp;
    logic                      s_bram_bvalid;
    logic                      s_bram_bready;
    logic [AXI_ADDR_WIDTH-1:0] s_bram_araddr;
    logic                      s_bram_arvalid;
    logic                      s_bram_arready;
    logic [AXI_DATA_WIDTH-1:0] s_bram_rdata;
    logic [1:0]                s_bram_rresp;
    logic                      s_bram_rvalid;
    logic                      s_bram_rready;

    // AXI Streams
    logic [STREAM_WIDTH-1:0]   m_axis_mm2s_tdata;
    logic                      m_axis_mm2s_tvalid;
    logic                      m_axis_mm2s_tready;
    logic [STREAM_WIDTH-1:0]   s_axis_s2mm_tdata;
    logic                      s_axis_s2mm_tvalid;
    logic                      s_axis_s2mm_tready;

    // -------------------------------------------------------------------------
    // Behavioral accelerator model: consumes MM2S nibbles independently of
    // producing S2MM nibbles (decoupled via an internal buffer), and reduces
    // 32 input nibbles -> 16 output nibbles (pairwise sum, mod 16).
    //
    // WHY NOT A SIMPLE COMBINATIONAL "+1" LOOPBACK (the original bug):
    // dma.sv's write engine derives its transfer length as reg_xfer_len/2
    // (see reg_wr_xfer_len in dma_bram.sv) - it assumes whatever sits
    // between MM2S and S2MM reduces data volume exactly 2:1, matching the
    // real systolic array (32 input elements -> 16 output elements for this
    // project's fixed 4x4x4-bit geometry). A 1:1 passthrough loopback sends
    // twice as many nibbles as the write engine expects; the write engine
    // finishes and stops asserting tready after only 16 nibbles, which
    // permanently stalls the read engine waiting to send its remaining 16
    // nibbles (mm2s_tready was tied directly to s_axis_s2mm_tready) - a
    // deadlock. This decoupled model buffers a full 32-nibble "read" before
    // producing exactly 16 output nibbles, matching the DMA's contract and
    // giving deterministic, checkable output values.
    // -------------------------------------------------------------------------
    localparam int RX_TOTAL = 32; // nibbles per MM2S transfer (2 x 4x4 x 4-bit)
    localparam int TX_TOTAL = 16; // nibbles per S2MM transfer (1 x 4x4 x 4-bit)

    logic [3:0] acc_rx_buf [0:RX_TOTAL-1];
    logic [3:0] acc_tx_buf [0:TX_TOTAL-1];
    logic [5:0] acc_rx_cnt;
    logic [4:0] acc_tx_cnt;
    logic       acc_tx_active;
    int         acc_i;
    logic [3:0] acc_elem_lo, acc_elem_hi; // scratch operands for the pairwise-sum bugfix below

    assign m_axis_mm2s_tready = 1'b1; // always able to accept (buffered accelerator)
    assign s_axis_s2mm_tvalid = acc_tx_active;
    assign s_axis_s2mm_tdata  = acc_tx_buf[acc_tx_cnt];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_rx_cnt    <= '0;
            acc_tx_cnt    <= '0;
            acc_tx_active <= 1'b0;
        end else begin
            // Receive side: capture every nibble MM2S sends
            if (m_axis_mm2s_tvalid && m_axis_mm2s_tready) begin
                acc_rx_buf[acc_rx_cnt] <= m_axis_mm2s_tdata;
                $display("   [%0t] ACCEL RX nibble %0d/%0d = %h", $time, acc_rx_cnt, RX_TOTAL-1, m_axis_mm2s_tdata);

                if (acc_rx_cnt == RX_TOTAL-1) begin
                    acc_rx_cnt <= '0;
                    // Full 32-nibble input collected: compute 16 reduced
                    // output nibbles (pairwise sum, mod 16) and start
                    // transmitting them on S2MM.
                    //
                    // BUGFIX: acc_rx_buf[RX_TOTAL-1] is written with a
                    // nonblocking assignment on THIS same clock edge (line
                    // above), so it is not yet visible to reads in this same
                    // always_ff block - the for loop below would otherwise
                    // read the stale/uninitialized (X) value for that one
                    // element instead of the nibble that just arrived on
                    // m_axis_mm2s_tdata. Bypass the array for that specific
                    // index and use the live streaming data directly.
                    for (acc_i = 0; acc_i < TX_TOTAL; acc_i++) begin
                        acc_elem_lo = (2*acc_i   == RX_TOTAL-1) ? m_axis_mm2s_tdata : acc_rx_buf[2*acc_i];
                        acc_elem_hi = (2*acc_i+1 == RX_TOTAL-1) ? m_axis_mm2s_tdata : acc_rx_buf[2*acc_i+1];
                        acc_tx_buf[acc_i] <= acc_elem_lo + acc_elem_hi;
                    end
                    acc_tx_cnt    <= '0;
                    acc_tx_active <= 1'b1;
                    $display("   [%0t] ACCEL RX complete: all %0d input nibbles collected -> computing %0d output nibbles (pairwise sum)", $time, RX_TOTAL, TX_TOTAL);
                end else begin
                    acc_rx_cnt <= acc_rx_cnt + 1'b1;
                end
            end

            // Transmit side: stream the 16 reduced nibbles to S2MM
            if (acc_tx_active && s_axis_s2mm_tvalid && s_axis_s2mm_tready) begin
                $display("   [%0t] ACCEL TX nibble %0d/%0d = %h", $time, acc_tx_cnt, TX_TOTAL-1, acc_tx_buf[acc_tx_cnt]);
                if (acc_tx_cnt == TX_TOTAL-1) begin
                    acc_tx_active <= 1'b0;
                    $display("   [%0t] ACCEL TX complete: all %0d output nibbles sent to S2MM", $time, TX_TOTAL);
                end else begin
                    acc_tx_cnt <= acc_tx_cnt + 1'b1;
                end
            end
        end
    end

    // Instantiate System
    dma_bram #(
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .STREAM_WIDTH  (STREAM_WIDTH),
        .BRAM_DEPTH    (BRAM_DEPTH)
    ) dut (
        .clk                    (clk),
        .rst_n                  (rst_n),

        // DMA AXI-Lite
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

        // BRAM AXI-Lite
        .s_bram_axi_lite_awaddr (s_bram_awaddr),
        .s_bram_axi_lite_awvalid(s_bram_awvalid),
        .s_bram_axi_lite_awready(s_bram_awready),
        .s_bram_axi_lite_wdata  (s_bram_wdata),
        .s_bram_axi_lite_wstrb  (s_bram_wstrb),
        .s_bram_axi_lite_wvalid (s_bram_wvalid),
        .s_bram_axi_lite_wready (s_bram_wready),
        .s_bram_axi_lite_bresp  (s_bram_bresp),
        .s_bram_axi_lite_bvalid (s_bram_bvalid),
        .s_bram_axi_lite_bready (s_bram_bready),
        .s_bram_axi_lite_araddr (s_bram_araddr),
        .s_bram_axi_lite_arvalid(s_bram_arvalid),
        .s_bram_axi_lite_arready(s_bram_arready),
        .s_bram_axi_lite_rdata  (s_bram_rdata),
        .s_bram_axi_lite_rresp  (s_bram_rresp),
        .s_bram_axi_lite_rvalid (s_bram_rvalid),
        .s_bram_axi_lite_rready (s_bram_rready),

        // Stream ports
        .m_axis_mm2s_tdata     (m_axis_mm2s_tdata),
        .m_axis_mm2s_tvalid    (m_axis_mm2s_tvalid),
        .m_axis_mm2s_tready    (m_axis_mm2s_tready),
        .s_axis_s2mm_tdata     (s_axis_s2mm_tdata),
        .s_axis_s2mm_tvalid    (s_axis_s2mm_tvalid),
        .s_axis_s2mm_tready    (s_axis_s2mm_tready)
    );

    // Clock Generation
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Tasks: BRAM Direct AXI-Lite Access
    // -------------------------------------------------------------------------
    task automatic bram_write(input logic [31:0] addr, input logic [31:0] data);
        $display("   [%0t] BRAM  AW/W  : issuing write  addr=0x%08h data=0x%08h wstrb=0xF", $time, addr, data);
        @(posedge clk);
        s_bram_awaddr  <= addr;
        s_bram_awvalid <= 1'b1;
        s_bram_wdata   <= data;
        s_bram_wstrb   <= 4'b1111;
        s_bram_wvalid  <= 1'b1;
        s_bram_bready  <= 1'b1;

        fork
            begin
                wait(s_bram_awready && s_bram_awvalid);
                $display("   [%0t] BRAM  AW    : address handshake complete (AWREADY seen)", $time);
                @(posedge clk);
                s_bram_awvalid <= 1'b0;
            end
            begin
                wait(s_bram_wready && s_bram_wvalid);
                $display("   [%0t] BRAM  W     : data handshake complete (WREADY seen)", $time);
                @(posedge clk);
                s_bram_wvalid  <= 1'b0;
            end
        join

        wait(s_bram_bvalid);
        $display("   [%0t] BRAM  B     : write response received (BRESP=0x%0h, OKAY) -> write to 0x%08h complete", $time, s_bram_bresp, addr);
        @(posedge clk);
        s_bram_bready <= 1'b0;
    endtask

    task automatic bram_read(input logic [31:0] addr, output logic [31:0] data);
        $display("   [%0t] BRAM  AR    : issuing read   addr=0x%08h", $time, addr);
        @(posedge clk);
        s_bram_araddr  <= addr;
        s_bram_arvalid <= 1'b1;
        s_bram_rready  <= 1'b1;

        wait(s_bram_arready && s_bram_arvalid);
        $display("   [%0t] BRAM  AR    : address handshake complete (ARREADY seen)", $time);
        @(posedge clk);
        s_bram_arvalid <= 1'b0;

        wait(s_bram_rvalid);
        data = s_bram_rdata;
        $display("   [%0t] BRAM  R     : read data received (RRESP=0x%0h, OKAY) data=0x%08h from 0x%08h", $time, s_bram_rresp, data, addr);
        @(posedge clk);
        s_bram_rready <= 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Tasks: DMA Register AXI-Lite Access
    // -------------------------------------------------------------------------
    // Human-readable name for each DMA register offset, for clearer logging
    function automatic string dma_reg_name(input logic [31:0] addr);
        case (addr)
            ADDR_CTRL: dma_reg_name = "CTRL";
            ADDR_STAT: dma_reg_name = "STAT";
            ADDR_SRC:  dma_reg_name = "SRC";
            ADDR_DEST: dma_reg_name = "DEST";
            ADDR_LEN:  dma_reg_name = "LEN";
            default:   dma_reg_name = "UNKNOWN";
        endcase
    endfunction

    task automatic dma_reg_write(input logic [31:0] addr, input logic [31:0] data);
        $display("   [%0t] DMA-REG AW/W: issuing write  %-4s (addr=0x%02h) data=0x%08h",
                 $time, dma_reg_name(addr), addr, data);
        @(posedge clk);
        s_dma_awaddr  <= addr;
        s_dma_awvalid <= 1'b1;
        s_dma_wdata   <= data;
        s_dma_wvalid  <= 1'b1;
        s_dma_bready  <= 1'b1;

        wait(s_dma_awready && s_dma_wready);
        $display("   [%0t] DMA-REG AW/W: address+data handshake complete", $time);
        @(posedge clk);
        s_dma_awvalid <= 1'b0;
        s_dma_wvalid  <= 1'b0;

        wait(s_dma_bvalid);
        $display("   [%0t] DMA-REG B   : write response received (BRESP=0x%0h, OKAY) -> %-4s write complete",
                 $time, s_dma_bresp, dma_reg_name(addr));
        @(posedge clk);
        s_dma_bready <= 1'b0;
    endtask

    task automatic dma_reg_read(input logic [31:0] addr, output logic [31:0] data);
        $display("   [%0t] DMA-REG AR  : issuing read   %-4s (addr=0x%02h)", $time, dma_reg_name(addr), addr);
        @(posedge clk);
        s_dma_araddr  <= addr;
        s_dma_arvalid <= 1'b1;
        s_dma_rready  <= 1'b1;

        wait(s_dma_arready && s_dma_arvalid);
        $display("   [%0t] DMA-REG AR  : address handshake complete (ARREADY seen)", $time);
        @(posedge clk);
        s_dma_arvalid <= 1'b0;

        wait(s_dma_rvalid);
        data = s_dma_rdata;
        $display("   [%0t] DMA-REG R   : read data received (RRESP=0x%0h, OKAY) -> %-4s = 0x%08h",
                 $time, s_dma_rresp, dma_reg_name(addr), data);
        @(posedge clk);
        s_dma_rready <= 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    logic [31:0] read_val;
    logic [31:0] status_val;
    int error_count = 0;

    // Safety net: if anything stalls (e.g. a future edit reintroduces a
    // handshake deadlock), fail loudly instead of hanging the simulation
    // forever.
    initial begin
        #(CLK_PERIOD * 2000);
        $display("\n[ERROR] Testbench TIMEOUT - simulation did not complete in time.");
        $display("        Check for a stalled AXI handshake (deadlock).");
        $finish;
    end

    initial begin
        // Initialize Signals
        clk = 0;
        rst_n = 0;

        s_dma_awaddr  = '0; s_dma_awvalid = 0; s_dma_wdata  = '0; s_dma_wvalid = 0;
        s_dma_bready  = 0;  s_dma_araddr  = '0; s_dma_arvalid = 0; s_dma_rready = 0;

        s_bram_awaddr = '0; s_bram_awvalid = 0; s_bram_wdata = '0; s_bram_wstrb = '0; s_bram_wvalid = 0;
        s_bram_bready = 0;  s_bram_araddr = '0; s_bram_arvalid = 0; s_bram_rready = 0;

        $display("=======================================================");
        $display(" 0. Testbench Configuration                            ");
        $display("=======================================================");
        $display("   AXI_ADDR_WIDTH = %0d, AXI_DATA_WIDTH = %0d, STREAM_WIDTH = %0d",
                  AXI_ADDR_WIDTH, AXI_DATA_WIDTH, STREAM_WIDTH);
        $display("   BRAM_DEPTH     = %0d words, CLK_PERIOD = %0d ns", BRAM_DEPTH, CLK_PERIOD);
        $display("   Accelerator model: %0d input nibbles -> %0d output nibbles (pairwise sum, mod 16)",
                  RX_TOTAL, TX_TOTAL);

        $display("\n[%0t] Applying reset (rst_n = 0)...", $time);
        // Reset Sequence
        #(CLK_PERIOD * 5);
        rst_n = 1;
        $display("[%0t] Releasing reset (rst_n = 1)", $time);
        #(CLK_PERIOD * 5);
        $display("[%0t] Reset settled, beginning test sequence", $time);

        $display("\n=======================================================");
        $display(" 1. Initializing Source Memory Locations via BRAM Port ");
        $display("=======================================================");
        // Write 4 test words into source address range (0x00 to 0x0F)
        $display(" -- Word 1 of 4 --");
        bram_write(32'h0000_0000, 32'h1111_1111);
        $display(" -- Word 2 of 4 --");
        bram_write(32'h0000_0004, 32'h2222_2222);
        $display(" -- Word 3 of 4 --");
        bram_write(32'h0000_0008, 32'h3333_3333);
        $display(" -- Word 4 of 4 --");
        bram_write(32'h0000_000C, 32'h4444_4444);
        $display(" -- All 4 source words written successfully --");

        $display("\n=======================================================");
        $display(" 2. Programming DMA via DMA Control Registers          ");
        $display("=======================================================");
        $display(" -- Setting source address --");
        dma_reg_write(ADDR_SRC,  32'h0000_0000); // Src Offset = 0x00
        $display(" -- Setting destination address --");
        dma_reg_write(ADDR_DEST, 32'h0000_0020); // Dest Offset = 0x20
        $display(" -- Setting transfer length (bytes to read from SRC) --");
        dma_reg_write(ADDR_LEN,  32'h0000_0010); // 16 bytes = 4 words
        $display(" -- DMA configured: SRC=0x00000000  DEST=0x00000020  LEN=16 bytes (4 words / 32 nibbles) --");

        $display("\n -- Triggering DMA Start (CTRL[0] = 1) --");
        dma_reg_write(ADDR_CTRL, 32'h0000_0001); // Set CTRL[0] = 1
        $display(" -- Start pulse issued: MM2S read engine and S2MM write engine should now be active --");

        $display("\n=======================================================");
        $display(" 3. Polling DMA Status Register                        ");
        $display("=======================================================");
        begin
            int poll_iter;
            poll_iter = 0;
            do begin
                poll_iter++;
                #(CLK_PERIOD * 10);
                $display(" -- Poll #%0d --", poll_iter);
                dma_reg_read(ADDR_STAT, status_val);
                $display("   DMA Status: 0x%08h (Busy=%b, Done=%b, Error=%b)%s",
                         status_val, status_val[0], status_val[1], status_val[2],
                         (status_val[1] && !status_val[0]) ? "  -> transfer complete" :
                         (status_val[0] ? "  -> still busy, continuing to poll" : ""));
            end while (status_val[0] == 1'b1 || status_val[1] == 1'b0);
            $display(" -- DMA reports Done after %0d poll iteration(s) (%0d ns since start trigger) --",
                      poll_iter, poll_iter * CLK_PERIOD * 10);
        end

        $display("\n=======================================================");
        $display(" 4. Verifying Destination Memory (0x20, 0x24)          ");
        $display("=======================================================");
        // The accelerator model reduces 32 input nibbles -> 16 output
        // nibbles (pairwise sum, mod 16), matching dma.sv's built-in
        // assumption that write length = read length / 2. Source words
        // were 0x11111111/0x22222222/0x33333333/0x44444444 (repeating
        // digits), so every pairwise sum within a source word is constant:
        //   word1 nibbles (all 1) -> sum=2 (x4)
        //   word2 nibbles (all 2) -> sum=4 (x4)
        //   word3 nibbles (all 3) -> sum=6 (x4)
        //   word4 nibbles (all 4) -> sum=8 (x4)
        // Packed LSB-nibble-first into two 32-bit beats:
        //   beat0 (addr 0x20) = 0x44442222
        //   beat1 (addr 0x24) = 0x88886666
        // Only 2 words are written in total (matches the fixed 8-byte
        // write length) - 0x28/0x2C are never touched by this transfer.
        $display(" -- Checking beat 0 (address 0x20) --");
        bram_read(32'h0000_0020, read_val);
        $display("Read @ 0x20: Actual = 0x%08h, Expected = 0x44442222  [%s]",
                 read_val, (read_val === 32'h4444_2222) ? "PASS" : "FAIL");
        if (read_val !== 32'h4444_2222) error_count++;

        $display(" -- Checking beat 1 (address 0x24) --");
        bram_read(32'h0000_0024, read_val);
        $display("Read @ 0x24: Actual = 0x%08h, Expected = 0x88886666  [%s]",
                 read_val, (read_val === 32'h8888_6666) ? "PASS" : "FAIL");
        if (read_val !== 32'h8888_6666) error_count++;

        $display("\n=======================================================");
        $display(" 5. Test Summary                                       ");
        $display("=======================================================");
        $display("   Checks performed : 2");
        $display("   Checks passed    : %0d", 2 - error_count);
        $display("   Checks failed    : %0d", error_count);
        $display("   Simulation time  : %0t", $time);
        $display("=======================================================");
        if (error_count == 0) begin
            $display("  TEST PASSED SUCCESSFULLY!");
        end else begin
            $display("  TEST FAILED WITH %0d ERRORS!", error_count);
        end
        $display("=======================================================\n");

        $finish;
    end

endmodule