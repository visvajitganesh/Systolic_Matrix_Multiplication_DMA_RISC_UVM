// =============================================================================
// bram_axi_top.sv
//
// Shared BRAM with two access ports:
//   - AXI4 (full)      slave port  -> connects to DMA master (m_axi_* on dma.sv)
//   - AXI4-Lite         slave port  -> connects to RISC master (control/data access)
//
// Both ports share ONE physical memory array through a fixed-priority arbiter
// (DMA wins ties, since DMA bursts should not be interrupted mid-transfer).
//
// Assumptions (adjust parameters if these don't match your system):
//   - AXI_DATA_WIDTH = 32  (matches dma.sv burst word size)
//   - BRAM_DEPTH      = 48  (as specified)
//   - Active-low async reset (rst_n), matching dma.sv
//   - AXI4 side supports INCR bursts (arlen/awlen), single outstanding txn
//   - AXI4-Lite side is single-beat only (no burst) per protocol definition
// =============================================================================

// -----------------------------------------------------------------------------
// 1. Physical memory core (single read/write port, arbitrated externally)
// -----------------------------------------------------------------------------
module bram_core #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH      = 48,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
)(
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     req_valid,
    input  logic                     req_we,
    input  logic [ADDR_WIDTH-1:0]    req_addr,
    input  logic [DATA_WIDTH-1:0]    req_wdata,

    output logic                     resp_valid,
    output logic [DATA_WIDTH-1:0]    resp_rdata
);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid <= 1'b0;
            resp_rdata <= '0;
        end else begin
            resp_valid <= 1'b0;
            if (req_valid) begin
                if (req_we) begin
                    mem[req_addr] <= req_wdata;
                end else begin
                    resp_rdata <= mem[req_addr];
                end
                resp_valid <= 1'b1;
            end
        end
    end

endmodule


