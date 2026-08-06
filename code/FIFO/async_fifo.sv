`timescale 1ns / 1ps

// -----------------------------------------------------------------------
// async_fifo
//
// Generic dual-clock (asynchronous) FIFO. Required whenever write and
// read sides run on independent, unrelated clocks (e.g. clk_sys vs
// clk_accel in input_buffer_if / output_buffer_if) -- a single-clock
// FIFO is NOT safe across that boundary.
//
// Standard Cliff-Cummings-style design: binary pointers converted to
// Gray code before crossing domains, 2-flop synchronizers on each side,
// full/empty computed from the synchronized Gray pointers.
//
// DEPTH must be a power of two.
// Read side is FWFT-style: rd_data reflects the current head of the
// queue combinationally whenever !empty; rd_en just pops on the next
// clock edge (same convention used by fifo_sync.sv earlier).
// -----------------------------------------------------------------------

module async_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int DEPTH      = 16,   // must be a power of 2
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    // Write domain
    input  logic                    wr_clk,
    input  logic                    wr_rst_n,
    input  logic                    wr_en,
    input  logic [DATA_WIDTH - 1:0] wr_data,
    output logic                    full,

    // Read domain
    input  logic                    rd_clk,
    input  logic                    rd_rst_n,
    input  logic                    rd_en,
    output logic [DATA_WIDTH - 1:0] rd_data,
    output logic                    empty
);

    logic [DATA_WIDTH - 1:0] mem [0:DEPTH - 1];

    // Binary + Gray pointers, one extra MSB used purely for wrap detection
    logic [ADDR_WIDTH:0] wr_bin, wr_bin_next;
    logic [ADDR_WIDTH:0] wr_gray, wr_gray_next;
    logic [ADDR_WIDTH:0] rd_bin, rd_bin_next;
    logic [ADDR_WIDTH:0] rd_gray, rd_gray_next;

    // Synchronized copies of the opposite-domain pointer (2-flop each)
    logic [ADDR_WIDTH:0] rd_gray_sync1, rd_gray_sync2; // read ptr into wr_clk
    logic [ADDR_WIDTH:0] wr_gray_sync1, wr_gray_sync2; // write ptr into rd_clk

    logic full_next, empty_next;

    wire wr_fire = wr_en && !full;
    wire rd_fire = rd_en && !empty;

    // -------------------- Write domain --------------------
    assign wr_bin_next  = wr_bin + (wr_fire ? 1'b1 : 1'b0);
    assign wr_gray_next = (wr_bin_next >> 1) ^ wr_bin_next;

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_bin  <= '0;
            wr_gray <= '0;
        end 
        else begin
            wr_bin  <= wr_bin_next;
            wr_gray <= wr_gray_next;
        end
    end

    always_ff @(posedge wr_clk) begin
        if (wr_fire) 
            mem[wr_bin[ADDR_WIDTH - 1:0]] <= wr_data;
    end

    // synchronize read pointer into write clock domain
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            rd_gray_sync1 <= '0;
            rd_gray_sync2 <= '0;
        end 
        else begin
            rd_gray_sync1 <= rd_gray;
            rd_gray_sync2 <= rd_gray_sync1;
        end
    end

    // Classic full condition: next write pointer equals synced read
    // pointer with its top two bits inverted (Gray-code wrap detection)
    assign full_next = (wr_gray_next == {~rd_gray_sync2[ADDR_WIDTH -: 2], rd_gray_sync2[ADDR_WIDTH-2:0]});

    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) full <= 1'b0;
        else           full <= full_next;
    end

    // -------------------- Read domain --------------------
    assign rd_bin_next  = rd_bin + (rd_fire ? 1'b1 : 1'b0);
    assign rd_gray_next = (rd_bin_next >> 1) ^ rd_bin_next;

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_bin  <= '0;
            rd_gray <= '0;
        end 
        else begin
            rd_bin  <= rd_bin_next;
            rd_gray <= rd_gray_next;
        end
    end

    assign rd_data = mem[rd_bin[ADDR_WIDTH - 1:0]]; // FWFT: head always presented

    // synchronize write pointer into read clock domain
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            wr_gray_sync1 <= '0;
            wr_gray_sync2 <= '0;
        end 
        else begin
            wr_gray_sync1 <= wr_gray;
            wr_gray_sync2 <= wr_gray_sync1;
        end
    end

    assign empty_next = (rd_gray_next == wr_gray_sync2);

    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) empty <= 1'b1;
        else           empty <= empty_next;
    end

endmodule
