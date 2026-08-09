`timescale 1ns / 1ps
`include "riscv_defs.sv"

module tb_riscv_core;

    // Clock and Reset Signals
    logic clk_i;
    logic rst_i;

    // AXI4-Lite Master Signals from Core
    logic [31:0] m_axi_lite_awaddr;
    logic  [2:0] m_axi_lite_awprot;
    logic        m_axi_lite_awvalid;
    logic        m_axi_lite_awready;

    logic [31:0] m_axi_lite_wdata;
    logic  [3:0] m_axi_lite_wstrb;
    logic        m_axi_lite_wvalid;
    logic        m_axi_lite_wready;

    logic  [1:0] m_axi_lite_bresp;
    logic        m_axi_lite_bvalid;
    logic        m_axi_lite_bready;

    logic [31:0] m_axi_lite_araddr;
    logic  [2:0] m_axi_lite_arprot;
    logic        m_axi_lite_arvalid;
    logic        m_axi_lite_arready;

    logic [31:0] m_axi_lite_rdata;
    logic  [1:0] m_axi_lite_rresp;
    logic        m_axi_lite_rvalid;
    logic        m_axi_lite_rready;

    // Diagnostic Counters
    integer axi_write_count = 0;
    integer axi_read_count  = 0;

    // Instantiate DUT (Device Under Test)
    riscv_core #(
        .DMEM_BASE(32'h0000_0000),
        .DMEM_SIZE(32'h0000_1000) // 4KB Local DMEM
    ) u_dut (
        .clk_i              (clk_i),
        .rst_i              (rst_i),
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

    // 100 MHz Clock Generation (10 ns Period)
    always #5 clk_i = ~clk_i;

    // Task to write program & data memory files dynamically
    task automatic generate_hex_files();
        int f_code, f_data;
        f_code = $fopen("code.hex", "w");
        f_data = $fopen("data.hex", "w");

        if (f_code && f_data) begin
            // Sample RISC-V Assembly Sequence:
            // 1. lui  x1, 0x00002     -> x1 = 0x00002000 (AXI address range)
            // 2. li   x2, 0xDEADBEEF  -> x2 = 0xDEADBEEF
            // 3. sw   x2, 0(x1)       -> AXI Write transaction to 0x00002000
            // 4. lw   x3, 0(x1)       -> AXI Read transaction from 0x00002000
            // 5. nop / stall loop
            $fdisplay(f_code, "000020b7"); // lui  x1, 0x2
            $fdisplay(f_code, "deadc137"); // lui  x2, 0xDEAD0
            $fdisplay(f_code, "eef10113"); // addi x2, x2, -273 (x2 = 0xDEADBEEF)
            $fdisplay(f_code, "0020a023"); // sw   x2, 0(x1)  <- Triggers AXI Write
            $fdisplay(f_code, "0000a183"); // lw   x3, 0(x1)  <- Triggers AXI Read
            $fdisplay(f_code, "00000013"); // nop
            $fdisplay(f_code, "00000013"); // nop
            $fdisplay(f_code, "00000013"); // nop
            $fclose(f_code);

            // Populate initial DMEM data
            $fdisplay(f_data, "12345678");
            $fdisplay(f_data, "87654321");
            $fclose(f_data);

            $display("[TB] Generated default 'code.hex' and 'data.hex' files.");
        end else begin
            $display("[TB ERROR] Failed to create hex files!");
            $finish;
        end
    endtask

    // Simple AXI-Lite Slave Responder Model
    initial begin
        m_axi_lite_awready = 1'b0;
        m_axi_lite_wready  = 1'b0;
        m_axi_lite_bvalid  = 1'b0;
        m_axi_lite_bresp   = 2'b00; // OKAY

        m_axi_lite_arready = 1'b0;
        m_axi_lite_rvalid  = 1'b0;
        m_axi_lite_rdata   = 32'h0;
        m_axi_lite_rresp   = 2'b00; // OKAY

        forever begin
            @(posedge clk_i);
            
            // AXI Write Handling
            if (m_axi_lite_awvalid && m_axi_lite_wvalid && !m_axi_lite_bvalid) begin
                m_axi_lite_awready <= 1'b1;
                m_axi_lite_wready  <= 1'b1;
                @(posedge clk_i);
                m_axi_lite_awready <= 1'b0;
                m_axi_lite_wready  <= 1'b0;
                
                m_axi_lite_bvalid  <= 1'b1;
                axi_write_count++;
                $display("[TB AXI WRITE] Addr: 0x%08h | Data: 0x%08h | Strobe: 0x%01h @ Time: %0t", 
                         m_axi_lite_awaddr, m_axi_lite_wdata, m_axi_lite_wstrb, $time);
            end

            if (m_axi_lite_bvalid && m_axi_lite_bready) begin
                m_axi_lite_bvalid <= 1'b0;
            end

            // AXI Read Handling
            if (m_axi_lite_arvalid && !m_axi_lite_rvalid) begin
                m_axi_lite_arready <= 1'b1;
                @(posedge clk_i);
                m_axi_lite_arready <= 1'b0;

                m_axi_lite_rvalid  <= 1'b1;
                m_axi_lite_rdata   <= 32'hCAFEBABE; // Dummy read data response
                axi_read_count++;
                $display("[TB AXI READ]  Addr: 0x%08h | Data: 0x%08h @ Time: %0t", 
                         m_axi_lite_araddr, 32'hCAFEBABE, $time);
            end

            if (m_axi_lite_rvalid && m_axi_lite_rready) begin
                m_axi_lite_rvalid <= 1'b0;
            end
        end
    end

    // Main Test Execution Flow
    initial begin
        clk_i = 1'b0;
        rst_i = 1'b1;

        $display("==========================================================");
        $display("               STARTING RISC-V CORE TESTBENCH             ");
        $display("==========================================================");

        // 1. Generate local memory hex files
        generate_hex_files();

        // 2. Force load generated files directly into internal memories
        $readmemh("code.hex", u_dut.u_imem.mem);
        $readmemh("data.hex", u_dut.u_dmem.mem);
        $display("[TB] Re-loaded hex files into IMEM and DMEM memory arrays.");

        // 3. Reset pulse
        #20;
        rst_i = 1'b0;
        $display("[TB] Reset De-asserted. Core execution started.");

        // 4. Run simulation for set time
        #1000;

        // 5. Display Summary
        $display("==========================================================");
        $display("                  TEST SUMMARY & RESULTS                  ");
        $display("==========================================================");
        $display(" Total AXI Writes Captured : %0d", axi_write_count);
        $display(" Total AXI Reads Captured  : %0d", axi_read_count);
        
        if (axi_write_count > 0 && axi_read_count > 0) begin
            $display(" [RESULT] PASSED: AXI Transactions were successfully executed!");
        end else begin
            $display(" [RESULT] WARNING: Check instruction execution or pipeline stall logic.");
        end
        $display("==========================================================");

        $finish;
    end

endmodule