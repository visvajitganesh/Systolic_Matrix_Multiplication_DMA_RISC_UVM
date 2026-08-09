`timescale 1ns/1ps
`include "riscv_defs.sv"

module tb_riscv_axi_lite_bridge;

    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam CLK_PERIOD = 10; // 100 MHz clock

    // DUT Signals
    logic                  clk_i;
    logic                  rst_i;

    // Core LSU Interface
    logic                  valid_mem_i;
    logic                  is_load_mem_i;
    logic                  is_store_mem_i;
    logic [ADDR_WIDTH-1:0] addr_mem_i;
    logic [DATA_WIDTH-1:0] wdata_mem_i;
    logic            [3:0] wstrb_mem_i;
    logic [DATA_WIDTH-1:0] rdata_mem_o;
    logic                  stall_o;

    // AXI4-Lite Master Interface
    logic [ADDR_WIDTH-1:0] m_axi_lite_awaddr;
    logic            [2:0] m_axi_lite_awprot;
    logic                  m_axi_lite_awvalid;
    logic                  m_axi_lite_awready;

    logic [DATA_WIDTH-1:0] m_axi_lite_wdata;
    logic            [3:0] m_axi_lite_wstrb;
    logic                  m_axi_lite_wvalid;
    logic                  m_axi_lite_wready;

    logic            [1:0] m_axi_lite_bresp;
    logic                  m_axi_lite_bvalid;
    logic                  m_axi_lite_bready;

    logic [ADDR_WIDTH-1:0] m_axi_lite_araddr;
    logic            [2:0] m_axi_lite_arprot;
    logic                  m_axi_lite_arvalid;
    logic                  m_axi_lite_arready;

    logic [DATA_WIDTH-1:0] m_axi_lite_rdata;
    logic            [1:0] m_axi_lite_rresp;
    logic                  m_axi_lite_rvalid;
    logic                  m_axi_lite_rready;

    // Test Tracking
    int pass_count = 0;
    int fail_count = 0;

    // Configurable Slave Delay Parameters
    int ar_delay = 0;
    int r_delay  = 0;
    int aw_delay = 0;
    int w_delay  = 0;
    int b_delay  = 0;

    // DUT Instantiation
    riscv_axi_lite_bridge #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
        .valid_mem_i        (valid_mem_i),
        .is_load_mem_i      (is_load_mem_i),
        .is_store_mem_i     (is_store_mem_i),
        .addr_mem_i         (addr_mem_i),
        .wdata_mem_i        (wdata_mem_i),
        .wstrb_mem_i        (wstrb_mem_i),
        .rdata_mem_o        (rdata_mem_o),
        .stall_o            (stall_o),
        .m_axi_lite_awaddr  (m_axi_lite_awaddr),
        .m_axi_lite_awprot  (m_axi_lite_awprot),
        .m_axi_lite_awvalid (m_axi_lite_awvalid),
        .m_axi_lite_awready (m_axi_lite_awready),
        .m_axi_lite_wdata   (m_axi_lite_wdata),
        .m_axi_lite_wstrb   (m_axi_lite_wstrb),
        .m_axi_lite_wvalid  (m_axi_lite_wvalid),
        .m_axi_lite_wready  (m_axi_lite_wready),
        .m_axi_lite_bresp   (m_axi_lite_bresp),
        .m_axi_lite_bvalid  (m_axi_lite_bvalid),
        .m_axi_lite_bready  (m_axi_lite_bready),
        .m_axi_lite_araddr  (m_axi_lite_araddr),
        .m_axi_lite_arprot  (m_axi_lite_arprot),
        .m_axi_lite_arvalid (m_axi_lite_arvalid),
        .m_axi_lite_arready (m_axi_lite_arready),
        .m_axi_lite_rdata   (m_axi_lite_rdata),
        .m_axi_lite_rresp   (m_axi_lite_rresp),
        .m_axi_lite_rvalid  (m_axi_lite_rvalid),
        .m_axi_lite_rready  (m_axi_lite_rready)
    );

    // Clock Generation
    always #(CLK_PERIOD/2) clk_i = ~clk_i;

    // --------------------------------------------------------
    // AXI4-Lite Slave BFM (Behavioral Memory Model)
    // --------------------------------------------------------
    logic [DATA_WIDTH-1:0] slave_mem [0:255];
    logic [ADDR_WIDTH-1:0] latched_awaddr;
    logic [DATA_WIDTH-1:0] latched_wdata;
    logic            [3:0] latched_wstrb;
    logic                  aw_handshaked, w_handshaked;

    // Initialize Memory Array
    initial begin
        foreach (slave_mem[i]) slave_mem[i] = 32'h0000_0000;
    end

    // Read Channel Responder
    initial begin
        m_axi_lite_arready = 1'b0;
        m_axi_lite_rvalid  = 1'b0;
        m_axi_lite_rdata   = '0;
        m_axi_lite_rresp   = 2'b00; // OKAY response

        forever begin
            @(posedge clk_i);
            if (rst_i) begin
                m_axi_lite_arready <= 1'b0;
                m_axi_lite_rvalid  <= 1'b0;
            end else begin
                // AR Channel
                if (m_axi_lite_arvalid && !m_axi_lite_arready) begin
                    repeat (ar_delay) @(posedge clk_i);
                    m_axi_lite_arready <= 1'b1;
                    @(posedge clk_i);
                    m_axi_lite_arready <= 1'b0;

                    // R Channel
                    repeat (r_delay) @(posedge clk_i);
                    m_axi_lite_rdata  <= slave_mem[m_axi_lite_araddr[9:2]];
                    m_axi_lite_rvalid <= 1'b1;

                    wait (m_axi_lite_rready);
                    @(posedge clk_i);
                    m_axi_lite_rvalid <= 1'b0;
                end
            end
        end
    end

    // Write Channel Responder
    initial begin
        m_axi_lite_awready = 1'b0;
        m_axi_lite_wready  = 1'b0;
        m_axi_lite_bvalid  = 1'b0;
        m_axi_lite_bresp   = 2'b00; // OKAY response
        aw_handshaked      = 1'b0;
        w_handshaked       = 1'b0;

        forever begin
            @(posedge clk_i);
            if (rst_i) begin
                m_axi_lite_awready <= 1'b0;
                m_axi_lite_wready  <= 1'b0;
                m_axi_lite_bvalid  <= 1'b0;
                aw_handshaked      <= 1'b0;
                w_handshaked       <= 1'b0;
            end else begin
                // Process AW Channel
                if (m_axi_lite_awvalid && !aw_handshaked && !m_axi_lite_awready) begin
                    fork
                        begin
                            repeat (aw_delay) @(posedge clk_i);
                            m_axi_lite_awready <= 1'b1;
                            latched_awaddr     <= m_axi_lite_awaddr;
                            @(posedge clk_i);
                            m_axi_lite_awready <= 1'b0;
                            aw_handshaked      <= 1'b1;
                        end
                    join_none
                end

                // Process W Channel
                if (m_axi_lite_wvalid && !w_handshaked && !m_axi_lite_wready) begin
                    fork
                        begin
                            repeat (w_delay) @(posedge clk_i);
                            m_axi_lite_wready <= 1'b1;
                            latched_wdata     <= m_axi_lite_wdata;
                            latched_wstrb     <= m_axi_lite_wstrb;
                            @(posedge clk_i);
                            m_axi_lite_wready <= 1'b0;
                            w_handshaked      <= 1'b1;
                        end
                    join_none
                end

                // Perform memory write once both AW and W arrive
                if ((aw_handshaked || (m_axi_lite_awvalid && m_axi_lite_awready)) &&
                    (w_handshaked  || (m_axi_lite_wvalid  && m_axi_lite_wready))) begin
                    
                    // Byte-strobe write application
                    if (latched_wstrb[0]) slave_mem[latched_awaddr[9:2]][7:0]   <= latched_wdata[7:0];
                    if (latched_wstrb[1]) slave_mem[latched_awaddr[9:2]][15:8]  <= latched_wdata[15:8];
                    if (latched_wstrb[2]) slave_mem[latched_awaddr[9:2]][23:16] <= latched_wdata[23:16];
                    if (latched_wstrb[3]) slave_mem[latched_awaddr[9:2]][31:24] <= latched_wdata[31:24];

                    // B Channel Response
                    repeat (b_delay) @(posedge clk_i);
                    m_axi_lite_bvalid <= 1'b1;

                    wait (m_axi_lite_bready);
                    @(posedge clk_i);
                    m_axi_lite_bvalid <= 1'b0;
                    aw_handshaked     <= 1'b0;
                    w_handshaked      <= 1'b0;
                end
            end
        end
    end

    // --------------------------------------------------------
    // Helper Tasks for LSU Stimulus
    // --------------------------------------------------------
    task automatic do_read(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] exp_data,
        input string           test_name
    );
        @(negedge clk_i);
        valid_mem_i   = 1'b1;
        is_load_mem_i = 1'b1;
        addr_mem_i    = addr;

        @(posedge clk_i);
        #1;
        // Hold LSU request until bridge transitions or deasserts stall
        valid_mem_i   = 1'b0;
        is_load_mem_i = 1'b0;

        // Wait for transaction completion
        wait (!stall_o);
        #1;

        if (rdata_mem_o === exp_data) begin
            $display("[PASS] %-40s | Addr: 0x%08h | Data: 0x%08h", test_name, addr, rdata_mem_o);
            pass_count++;
        end else begin
            $display("** Error: [FAIL] %-33s | Addr: 0x%08h | Exp: 0x%08h Got: 0x%08h", 
                     test_name, addr, exp_data, rdata_mem_o);
            fail_count++;
        end
    endtask

    task automatic do_write(
        input [ADDR_WIDTH-1:0] addr,
        input [DATA_WIDTH-1:0] data,
        input            [3:0] strb,
        input string           test_name
    );
        @(negedge clk_i);
        valid_mem_i    = 1'b1;
        is_store_mem_i = 1'b1;
        addr_mem_i     = addr;
        wdata_mem_i    = data;
        wstrb_mem_i    = strb;

        @(posedge clk_i);
        #1;
        valid_mem_i    = 1'b0;
        is_store_mem_i = 1'b0;

        // Wait for AXI Write Response completion
        wait (!stall_o);
        #1;

        $display("[PASS] %-40s | Addr: 0x%08h | WData: 0x%08h | Strobe: 4'b%04b", 
                 test_name, addr, data, strb);
        pass_count++;
    endtask

    // --------------------------------------------------------
    // Main Stimulus Procedure
    // --------------------------------------------------------
    initial begin
        // Signal Initialization
        clk_i          = 0;
        rst_i          = 1;
        valid_mem_i    = 0;
        is_load_mem_i  = 0;
        is_store_mem_i = 0;
        addr_mem_i     = 0;
        wdata_mem_i    = 0;
        wstrb_mem_i    = 0;

        // Pre-populate Slave Memory
        slave_mem[0] = 32'hDEAD_BEEF;
        slave_mem[1] = 32'h1234_5678;
        slave_mem[2] = 32'hA5A5_5A5A;

        $display("==========================================================");
        $display("      STARTING RISC-V AXI-LITE BRIDGE TESTBENCH           ");
        $display("==========================================================");

        // Reset Pulse
        repeat (3) @(posedge clk_i);
        rst_i = 0;
        @(posedge clk_i);

        // --------------------------------------------------------
        // Test 1: Zero-Wait-State Read Transaction
        // --------------------------------------------------------
        ar_delay = 0; r_delay = 0;
        do_read(32'h0000_0000, 32'hDEAD_BEEF, "Zero-Wait Read (Word 0)");

        // --------------------------------------------------------
        // Test 2: Zero-Wait-State Write Transaction
        // --------------------------------------------------------
        aw_delay = 0; w_delay = 0; b_delay = 0;
        do_write(32'h0000_000C, 32'hCAFE_F00D, 4'b1111, "Zero-Wait Write (Word 3)");
        do_read(32'h0000_000C, 32'hCAFE_F00D, "Readback Written Data (Word 3)");

        // --------------------------------------------------------
        // Test 3: Read Transaction with Slave Delays (Backpressure)
        // --------------------------------------------------------
        ar_delay = 2; r_delay = 3;
        do_read(32'h0000_0004, 32'h1234_5678, "Delayed Slave Read (Word 1)");

        // --------------------------------------------------------
        // Test 4: Write with Staggered Handshakes (AW Before W)
        // --------------------------------------------------------
        aw_delay = 0; w_delay = 3; b_delay = 1;
        do_write(32'h0000_0010, 32'h8877_6655, 4'b1111, "Staggered Write (AW ready before W)");
        ar_delay = 0; r_delay = 0;
        do_read(32'h0000_0010, 32'h8877_6655, "Readback Staggered Write (Word 4)");

        // --------------------------------------------------------
        // Test 5: Write with Staggered Handshakes (W Before AW)
        // --------------------------------------------------------
        aw_delay = 3; w_delay = 0; b_delay = 1;
        do_write(32'h0000_0014, 32'h1122_3344, 4'b1111, "Staggered Write (W ready before AW)");
        do_read(32'h0000_0014, 32'h1122_3344, "Readback Staggered Write (Word 5)");

        // --------------------------------------------------------
        // Test 6: Byte Strobe Masking Write Test
        // --------------------------------------------------------
        aw_delay = 0; w_delay = 0; b_delay = 0;
        // Write byte to word 2 (0x08)
        do_write(32'h0000_0008, 32'h0000_00FF, 4'b0001, "Byte Strobe Write (Lower Byte)");
        do_read(32'h0000_0008, 32'hA5A5_5AFF, "Readback Byte-Masked Data (Word 2)");

        // --------------------------------------------------------
        // Test Summary
        // --------------------------------------------------------
        $display("==========================================================");
        $display("   TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==========================================================");

        if (fail_count == 0)
            $display(" >>> ALL AXI-LITE BRIDGE TESTS PASSED <<<");
        else
            $display(" >>> SOME BRIDGE TESTS FAILED - CHECK TRANSCRIPT <<<");

        $finish;
    end

endmodule