`timescale 1ns/1ps

module tb_riscv_lsu;

    // -------------------------------------------------------------------------
    // Clock & Interface Signals
    // -------------------------------------------------------------------------
    logic        clk_i = 0; // Initialized at declaration to avoid simulation glitches
    logic        rst_i;
    logic        stall_i;

    logic        valid_mem_i;
    logic        is_load_mem_i;
    logic        is_store_mem_i;
    logic [31:0] addr_mem_i;
    logic [31:0] store_data_mem_i;
    logic [1:0]  mem_size_mem_i;
    logic        mem_unsigned_mem_i;

    logic [31:0] dmem_addr_o;
    logic [31:0] dmem_wdata_o;
    logic [3:0]  dmem_wstrb_o;
    logic [31:0] dmem_rdata_i;

    logic [31:0] mem_rdata_o;

    // Track pass/fail statistics
    int tests_passed = 0;
    int tests_failed = 0;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    riscv_lsu dut (
        .clk_i               (clk_i),
        .rst_i               (rst_i),
        .stall_i             (stall_i),
        .valid_mem_i         (valid_mem_i),
        .is_load_mem_i        (is_load_mem_i),
        .is_store_mem_i       (is_store_mem_i),
        .addr_mem_i          (addr_mem_i),
        .store_data_mem_i    (store_data_mem_i),
        .mem_size_mem_i      (mem_size_mem_i),
        .mem_unsigned_mem_i  (mem_unsigned_mem_i),
        .dmem_addr_o         (dmem_addr_o),
        .dmem_wdata_o        (dmem_wdata_o),
        .dmem_wstrb_o        (dmem_wstrb_o),
        .dmem_rdata_i        (dmem_rdata_i),
        .mem_rdata_o         (mem_rdata_o)
    );

    // -------------------------------------------------------------------------
    // Clock Generation (10ns Period)
    // -------------------------------------------------------------------------
    always #5 clk_i = ~clk_i;

    // -------------------------------------------------------------------------
    // Verification Helper Tasks
    // -------------------------------------------------------------------------
    task automatic reset_dut();
        rst_i              = 1;
        stall_i            = 0;
        valid_mem_i        = 0;
        is_load_mem_i       = 0;
        is_store_mem_i      = 0;
        addr_mem_i         = '0;
        store_data_mem_i   = '0;
        mem_size_mem_i     = '0;
        mem_unsigned_mem_i = 0;
        dmem_rdata_i       = '0;
        repeat (2) @(posedge clk_i);
        rst_i              = 0;
        @(posedge clk_i);
    endtask

    // Check Immediate Store Request Outputs (Combinational)
    task automatic check_store_req(
        input string tc_name,
        input [3:0]  exp_wstrb,
        input [31:0] exp_wdata
    );
        #1; // Allow combinational logic to settle
        if (dmem_wstrb_o !== exp_wstrb || dmem_wdata_o !== exp_wdata) begin
            $error("[FAIL] %s | Expected wstrb=%b wdata=0x%h | Got wstrb=%b wdata=0x%h",
                   tc_name, exp_wstrb, exp_wdata, dmem_wstrb_o, dmem_wdata_o);
            tests_failed++;
        end else begin
            $display("[PASS] %s", tc_name);
            tests_passed++;
        end
    endtask

    // Check Load Response Output (Registered - Sampled on Next Cycle)
    task automatic check_load_resp(
        input string tc_name,
        input [31:0] exp_rdata
    );
        #1;
        if (mem_rdata_o !== exp_rdata) begin
            $error("[FAIL] %s | Expected mem_rdata_o=0x%h | Got 0x%h",
                   tc_name, exp_rdata, mem_rdata_o);
            tests_failed++;
        end else begin
            $display("[PASS] %s", tc_name);
            tests_passed++;
        end
    endtask

    // Expected Value Helper for Golden Model
    function automatic [31:0] get_expected_load(
        input [31:0] rdata,
        input [1:0]  addr_lsb,
        input [1:0]  size,
        input        is_unsigned
    );
        logic [7:0]  b;
        logic [15:0] h;
        case (addr_lsb)
            2'b00: b = rdata[7:0];
            2'b01: b = rdata[15:8];
            2'b10: b = rdata[23:16];
            2'b11: b = rdata[31:24];
        endcase
        h = addr_lsb[1] ? rdata[31:16] : rdata[15:0];

        case (size)
            2'b00: return is_unsigned ? {24'b0, b} : {{24{b[7]}}, b};
            2'b01: return is_unsigned ? {16'b0, h} : {{16{h[15]}}, h};
            2'b10: return rdata;
            default: return rdata;
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Test Sequences
    // -------------------------------------------------------------------------
    initial begin
        $display("=======================================================================");
        $display("STARTING RIGOROUS VERIFICATION OF RISCV_LSU");
        $display("=======================================================================");

        reset_dut();

        // ---------------------------------------------------------------------
        // TEST 1: Store Word, Halfword, and Byte Offsets
        // ---------------------------------------------------------------------
        $display("\n--- TEST 1: Store Operations & Alignment ---");
        
        valid_mem_i = 1; is_store_mem_i = 1; mem_size_mem_i = 2'b00; addr_mem_i = 32'h1000; store_data_mem_i = 32'h12345678;
        check_store_req("SB @ Offset 0", 4'b0001, 32'h78787878);

        addr_mem_i = 32'h1001;
        check_store_req("SB @ Offset 1", 4'b0010, 32'h78787878);

        addr_mem_i = 32'h1002;
        check_store_req("SB @ Offset 2", 4'b0100, 32'h78787878);

        addr_mem_i = 32'h1003;
        check_store_req("SB @ Offset 3", 4'b1000, 32'h78787878);

        mem_size_mem_i = 2'b01; addr_mem_i = 32'h1000;
        check_store_req("SH @ Offset 0", 4'b0011, 32'h56785678);

        addr_mem_i = 32'h1002;
        check_store_req("SH @ Offset 2", 4'b1100, 32'h56785678);

        mem_size_mem_i = 2'b10; addr_mem_i = 32'h1000;
        check_store_req("SW @ Offset 0", 4'b1111, 32'h12345678);

        valid_mem_i = 0; is_store_mem_i = 0;
        @(posedge clk_i);

        // ---------------------------------------------------------------------
        // TEST 2: Load Operations (Sign Extension vs Zero Extension)
        // ---------------------------------------------------------------------
        $display("\n--- TEST 2: Load Operations & Extension ---");

        // 1. LB (Signed) @ Offset 2
        valid_mem_i = 1; is_load_mem_i = 1; mem_size_mem_i = 2'b00; mem_unsigned_mem_i = 0; addr_mem_i = 32'h2002;
        dmem_rdata_i = 32'h00800000; // Byte 2 is 0x80 (-128)
        @(posedge clk_i);
        check_load_resp("LB (Signed Negative) @ Offset 2", 32'hFFFFFF80);

        // 2. LBU (Unsigned) @ Offset 2
        mem_unsigned_mem_i = 1;
        dmem_rdata_i = 32'h00800000;
        @(posedge clk_i);
        check_load_resp("LBU (Unsigned) @ Offset 2", 32'h00000080);

        // 3. LH (Signed) @ Offset 2
        mem_size_mem_i = 2'b01; mem_unsigned_mem_i = 0; addr_mem_i = 32'h2002;
        dmem_rdata_i = 32'h9ABC0000;
        @(posedge clk_i);
        check_load_resp("LH (Signed Negative) @ Offset 2", 32'hFFFF9ABC);

        // 4. LHU (Unsigned) @ Offset 2
        mem_unsigned_mem_i = 1;
        dmem_rdata_i = 32'h9ABC0000;
        @(posedge clk_i);
        check_load_resp("LHU (Unsigned) @ Offset 2", 32'h00009ABC);

        // Clear Load Inputs
        valid_mem_i = 0; is_load_mem_i = 0;
        @(posedge clk_i);

        // ---------------------------------------------------------------------
        // TEST 3: Multi-Cycle Stall During Load Access
        // ---------------------------------------------------------------------
        $display("\n--- TEST 3: Multi-Cycle Stall Protection ---");

        valid_mem_i = 1; is_load_mem_i = 1; mem_size_mem_i = 2'b00; mem_unsigned_mem_i = 1; addr_mem_i = 32'h3001;
        @(posedge clk_i); 
        
        stall_i = 1;
        valid_mem_i = 0; is_load_mem_i = 0; addr_mem_i = 32'h4000; // Upstream clears during stall
        
        repeat (2) @(posedge clk_i);
        dmem_rdata_i = 32'h0000FE00; // Byte 1 = 0xFE
        check_load_resp("Load Data Held Correctly Across 2-Cycle Stall", 32'h000000FE);

        stall_i = 0;
        @(posedge clk_i);
        check_load_resp("Post-Stall Output Invalidated Cleanly", 32'h00000000);

        // ---------------------------------------------------------------------
        // TEST 4: Self-Checking Randomized Stress Test (200 Iterations)
        // ---------------------------------------------------------------------
        $display("\n--- TEST 4: Self-Checking Randomized Stress Test ---");
        
        repeat (200) begin
            logic        rand_stall;
            logic        rand_valid;
            logic        rand_is_load;
            logic        rand_is_store;
            logic [31:0] rand_addr;
            logic [31:0] rand_sdata;
            logic [1:0]  rand_size;
            logic        rand_unsigned;
            logic [31:0] rand_rdata;
            logic [31:0] exp_rdata;

            rand_stall    = ($urandom_range(0, 100) < 20); // 20% stall chance
            rand_valid    = $urandom_range(0, 1);
            rand_is_load  = rand_valid ? $urandom_range(0, 1) : 0;
            rand_is_store = (rand_valid && !rand_is_load) ? 1 : 0;
            rand_addr     = $urandom();
            rand_sdata    = $urandom();
            rand_size     = $urandom_range(0, 2);
            rand_unsigned = $urandom_range(0, 1);
            rand_rdata    = $urandom();

            if (!stall_i) begin
                valid_mem_i        = rand_valid;
                is_load_mem_i       = rand_is_load;
                is_store_mem_i      = rand_is_store;
                addr_mem_i         = rand_addr;
                store_data_mem_i   = rand_sdata;
                mem_size_mem_i     = rand_size;
                mem_unsigned_mem_i = rand_unsigned;
            end

            stall_i      = rand_stall;
            dmem_rdata_i = rand_rdata;

            // Wait for clock edge to update internal state (valid_mem_q, etc.)
            @(posedge clk_i);
            #1;

            // Calculate expected output AFTER registers update for current cycle
            if (dut.valid_mem_q && dut.is_load_mem_q) begin
                exp_rdata = get_expected_load(dmem_rdata_i, dut.addr_lsb_q, dut.mem_size_q, dut.mem_unsigned_q);
            end else begin
                exp_rdata = 32'h0;
            end

            if (mem_rdata_o !== exp_rdata) begin
                $error("[FAIL Stress Test] Expected 0x%h | Got 0x%h", exp_rdata, mem_rdata_o);
                tests_failed++;
            end else begin
                tests_passed++;
            end
        end

        // ---------------------------------------------------------------------
        // Final Test Summary
        // ---------------------------------------------------------------------
        $display("\n=======================================================================");
        if (tests_failed == 0) begin
            $display("  ALL TESTS PASSED SUCCESSFULLY! (%0d Checks Executed)", tests_passed);
        end else begin
            $display("  VERIFICATION FAILED: %0d Errors Detected!", tests_failed);
        end
        $display("=======================================================================\n");

        $finish;
    end

endmodule