// -----------------------------------------------------------------------------
// 2. AXI4 (full) slave wrapper - for DMA master connection
//    Supports single-outstanding INCR burst read and write.
// -----------------------------------------------------------------------------
module axi4_slave_if #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int MEM_ADDR_WIDTH = 6      // $clog2(48)
)(
    input  logic                        clk,
    input  logic                        rst_n,

    // ---- AXI4 write address channel ----
    input  logic [AXI_ADDR_WIDTH-1:0]   awaddr,
    input  logic [7:0]                  awlen,
    input  logic                        awvalid,
    output logic                        awready,

    // ---- AXI4 write data channel ----
    input  logic [AXI_DATA_WIDTH-1:0]   wdata,
    input  logic                        wlast,
    input  logic                        wvalid,
    output logic                        wready,

    // ---- AXI4 write response channel ----
    output logic [1:0]                  bresp,
    output logic                        bvalid,
    input  logic                        bready,

    // ---- AXI4 read address channel ----
    input  logic [AXI_ADDR_WIDTH-1:0]   araddr,
    input  logic [7:0]                  arlen,
    input  logic                        arvalid,
    output logic                        arready,

    // ---- AXI4 read data channel ----
    output logic [AXI_DATA_WIDTH-1:0]   rdata,
    output logic [1:0]                  rresp,
    output logic                        rlast,
    output logic                        rvalid,
    input  logic                        rready,

    // ---- internal arbiter request/response (to bram_core via mux) ----
    output logic                        mem_req_valid,
    output logic                        mem_req_we,
    output logic [MEM_ADDR_WIDTH-1:0]   mem_req_addr,
    output logic [AXI_DATA_WIDTH-1:0]   mem_req_wdata,
    input  logic                        mem_gnt,        // arbiter grant
    input  logic                        mem_resp_valid,
    input  logic [AXI_DATA_WIDTH-1:0]   mem_resp_rdata
);

    typedef enum logic [1:0] {IDLE, WR_BURST, WAIT_BRESP, RD_BURST} state_t;
    state_t state;

    logic [MEM_ADDR_WIDTH-1:0] waddr_cnt, raddr_cnt;
    logic [7:0]                wbeats_left, rbeats_left;
    logic                      rd_req_pending, rd_last_pend;

    assign awready = (state == IDLE);
    assign arready = (state == IDLE) && !awvalid; // write has priority if both request same cycle

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            bvalid        <= 1'b0;
            bresp         <= 2'b00;
            rvalid        <= 1'b0;
            rlast         <= 1'b0;
            rresp         <= 2'b00;
            mem_req_valid <= 1'b0;
            mem_req_we    <= 1'b0;
            wready        <= 1'b0;
            rd_req_pending<= 1'b0;
            rd_last_pend  <= 1'b0;
        end else begin
            mem_req_valid <= 1'b0;
            wready        <= 1'b0;

            case (state)
                IDLE: begin
                    if (awvalid) begin
                        waddr_cnt   <= awaddr[MEM_ADDR_WIDTH+1:2]; // word address
                        wbeats_left <= awlen + 1'b1;
                        state       <= WR_BURST;
                    end else if (arvalid) begin
                        raddr_cnt   <= araddr[MEM_ADDR_WIDTH+1:2];
                        rbeats_left <= arlen + 1'b1;
                        state       <= RD_BURST;
                    end
                end

                WR_BURST: begin
                    wready <= 1'b1;
                    if (wvalid && wready) begin
                        mem_req_valid <= 1'b1;
                        mem_req_we    <= 1'b1;
                        mem_req_addr  <= waddr_cnt;
                        mem_req_wdata <= wdata;
                        waddr_cnt     <= waddr_cnt + 1'b1;
                        wbeats_left   <= wbeats_left - 1'b1;
                        wready        <= 1'b0;
                        if (wlast || wbeats_left == 8'd1)
                            state <= WAIT_BRESP;
                    end
                end

                WAIT_BRESP: begin
                    if (mem_gnt) begin
                        bvalid <= 1'b1;
                        bresp  <= 2'b00; // OKAY
                    end
                    if (bvalid && bready) begin
                        bvalid <= 1'b0;
                        state  <= IDLE;
                    end
                end

                RD_BURST: begin
                    // Strict single-outstanding-request handshake: only issue
                    // a new memory request once no request is pending AND the
                    // previous beat has been consumed (rvalid deasserted).
                    // This avoids issuing a duplicate request for the same
                    // address before raddr_cnt/rvalid have visibly updated.
                    if (!rd_req_pending && !rvalid && rbeats_left != 0) begin
                        mem_req_valid  <= 1'b1;
                        mem_req_we     <= 1'b0;
                        mem_req_addr   <= raddr_cnt;
                        rd_req_pending <= 1'b1;
                        rd_last_pend   <= (rbeats_left == 8'd1);
                    end

                    if (mem_resp_valid) begin
                        rvalid         <= 1'b1;
                        rdata          <= mem_resp_rdata;
                        rresp          <= 2'b00;
                        rlast          <= rd_last_pend;
                        rd_req_pending <= 1'b0;
                    end

                    if (rvalid && rready) begin
                        rvalid      <= 1'b0;
                        raddr_cnt   <= raddr_cnt + 1'b1;
                        rbeats_left <= rbeats_left - 1'b1;
                        if (rlast) state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule


// -----------------------------------------------------------------------------
// 3. AXI4-Lite slave wrapper - for RISC master connection (single-beat only)
// -----------------------------------------------------------------------------
module axi4_lite_slave_if #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int MEM_ADDR_WIDTH = 6
)(
    input  logic                        clk,
    input  logic                        rst_n,

    input  logic [AXI_ADDR_WIDTH-1:0]   awaddr,
    input  logic                        awvalid,
    output logic                        awready,

    input  logic [AXI_DATA_WIDTH-1:0]   wdata,
    input  logic                        wvalid,
    output logic                        wready,

    output logic [1:0]                  bresp,
    output logic                        bvalid,
    input  logic                        bready,

    input  logic [AXI_ADDR_WIDTH-1:0]   araddr,
    input  logic                        arvalid,
    output logic                        arready,

    output logic [AXI_DATA_WIDTH-1:0]   rdata,
    output logic [1:0]                  rresp,
    output logic                        rvalid,
    input  logic                        rready,

    // internal arbiter request/response
    output logic                        mem_req_valid,
    output logic                        mem_req_we,
    output logic [MEM_ADDR_WIDTH-1:0]   mem_req_addr,
    output logic [AXI_DATA_WIDTH-1:0]   mem_req_wdata,
    input  logic                        mem_gnt,
    input  logic                        mem_resp_valid,
    input  logic [AXI_DATA_WIDTH-1:0]   mem_resp_rdata
);

    typedef enum logic [1:0] {IDLE, WRITE, RESP, READ} state_t;
    state_t state;

    logic [AXI_ADDR_WIDTH-1:0] awaddr_lat, araddr_lat;

    assign awready = (state == IDLE) && !arvalid; // read has priority if both request (Lite = simple, low traffic)
    assign arready = (state == IDLE);
    assign wready  = (state == WRITE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            bvalid        <= 1'b0;
            bresp         <= 2'b00;
            rvalid        <= 1'b0;
            rresp         <= 2'b00;
            mem_req_valid <= 1'b0;
            mem_req_we    <= 1'b0;
        end else begin
            mem_req_valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (arvalid) begin
                        araddr_lat <= araddr;
                        state      <= READ;
                    end else if (awvalid) begin
                        awaddr_lat <= awaddr;
                        state      <= WRITE;
                    end
                end

                WRITE: begin
                    if (wvalid && wready) begin
                        mem_req_valid <= 1'b1;
                        mem_req_we    <= 1'b1;
                        mem_req_addr  <= awaddr_lat[MEM_ADDR_WIDTH+1:2];
                        mem_req_wdata <= wdata;
                        state         <= RESP;
                    end
                end

                RESP: begin
                    if (mem_gnt) begin
                        bvalid <= 1'b1;
                        bresp  <= 2'b00;
                    end
                    if (bvalid && bready) begin
                        bvalid <= 1'b0;
                        state  <= IDLE;
                    end
                end

                READ: begin
                    if (!rvalid) begin
                        mem_req_valid <= 1'b1;
                        mem_req_we    <= 1'b0;
                        mem_req_addr  <= araddr_lat[MEM_ADDR_WIDTH+1:2];
                    end
                    if (mem_resp_valid) begin
                        rvalid <= 1'b1;
                        rdata  <= mem_resp_rdata;
                        rresp  <= 2'b00;
                    end
                    if (rvalid && rready) begin
                        rvalid <= 1'b0;
                        state  <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule


// -----------------------------------------------------------------------------
// 4. Arbiter/mux - fixed priority (DMA/AXI4 side wins ties over RISC/Lite side)
// -----------------------------------------------------------------------------
module bram_arbiter #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 6
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // Port A - DMA (AXI4), higher priority
    input  logic                     a_req_valid,
    input  logic                     a_req_we,
    input  logic [ADDR_WIDTH-1:0]    a_req_addr,
    input  logic [DATA_WIDTH-1:0]    a_req_wdata,
    output logic                     a_gnt,
    output logic                     a_resp_valid,
    output logic [DATA_WIDTH-1:0]    a_resp_rdata,

    // Port B - RISC (AXI4-Lite), lower priority
    input  logic                     b_req_valid,
    input  logic                     b_req_we,
    input  logic [ADDR_WIDTH-1:0]    b_req_addr,
    input  logic [DATA_WIDTH-1:0]    b_req_wdata,
    output logic                     b_gnt,
    output logic                     b_resp_valid,
    output logic [DATA_WIDTH-1:0]    b_resp_rdata,

    // to bram_core
    output logic                     mem_req_valid,
    output logic                     mem_req_we,
    output logic [ADDR_WIDTH-1:0]    mem_req_addr,
    output logic [DATA_WIDTH-1:0]    mem_req_wdata,
    input  logic                     mem_resp_valid,
    input  logic [DATA_WIDTH-1:0]    mem_resp_rdata
);

    logic grant_a, grant_a_d;

    always_comb begin
        grant_a       = a_req_valid;                   // DMA always wins on contention
        mem_req_valid = a_req_valid | b_req_valid;
        mem_req_we    = grant_a ? a_req_we    : b_req_we;
        mem_req_addr  = grant_a ? a_req_addr  : b_req_addr;
        mem_req_wdata = grant_a ? a_req_wdata : b_req_wdata;
        a_gnt         = grant_a;
        b_gnt         = ~grant_a & b_req_valid;
    end

    // remember which port owned the request so the 1-cycle-later response
    // (from bram_core) routes back to the correct requester
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) grant_a_d <= 1'b0;
        else        grant_a_d <= grant_a;
    end

    assign a_resp_valid = mem_resp_valid & grant_a_d;
    assign b_resp_valid = mem_resp_valid & ~grant_a_d;
    assign a_resp_rdata = mem_resp_rdata;
    assign b_resp_rdata = mem_resp_rdata;

