/////////////////

`timescale 1ns/1ps

module tb_processing_element;

    // 1. Declare signals to connect to the PE
    logic         clk;
    logic         rst;
    logic         weight_en;
    logic         pe_en;
    logic         mul_en;
    logic         adder_en;
    
    // Inputs to DUT
    logic [3:0]   in;
    logic [3:0]   weight;
    logic [15:0]  psum;
    
    // Outputs from DUT (FIXED TO MATCH DUT)
    logic [3:0]   row_out;
    logic [15:0]  pe_output;

    // 2. Instantiate the Device Under Test (DUT)
    processing_element #(
        .DATA_WIDTH(4),
        .PSUM_WIDTH(16)
    ) dut (
        .clk(clk),
        .rst(rst),
        .weight_en(weight_en),
        .pe_en(pe_en),
        .mul_en(mul_en),
        .adder_en(adder_en),   // Hooked up the unused pin
        .in(in),
        .weight(weight),
        .psum(psum),
        .row_out(row_out),     // FIXED port mapping
        .pe_output(pe_output)  // FIXED port mapping
    );

    // 3. Generate a Clock (10ns period -> 100MHz)
    always #5 clk = ~clk;

    // 4. Test Sequence (The Stimulus)
    initial begin
        // --- Initialization ---
        clk       = 0; 
        rst       = 1; 
        weight_en = 0; 
        pe_en     = 0; 
        mul_en    = 0;
        adder_en  = 0;
        in        = 0; 
        weight    = 0; 
        psum      = 0;

        // Wait a bit, then release reset
        #15;
        rst = 0;

        // -----------------------------------------------------
        // TEST PHASE 1: Load the Weight
        // -----------------------------------------------------
        $display("\n--- PHASE 1: Loading Weight ---");
        #10;
        weight_en = 1;
        weight    = 4'd3; // We are locking the number '3' into the weight register
        #10;
        weight_en = 0;    // De-assert to lock it in

        // -----------------------------------------------------
        // TEST PHASE 2: Perform MAC operations
        // Math formula inside PE: pe_output = psum + (in * weight)
        // -----------------------------------------------------
        $display("\n--- PHASE 2: MAC Computation ---");
        
        // Cycle 1: Let's try 10 + (4 * 3). Expecting 22.
        pe_en  = 1;
        mul_en = 1;
        in     = 4'd4;
        psum   = 16'd10;
        #10; // Wait 1 clock cycle
        
        // Cycle 2: Let's try 5 + (2 * 3). Expecting 11.
        in     = 4'd2; 
        psum   = 16'd5;
        #10; // Wait 1 clock cycle
        
        // Turn off enable signals
        pe_en  = 0;
        mul_en = 0;
        in     = 0;
        psum   = 0;

        // Let the pipeline drain and end simulation
        #30;
        $display("\n--- Simulation Complete ---");
        $finish;
    end

    // 5. Monitor: Automatically print results to the console when values change
    // FIXED variables inside $monitor to match new names
    initial begin
        $monitor("Time: %0t | in: %2d | weight: %2d | psum_in: %2d || row_out: %2d | pe_output: %2d", 
                 $time, in, weight, psum, row_out, pe_output);
    end

endmodule
