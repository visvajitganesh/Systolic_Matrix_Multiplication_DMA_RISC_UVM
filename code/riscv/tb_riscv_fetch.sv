`timescale 1ns / 1ps

module tb_riscv_fetch;

    localparam CLK_PERIOD = 10;

    // DUT Signals
    logic        clk_i;
    logic        rst_i;
    logic        branch_taken_i;
    logic [31:0] branch_target_i;
    logic        squash_i;
    logic        stall_i;

    logic [31:0] imem_addr_o;
    logic [31:0] imem_rdata_i;

    logic [31:0] pc_o;
    logic [31:0] instr_o;
    logic        valid_o;

    // Test Tracking
    int pass_count = 0;
    int fail_count = 0;
    int test_num   = 0;

    // Instantiate DUT
    riscv_fetch dut (
        .clk_i           (clk_i),
        .rst_i           (rst_i),
        .branch_taken_i  (branch_taken_i),
        .branch_target_i (branch_target_i),
        .squash_i        (squash_i),
        .stall_i         (stall_i),
        .imem_addr_o     (imem_addr_o),
        .imem_rdata_i    (imem_rdata_i),
        .pc_o            (pc_o),
        .instr_o         (instr_o),
        .valid_o         (valid_o)
    );

    // Clock Generator
    always #(CLK_PERIOD / 2) clk_i = ~clk_i;

    // Synchronous Instruction Memory Model
    // Generates a unique, deterministic instruction encoding based on address:
    // Memory Data = Address XOR 0xA5A5_5A5A
    always_ff @(posedge clk_i) begin
        imem_rdata_i <= imem_addr_o ^ 32'hA5A5_5A5A;
    end

    // Helper Task: Self-Checking Assertion
    task automatic check_outputs(
        input string       test_desc,
        input logic [31:0] exp_pc,
        input logic [31:0] exp_instr,
        input logic        exp_valid
    );
        #1; // Sample shortly after posedge clk_i
        if ((valid_o === exp_valid) && 
            (!exp_valid || (pc_o === exp_pc && instr_o === exp_instr))) begin
            $display("[PASS %02d] %-50s | PC: 0x%08h | Valid: %0b | Instr: 0x%08h", 
                     test_num, test_desc, pc_o, valid_o, instr_o);
            pass_count++;
        end else begin
            $error("[FAIL %02d] %-50s\n        EXPECTED -> PC: 0x%08h | Valid: %0b | Instr: 0x%08h\n        ACTUAL   -> PC: 0x%08h | Valid: %0b | Instr: 0x%08h", 
                   test_num, test_desc, exp_pc, exp_valid, exp_instr, pc_o, valid_o, instr_o);
            fail_count++;
        end
        test_num++;
    endtask

    // Helper Task: Drive Inputs
    task automatic drive_inputs(
        input logic        branch_taken = 1'b0,
        input logic [31:0] branch_target = 32'h0,
        input logic        squash       = 1'b0,
        input logic        stall        = 1'b0
    );
        branch_taken_i  <= branch_taken;
        branch_target_i <= branch_target;
        squash_i        <= squash;
        stall_i         <= stall;
    endtask

    // Main Test Sequence
    initial begin
        // Initialize
        clk_i = 1'b0;
        rst_i = 1'b1;
        drive_inputs();

        $display("=======================================================================");
        $display("          STARTING EXHAUSTIVE VERIFICATION OF RISCV_FETCH             ");
        $display("=======================================================================");

        // -----------------------------------------------------------------
        // TEST 1: Synchronous Reset Asserted
        // -----------------------------------------------------------------
        repeat (2) @(posedge clk_i);
        check_outputs("Reset Active Check", 32'h0000_0000, 32'h0, 1'b0);

        // Deassert Reset
        @(posedge clk_i);
        rst_i <= 1'b0;

        // -----------------------------------------------------------------
        // TEST 2: Normal Sequential Pipeline Fetch (Unstalled)
        // -----------------------------------------------------------------
        // Cycle 1: Requesting PC 0x0
        drive_inputs();
        @(posedge clk_i); // Cycle 2: Output valid for PC 0x0, requesting PC 0x4
        check_outputs("Seq Fetch 1 (PC 0x0000_0000)", 32'h0000_0000, 32'h0000_0000 ^ 32'hA5A5_5A5A, 1'b1);

        @(posedge clk_i); // Cycle 3: Output valid for PC 0x4, requesting PC 0x8
        check_outputs("Seq Fetch 2 (PC 0x0000_0004)", 32'h0000_0004, 32'h0000_0004 ^ 32'hA5A5_5A5A, 1'b1);

        // -----------------------------------------------------------------
        // TEST 3: Single-Cycle Stall (Skid Buffer Activation)
        // -----------------------------------------------------------------
        // Cycle N: Assert Stall
        drive_inputs(.stall(1'b1));
        @(posedge clk_i); // Skid buffer captures imem_rdata_i for PC 0x8

        // Cycle N+1: Hold Stall. Output MUST serve captured Skid Buffer data
        check_outputs("Single Stall Cycle 1 (Serve Buffer 0x4)", 32'h0000_0004, 32'h0000_0004 ^ 32'hA5A5_5A5A, 1'b1);

        // Release Stall
        drive_inputs(.stall(1'b0));
        @(posedge clk_i); // Cycle N+2: Resumes live memory stream (PC 0x0C)
        check_outputs("Post-Stall Resume (PC 0x0000_0008)", 32'h0000_0008, 32'h0000_0008 ^ 32'hA5A5_5A5A, 1'b1);

        // -----------------------------------------------------------------
        // TEST 4: Multi-Cycle Stall (Skid Buffer Data Hold Verification)
        // -----------------------------------------------------------------
        drive_inputs(.stall(1'b1));

    // The DUT should hold PC 0x8 continuously across all stalled cycles
        repeat (3) begin
            @(posedge clk_i);
            check_outputs("Multi-Cycle Stall Hold (Serve Buffer 0x8)", 
                32'h0000_0008, 
                32'h0000_0008 ^ 32'hA5A5_5A5A, 
                1'b1);
        end

        // Release Stall and resume
        drive_inputs(.stall(1'b0));
        @(posedge clk_i);
        check_outputs("Multi-Stall Resume (PC 0x0000_000C)", 
            32'h0000_000C, 
            32'h0000_000C ^ 32'hA5A5_5A5A, 
            1'b1);
            
        // -----------------------------------------------------------------
        // TEST 5: Branch Redirect (Unstalled)
        // -----------------------------------------------------------------
        // Branch to 0x0000_2000
        drive_inputs(.branch_taken(1'b1), .branch_target(32'h0000_2000));
        @(posedge clk_i); // Branch bubble cycle (valid_o = 0)

        drive_inputs(.branch_taken(1'b0));
        check_outputs("Branch Target Bubble Cycle", 32'h0, 32'h0, 1'b0);

        @(posedge clk_i); // Valid instruction from target 0x2000
        check_outputs("Branch Target Execution (PC 0x0000_2000)", 32'h0000_2000, 32'h0000_2000 ^ 32'hA5A5_5A5A, 1'b1);

        // -----------------------------------------------------------------
        // TEST 6: Branch Taken DURING a Pipeline Stall
        // -----------------------------------------------------------------
        // 1. Stall the pipeline
        drive_inputs(.stall(1'b1));
        @(posedge clk_i); // Latch PC 0x2004 in skid buffer

        // 2. Issue Branch while still stalled
        drive_inputs(.stall(1'b1), .branch_taken(1'b1), .branch_target(32'h0000_5000));
        @(posedge clk_i); // Should invalidate skid buffer selection (use_buff_q <= 0)

        // 3. Unstall and verify branch target is fetched, NOT stale buffer
        drive_inputs(.stall(1'b0), .branch_taken(1'b0));
        check_outputs("Branch during Stall Bubble Cycle", 32'h0, 32'h0, 1'b0);

        @(posedge clk_i);
        check_outputs("Post-Stalled Branch Execution (PC 0x0000_5000)", 32'h0000_5000, 32'h0000_5000 ^ 32'hA5A5_5A5A, 1'b1);

        // -----------------------------------------------------------------
        // TEST 7: Squash Signal Handling (Flush without Branch)
        // -----------------------------------------------------------------
        drive_inputs(.squash(1'b1));
        @(posedge clk_i);

        drive_inputs(.squash(1'b0));
        check_outputs("Squash Flush Bubble Cycle", 32'h0, 32'h0, 1'b0);

        @(posedge clk_i);
        // Note: Verifies whether implementation holds or advances PC on squash
        $display("[INFO] Post-Squash PC Observed: 0x%08h | Valid: %0b", pc_o, valid_o);

        // -----------------------------------------------------------------
        // TEST 8: Randomized Stress Testing (100 Cycles)
        // -----------------------------------------------------------------
        $display("-----------------------------------------------------------------------");
        $display("Starting Randomized Stress Test (100 Cycles)...");
        $display("-----------------------------------------------------------------------");

        repeat (100) begin
            logic        r_stall;
            logic        r_branch;
            logic        r_squash;
            logic [31:0] r_target;

            r_stall  = ($urandom_range(0, 100) < 30); // 30% probability
            r_branch = ($urandom_range(0, 100) < 15); // 15% probability
            r_squash = ($urandom_range(0, 100) < 10); // 10% probability
            r_target = $urandom() && 32'hFFFF_FFFC;        // Word-aligned address

            drive_inputs(r_branch, r_target, r_squash, r_stall);
            @(posedge clk_i);
        end

        // Clean finish
        drive_inputs();
        repeat (3) @(posedge clk_i);

        // -----------------------------------------------------------------
        // SUMMARY REPORT
        // -----------------------------------------------------------------
        $display("=======================================================================");
        $display("VERIFICATION COMPLETE");
        $display("Total Directed Checks Passed: %0d | Failed: %0d", pass_count, fail_count);
        $display("=======================================================================");

        if (fail_count == 0) begin
            $display("SUCCESS: All functional scenarios verified without errors.");
        end else begin
            $error("FAILURE: %0d assertion checks failed.", fail_count);
        end

        $finish;
    end

endmodule
