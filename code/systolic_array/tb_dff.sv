`timescale 1ns / 1ps

module tb_dff;

    // ------------------------------------------------------------------------
    // Parameters & Signals
    // ------------------------------------------------------------------------
    localparam int DATA_WIDTH = 4;
    localparam int CLK_PERIOD = 10;

    logic                    clk;
    logic                    rst;
    logic                    en;
    logic [DATA_WIDTH - 1:0] din;
    logic [DATA_WIDTH - 1:0] dout;

    // ------------------------------------------------------------------------
    // Instantiate DUT
    // ------------------------------------------------------------------------
    dff #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk (clk),
        .rst (rst),
        .en  (en),
        .din (din),
        .dout(dout)
    );

    // Clock Generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ------------------------------------------------------------------------
    // Test Stimulus
    // ------------------------------------------------------------------------
    initial begin
        // Initialize Signals
        clk = 0;
        rst = 1;
        en  = 0;
        din = '0;

        $display("==========================================");
        $display("          Starting dff Testbench          ");
        $display("==========================================");

        // 1. Reset Test
        #(CLK_PERIOD);
        if (dout == 4'h0) 
            $display("[SUCCESS] Async Reset holding output at 0.");
        else 
            $error("[ERROR] Reset failed! dout = %h", dout);

        // Release reset
        rst = 0;
        @(posedge clk);

        // 2. Enable Write Test
        en  = 1;
        din = 4'hA;
        @(posedge clk);
        #1; // Small delta delay to allow non-blocking assignment to update
        if (dout == 4'hA)
            $display("[SUCCESS] Latched 4'hA when en = 1.");
        else
            $error("[ERROR] Failed to latch data when enabled! dout = %h", dout);

        // 3. Hold Test (en = 0)
        en  = 0;
        din = 4'hF; // Drive new value on din
        @(posedge clk);
        #1;
        if (dout == 4'hA)
            $display("[SUCCESS] Successfully held previous value (4'hA) when en = 0.");
        else
            $error("[ERROR] Output changed while en = 0! dout = %h", dout);

        // 4. Asynchronous Reset Test during active hold
        #3;
        rst = 1; // Trigger reset off-clock-edge
        #1;
        if (dout == 4'h0)
            $display("[SUCCESS] Async Reset cleared output immediately.");
        else
            $error("[ERROR] Async Reset failed! dout = %h", dout);

        #(CLK_PERIOD);
        $display("==========================================");
        $display("           Testbench Finished             ");
        $display("==========================================");
        $finish;
    end

endmodule