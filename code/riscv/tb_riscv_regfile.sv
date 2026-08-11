`timescale 1ns/1ps

module tb_riscv_regfile;

    parameter DATA_WIDTH = 32;
    parameter CLK_PERIOD = 10;

    // DUT Signals
    logic                  clk_i;
    logic                  rst_i;
    logic [4:0]            rd0_i;
    logic [DATA_WIDTH-1:0] rd0_value_i;
    logic                  rd0_wren_i;
    logic [4:0]            ra0_i;
    logic [4:0]            rb0_i;
    wire  [DATA_WIDTH-1:0] ra0_value_o;
    wire  [DATA_WIDTH-1:0] rb0_value_o;

    int error_count = 0;

    // Instantiate Design Under Test
    riscv_regfile #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk_i      (clk_i),
        .rst_i      (rst_i),
        .rd0_i      (rd0_i),
        .rd0_value_i(rd0_value_i),
        .rd0_wren_i (rd0_wren_i),
        .ra0_i      (ra0_i),
        .rb0_i      (rb0_i),
        .ra0_value_o(ra0_value_o),
        .rb0_value_o(rb0_value_o)
    );

    // Clock Generation
    initial begin
        clk_i = 0;
        forever #(CLK_PERIOD/2) clk_i = ~clk_i;
    end

    // Test Procedure
    initial begin
        // Initialize Signals
        rst_i       = 0;
        rd0_i       = '0;
        rd0_value_i = '0;
        rd0_wren_i  = 0;
        ra0_i       = '0;
        rb0_i       = '0;

        $display("=== STARTING REGFILE TESTBENCH ===");

        //---------------------------------------------------------------------
        // TEST 1: Asynchronous Reset Check
        // Checks if all registers clear to zero on reset
        //---------------------------------------------------------------------
        $display("\n[TEST 1] Testing Asynchronous Reset...");
        rst_i = 1;
        #15;
        rst_i = 0;
        @(negedge clk_i);
        
        for (int i = 0; i < 32; i++) begin
            ra0_i = i[4:0];
            #1; // Allow propagation time for async read
            if (ra0_value_o !== '0) begin
                $error("[FAIL Test 1] Reg x%0d not zero after reset! Got: 0x%h", i, ra0_value_o);
                error_count++;
            end
        end

        //---------------------------------------------------------------------
        // TEST 2: Register x0 Immutability (Write to x0)
        // Verifies writing to x0 does not change its hardwired '0 value
        //---------------------------------------------------------------------
        $display("\n[TEST 2] Testing x0 Immutability (Attempting Write to x0)...");
        @(posedge clk_i);
        rd0_i       = 5'd0;
        rd0_value_i = 32'hDEADBEEF;
        rd0_wren_i  = 1'b1;

        @(posedge clk_i);
        rd0_wren_i  = 1'b0;
        ra0_i       = 5'd0;
        rb0_i       = 5'd0;
        #1;

        if (ra0_value_o !== 32'h0 || rb0_value_o !== 32'h0) begin
            $error("[FAIL Test 2] Register x0 was modified! ra0_value_o=0x%h, rb0_value_o=0x%h", 
                   ra0_value_o, rb0_value_o);
            error_count++;
        end

        //---------------------------------------------------------------------
        // TEST 3: Read-During-Write (RAW Hazard & Delta Cycle Timing)
        // Checks behavior when simultaneously reading and writing the same address
        //---------------------------------------------------------------------
        $display("\n[TEST 3] Testing Read-During-Write (RAW) Hazard on x5...");
        // Pre-load x5 with 0x11111111
        @(posedge clk_i);
        rd0_i       = 5'd5;
        rd0_value_i = 32'h11111111;
        rd0_wren_i  = 1'b1;
        
        @(posedge clk_i);
        // Write new value 0x99999999 while reading x5
        rd0_i       = 5'd5;
        rd0_value_i = 32'h99999999;
        rd0_wren_i  = 1'b1;
        ra0_i       = 5'd5;

        // Exact posedge check exposes non-blocking assignment (NBA) delay
        @(posedge clk_i);
        if (ra0_value_o == 32'h11111111) begin
            $warning("[RACE CONDITION] Exact clock edge sample captures OLD value (0x11111111) before NBA update.");
        end
        
        #1; // Post clock edge evaluation
        if (ra0_value_o !== 32'h99999999) begin
            $error("[FAIL Test 3] Async read failed to reflect write data! Expected: 0x99999999, Got: 0x%h", 
                   ra0_value_o);
            error_count++;
        end
        rd0_wren_i = 1'b0;

        //---------------------------------------------------------------------
        // TEST 4: Full Sweep Write and Asynchronous Dual Read
        //---------------------------------------------------------------------
        $display("\n[TEST 4] Sequential write and dual port read verification...");
        for (int i = 1; i < 32; i++) begin
            @(posedge clk_i);
            rd0_i       = i[4:0];
            rd0_value_i = 32'hA5A50000 | i;
            rd0_wren_i  = 1'b1;
        end
        
        @(posedge clk_i);
        rd0_wren_i = 1'b0;

        // Check dual read capability concurrently
        for (int i = 1; i < 32; i += 2) begin
            ra0_i = i[4:0];
            rb0_i = (i < 31) ? (i[4:0] + 1'b1) : 5'd0;
            #1;
            
            if (ra0_value_o !== (32'hA5A50000 | i)) begin
                $error("[FAIL Test 4] Port A mismatch at x%0d: Expected 0x%h, Got 0x%h", 
                       i, (32'hA5A50000 | i), ra0_value_o);
                error_count++;
            end
            
            if (i < 31 && rb0_value_o !== (32'hA5A50000 | (i + 1))) begin
                $error("[FAIL Test 4] Port B mismatch at x%0d: Expected 0x%h, Got 0x%h", 
                       i+1, (32'hA5A50000 | (i + 1)), rb0_value_o);
                error_count++;
            end
        end

        //---------------------------------------------------------------------
        // TEST 5: Write Enable (wren = 0) Protection Check
        //---------------------------------------------------------------------
        $display("\n[TEST 5] Verifying write protection when rd0_wren_i = 0...");
        @(posedge clk_i);
        rd0_i       = 5'd10;
        rd0_value_i = 32'hFFFFFFFF;
        rd0_wren_i  = 1'b0; // Disabled

        @(posedge clk_i);
        ra0_i = 5'd10;
        #1;
        if (ra0_value_o == 32'hFFFFFFFF) begin
            $error("[FAIL Test 5] Register x10 was modified while write enable was LOW!", ra0_value_o);
            error_count++;
        end

        // Final Status
        $display("\n==================================================");
        if (error_count == 0)
            $display("TESTBENCH COMPLETED: All functional checks passed.");
        else
            $display("TESTBENCH FAILED: Detected %0d error(s).", error_count);
        $display("==================================================");

        $finish;
    end

endmodule
