`timescale 1ns / 1ps

module tb_d_ff_chain;

    // ------------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------------
    localparam int DATA_WIDTH = 4;
    localparam int DEPTH      = 3; // Tested with DEPTH = 3 delay stages
    localparam int CLK_PERIOD = 10;

    // ------------------------------------------------------------------------
    // Testbench Signals
    // ------------------------------------------------------------------------
    logic                    clk;
    logic                    rst;
    logic                    en;
    logic [DATA_WIDTH - 1:0] din;
    logic [DATA_WIDTH - 1:0] dout;

    // ------------------------------------------------------------------------
    // Instantiate DUT (Device Under Test)
    // ------------------------------------------------------------------------
    d_ff_chain #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .clk (clk),
        .rst (rst),
        .en  (en),
        .din (din),
        .dout(dout)
    );

    // ------------------------------------------------------------------------
    // Clock Generation
    // ------------------------------------------------------------------------
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ------------------------------------------------------------------------
    // Test Sequence
    // ------------------------------------------------------------------------
    initial begin
        // Initialize Signals under reset
        clk = 0;
        rst = 1;
        en  = 0;
        din = '0;

        $display("==================================================");
        $display("   Starting Testbench for d_ff_chain (DEPTH = %0d)  ", DEPTH);
        $display("==================================================");

        // 1. Reset Phase
        #(CLK_PERIOD * 2);
        
        // De-assert reset off-edge & immediately drive initial din/en
        rst = 0;
        en  = 1;
        din = 4'hA; // Ready prior to posedge clk!
        $display("[TIME %0tn] Reset Released - Driven din = 4'hA, en = 1", $time);

        // 2. Data Propagation Test (Latch 4'hA on Clock Edge 1)
        @(posedge clk);
        din = 4'hB; // Latch 4'hB on Clock Edge 2

        @(posedge clk);
        din = 4'hC; // Latch 4'hC on Clock Edge 3

        @(posedge clk); 
        // Clock Edge 3 complete (3 cycles post-reset): 4'hA reaches dout now!
        #1; // Small delta delay to evaluate updated dout
        if (dout == 4'hA) begin
            $display("[SUCCESS at %0tn] Correctly received 4'hA at output after %0d cycles!", $time, DEPTH);
        end else begin
            $error("[ERROR at %0tn] Expected 4'hA, got 4'h%0h", $time, dout);
        end

        din = 4'h0;

        @(posedge clk);
        #1;
        if (dout == 4'hB) begin
            $display("[SUCCESS at %0tn] Correctly received 4'hB at output!", $time);
        end else begin
            $error("[ERROR at %0tn] Expected 4'hB, got 4'h%0h", $time, dout);
        end

        // 3. Enable (Hold) Test
        en  = 0; // Disable DFF chain
        din = 4'hF;
        @(posedge clk);
        #1;
        if (dout == 4'hB) begin
            $display("[SUCCESS at %0tn] Enable = 0 held previous data (4'hB) correctly!", $time);
        end else begin
            $error("[ERROR at %0tn] Output changed when en=0! Got 4'h%0h", $time, dout);
        end

        #(CLK_PERIOD * 2);
        $display("==================================================");
        $display("   Testbench Complete!                            ");
        $display("==================================================");
        $finish;
    end

endmodule