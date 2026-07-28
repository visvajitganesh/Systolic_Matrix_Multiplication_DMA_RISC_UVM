`timescale 1ns / 1ps

module tb_d_ff_chain_multi;

    localparam int DATA_WIDTH = 4;
    localparam int CLK_PERIOD = 10;

    logic                    clk;
    logic                    rst;
    logic                    en;
    logic [DATA_WIDTH - 1:0] din;

    // Output signals for different depth instances
    logic [DATA_WIDTH - 1:0] dout_d0;
    logic [DATA_WIDTH - 1:0] dout_d1;
    logic [DATA_WIDTH - 1:0] dout_d5;

    // ------------------------------------------------------------------------
    // Instantiate DUTs for Depth 0, 1, and 5
    // ------------------------------------------------------------------------
    d_ff_chain #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(0)) dut_d0 (
        .clk(clk), .rst(rst), .en(en), .din(din), .dout(dout_d0)
    );

    d_ff_chain #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(1)) dut_d1 (
        .clk(clk), .rst(rst), .en(en), .din(din), .dout(dout_d1)
    );

    d_ff_chain #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(5)) dut_d5 (
        .clk(clk), .rst(rst), .en(en), .din(din), .dout(dout_d5)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ------------------------------------------------------------------------
    // Test Sequence
    // ------------------------------------------------------------------------
    initial begin
        // 1. Initialize
        clk = 0;
        rst = 1;
        en  = 0;
        din = 4'h0;

        $display("==================================================");
        $display("   Testing d_ff_chain with DEPTH = 0, 1, and 5   ");
        $display("==================================================");

        #(CLK_PERIOD * 2);
        rst = 0;
        en  = 1;
        
        // --------------------------------------------------------------------
        // TEST 1: DEPTH = 0 (Direct Wire Pass-through)
        // --------------------------------------------------------------------
        din = 4'h7;
        #1; // Combinational delay check
        if (dout_d0 == 4'h7) begin
            $display("[SUCCESS] DEPTH = 0 correctly acts as direct wire (dout = 4'h7 immediately)");
        end else begin
            $error("[ERROR] DEPTH = 0 failed! Expected 4'h7, got %h", dout_d0);
        end

        // --------------------------------------------------------------------
        // TEST 2: DEPTH = 1 (Single Flip-Flop Delay)
        // --------------------------------------------------------------------
        din = 4'hA;
        @(posedge clk);
        #1;
        if (dout_d1 == 4'hA) begin
            $display("[SUCCESS] DEPTH = 1 received 4'hA after 1 clock cycle");
        end else begin
            $error("[ERROR] DEPTH = 1 failed! Expected 4'hA, got %h", dout_d1);
        end

        // --------------------------------------------------------------------
        // TEST 3: DEPTH = 5 (5-Stage Pipeline Chain)
        // --------------------------------------------------------------------
        $display("\n--- Testing DEPTH = 5 Pipeline ---");
        din = 4'hE; // Cycle 1
        @(posedge clk);
        
        din = 4'hC;
        
        // Wait 4 more clock cycles (Total = 5 cycles)
        repeat (4) @(posedge clk);
        #1;

        if (dout_d5 == 4'hE) begin
            $display("[SUCCESS] DEPTH = 5 received 4'hE after exactly 5 clock cycles!");
        end else begin
            $error("[ERROR] DEPTH = 5 failed! Expected 4'hE, got %h", dout_d5);
        end

        // --------------------------------------------------------------------
        // TEST 4: Hold State Verification on DEPTH = 5
        // --------------------------------------------------------------------
        din = 4'h3;
        @(posedge clk);
        #1;
        en = 0; // Freeze pipeline (holds current state)
        din = 4'hF;

        @(posedge clk);
        #1;
        if (dout_d5 == 4'hC) begin
            $display("[SUCCESS] DEPTH = 5 held state (4'hC) correctly when en = 0");
        end else begin
            $error("[ERROR] Hold state failed on DEPTH = 5! Got %h", dout_d5);
        end

        #(CLK_PERIOD * 2);
        $display("==================================================");
        $display("          Multi-Depth Tests Complete!             ");
        $display("==================================================");
        $finish;
    end

endmodule