endmodule


// -----------------------------------------------------------------------------
// 5. Top level - wires everything together
// -----------------------------------------------------------------------------
module bram_axi_top #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int BRAM_DEPTH     = 48,
    parameter int MEM_ADDR_WIDTH = $clog2(BRAM_DEPTH)
)(
    input  logic clk,
    input  logic rst_n,

    // ===== AXI4 (full) slave port - connects to DMA m_axi_* master =====
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [7:0]                s_axi_awlen,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic                      s_axi_wlast,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [7:0]                s_axi_arlen,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rlast,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    // ===== AXI4-Lite slave port - connects to RISC master =====
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_lite_awaddr,
    input  logic                      s_axi_lite_awvalid,
    output logic                      s_axi_lite_awready,
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_lite_wdata,
    input  logic                      s_axi_lite_wvalid,
    output logic                      s_axi_lite_wready,
    output logic [1:0]                s_axi_lite_bresp,
    output logic                      s_axi_lite_bvalid,
    input  logic                      s_axi_lite_bready,
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_lite_araddr,
    input  logic                      s_axi_lite_arvalid,
    output logic                      s_axi_lite_arready,
    output logic [AXI_DATA_WIDTH-1:0] s_axi_lite_rdata,
    output logic [1:0]                s_axi_lite_rresp,
    output logic                      s_axi_lite_rvalid,
    input  logic                      s_axi_lite_rready
);

    // ---- internal arbiter <-> port wires ----
    logic                     a_req_valid, a_req_we, a_gnt, a_resp_valid;
    logic [MEM_ADDR_WIDTH-1:0] a_req_addr;
    logic [AXI_DATA_WIDTH-1:0] a_req_wdata, a_resp_rdata;

    logic                     b_req_valid, b_req_we, b_gnt, b_resp_valid;
    logic [MEM_ADDR_WIDTH-1:0] b_req_addr;
    logic [AXI_DATA_WIDTH-1:0] b_req_wdata, b_resp_rdata;

    logic                     mem_req_valid, mem_req_we, mem_resp_valid;
    logic [MEM_ADDR_WIDTH-1:0] mem_req_addr;
    logic [AXI_DATA_WIDTH-1:0] mem_req_wdata, mem_resp_rdata;

    // ---- AXI4 (DMA) slave wrapper ----
    axi4_slave_if #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .MEM_ADDR_WIDTH (MEM_ADDR_WIDTH)
    ) u_axi4 (
        .clk(clk), .rst_n(rst_n),
        .awaddr(s_axi_awaddr), .awlen(s_axi_awlen), .awvalid(s_axi_awvalid), .awready(s_axi_awready),
        .wdata(s_axi_wdata),   .wlast(s_axi_wlast),   .wvalid(s_axi_wvalid),   .wready(s_axi_wready),
        .bresp(s_axi_bresp),   .bvalid(s_axi_bvalid),   .bready(s_axi_bready),
        .araddr(s_axi_araddr), .arlen(s_axi_arlen), .arvalid(s_axi_arvalid), .arready(s_axi_arready),
        .rdata(s_axi_rdata),   .rresp(s_axi_rresp),   .rlast(s_axi_rlast), .rvalid(s_axi_rvalid), .rready(s_axi_rready),
        .mem_req_valid(a_req_valid), .mem_req_we(a_req_we),
        .mem_req_addr(a_req_addr),   .mem_req_wdata(a_req_wdata),
        .mem_gnt(a_gnt), .mem_resp_valid(a_resp_valid), .mem_resp_rdata(a_resp_rdata)
    );

    // ---- AXI4-Lite (RISC) slave wrapper ----
    axi4_lite_slave_if #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .MEM_ADDR_WIDTH (MEM_ADDR_WIDTH)
    ) u_axi4_lite (
        .clk(clk), .rst_n(rst_n),
        .awaddr(s_axi_lite_awaddr), .awvalid(s_axi_lite_awvalid), .awready(s_axi_lite_awready),
        .wdata(s_axi_lite_wdata),   .wvalid(s_axi_lite_wvalid),   .wready(s_axi_lite_wready),
        .bresp(s_axi_lite_bresp),   .bvalid(s_axi_lite_bvalid),   .bready(s_axi_lite_bready),
        .araddr(s_axi_lite_araddr), .arvalid(s_axi_lite_arvalid), .arready(s_axi_lite_arready),
        .rdata(s_axi_lite_rdata),   .rresp(s_axi_lite_rresp),   .rvalid(s_axi_lite_rvalid), .rready(s_axi_lite_rready),
        .mem_req_valid(b_req_valid), .mem_req_we(b_req_we),
        .mem_req_addr(b_req_addr),   .mem_req_wdata(b_req_wdata),
        .mem_gnt(b_gnt), .mem_resp_valid(b_resp_valid), .mem_resp_rdata(b_resp_rdata)
    );

    // ---- Arbiter (DMA priority over RISC) ----
    bram_arbiter #(
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ADDR_WIDTH (MEM_ADDR_WIDTH)
    ) u_arb (
        .clk(clk), .rst_n(rst_n),
        .a_req_valid(a_req_valid), .a_req_we(a_req_we), .a_req_addr(a_req_addr), .a_req_wdata(a_req_wdata),
        .a_gnt(a_gnt), .a_resp_valid(a_resp_valid), .a_resp_rdata(a_resp_rdata),
        .b_req_valid(b_req_valid), .b_req_we(b_req_we), .b_req_addr(b_req_addr), .b_req_wdata(b_req_wdata),
        .b_gnt(b_gnt), .b_resp_valid(b_resp_valid), .b_resp_rdata(b_resp_rdata),
        .mem_req_valid(mem_req_valid), .mem_req_we(mem_req_we),
        .mem_req_addr(mem_req_addr),   .mem_req_wdata(mem_req_wdata),
        .mem_resp_valid(mem_resp_valid), .mem_resp_rdata(mem_resp_rdata)
    );

    // ---- Physical memory ----
    bram_core #(
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .DEPTH      (BRAM_DEPTH),
        .ADDR_WIDTH (MEM_ADDR_WIDTH)
    ) u_mem (
        .clk(clk), .rst_n(rst_n),
        .req_valid(mem_req_valid), .req_we(mem_req_we),
        .req_addr(mem_req_addr),   .req_wdata(mem_req_wdata),
        .resp_valid(mem_resp_valid), .resp_rdata(mem_resp_rdata)
    );

endmodule
