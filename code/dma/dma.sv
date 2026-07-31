`timescale 1ns / 1ps

module dma_top (
    input  logic        clk,
    input  logic        rst_n,

    // AXI4-Lite Register Slave Interface

    input  logic [31:0] s_axi_lite_awaddr,
    input  logic        s_axi_lite_awvalid,
    output logic        s_axi_lite_awready,
    input  logic [31:0] s_axi_lite_wdata,
    input  logic        s_axi_lite_wvalid,
    output logic        s_axi_lite_wready,
    output logic [1:0]  s_axi_lite_bresp,
    output logic        s_axi_lite_bvalid,
    input  logic        s_axi_lite_bready,
    input  logic [31:0] s_axi_lite_araddr,
    input  logic        s_axi_lite_arvalid,
    output logic        s_axi_lite_arready,
    output logic [31:0] s_axi_lite_rdata,
    output logic [1:0]  s_axi_lite_rresp,
    output logic        s_axi_lite_rvalid,
    input  logic        s_axi_lite_rready,


    // AXI4 Master Interface (Memory Read & Write)

    output logic [31:0] m_axi_araddr,
    output logic [7:0]  m_axi_arlen,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready,

    output logic [31:0] m_axi_awaddr,
    output logic [7:0]  m_axi_awlen,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic        m_axi_wvalid,
    output logic        m_axi_wlast,
    input  logic        m_axi_wready,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,


    // AXI-Stream Accelerator Interfaces

    output logic [3:0]  m_axis_mm2s_tdata,
    output logic        m_axis_mm2s_tvalid,
    input  logic        m_axis_mm2s_tready,

    input  logic [3:0]  s_axis_s2mm_tdata,
    input  logic        s_axis_s2mm_tvalid,
    output logic        s_axis_s2mm_tready
);

    // Register Offsets
    localparam ADDR_CTRL  = 32'h00;
    localparam ADDR_STAT  = 32'h04;
    localparam ADDR_SRC   = 32'h08;
    localparam ADDR_DEST  = 32'h0C;
    localparam ADDR_LEN   = 32'h10;

    // Registers
    logic [31:0] reg_ctrl;
    logic [31:0] reg_status;
    logic [31:0] reg_src_addr;
    logic [31:0] reg_dest_addr;
    logic [31:0] reg_xfer_len;

    logic start_pulse;
    logic rd_done, wr_done;
    logic busy;

    assign busy = reg_status[0];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_status <= 32'h0;
        end else begin
            if (start_pulse) begin
                reg_status <= 32'h1; 
            end else if (rd_done && wr_done) begin
                reg_status <= 32'h2; 
            end
        end
    end


    // AXI-Lite Slave Register Write Control

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl      <= '0;
            reg_src_addr  <= '0;
            reg_dest_addr <= '0;
            reg_xfer_len  <= '0;
            start_pulse   <= 1'b0;
            s_axi_lite_awready <= 1'b0;
            s_axi_lite_wready  <= 1'b0;
            s_axi_lite_bvalid  <= 1'b0;
            s_axi_lite_bresp   <= 2'b00;
        end else begin
            start_pulse <= 1'b0; 

            if (s_axi_lite_awvalid && s_axi_lite_wvalid && !s_axi_lite_bvalid) begin
                s_axi_lite_awready <= 1'b1;
                s_axi_lite_wready  <= 1'b1;

                case (s_axi_lite_awaddr[7:0])
                    ADDR_CTRL: begin
                        reg_ctrl <= s_axi_lite_wdata;
                        if (s_axi_lite_wdata[0]) start_pulse <= 1'b1;
                    end
                    ADDR_SRC:  reg_src_addr  <= s_axi_lite_wdata;
                    ADDR_DEST: reg_dest_addr <= s_axi_lite_wdata;
                    ADDR_LEN:  reg_xfer_len  <= s_axi_lite_wdata;
                endcase

                s_axi_lite_bvalid <= 1'b1;
            end else begin
                s_axi_lite_awready <= 1'b0;
                s_axi_lite_wready  <= 1'b0;
            end

            if (s_axi_lite_bvalid && s_axi_lite_bready) begin
                s_axi_lite_bvalid <= 1'b0;
            end
        end
    end

    // AXI-Lite Read Logic
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_lite_arready <= 1'b0;
            s_axi_lite_rvalid  <= 1'b0;
            s_axi_lite_rdata   <= '0;
            s_axi_lite_rresp   <= 2'b00;
        end else begin
            if (s_axi_lite_arvalid && !s_axi_lite_rvalid) begin
                s_axi_lite_arready <= 1'b1;
                s_axi_lite_rvalid  <= 1'b1;
                case (s_axi_lite_araddr[7:0])
                    ADDR_CTRL:  s_axi_lite_rdata <= reg_ctrl;
                    ADDR_STAT:  s_axi_lite_rdata <= reg_status;
                    ADDR_SRC:   s_axi_lite_rdata <= reg_src_addr;
                    ADDR_DEST:  s_axi_lite_rdata <= reg_dest_addr;
                    ADDR_LEN:   s_axi_lite_rdata <= reg_xfer_len;
                    default:    s_axi_lite_rdata <= 32'h0;
                endcase
            end else begin
                s_axi_lite_arready <= 1'b0;
            end

            if (s_axi_lite_rvalid && s_axi_lite_rready) begin
                s_axi_lite_rvalid <= 1'b0;
            end
        end
    end


    // MM2S Engine (Read Memory -> Unpack to 4-bit Stream)

    typedef enum logic [2:0] {R_IDLE, R_ADDR, R_DATA, R_UNPACK, R_DONE} r_state_t;
    r_state_t r_state;

    logic [31:0] rd_buf;
    logic [31:0] rd_bytes_left;
    logic [2:0]  unpack_idx;

    assign m_axis_mm2s_tvalid = (r_state == R_UNPACK);
    assign m_axis_mm2s_tdata  = rd_buf[(unpack_idx * 4) +: 4];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state            <= R_IDLE;
            m_axi_araddr       <= '0;
            m_axi_arlen        <= '0;
            m_axi_arvalid      <= 1'b0;
            m_axi_rready       <= 1'b0;
            rd_done            <= 1'b0;
            unpack_idx         <= '0;
            rd_bytes_left      <= '0;
        end else begin
            case (r_state)
                R_IDLE: begin

                    if (start_pulse) begin
                        m_axi_araddr  <= reg_src_addr;
                        rd_bytes_left <= reg_xfer_len;
                        rd_done       <= 1'b0;
                        r_state       <= R_ADDR;
                    end
                end

                R_ADDR: begin
                    m_axi_arvalid <= 1'b1;
                    m_axi_arlen   <= 8'd0; // Single word read
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        r_state       <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        rd_buf       <= m_axi_rdata;
                        m_axi_rready <= 1'b0;
                        unpack_idx   <= '0;
                        r_state      <= R_UNPACK;
                    end
                end

                R_UNPACK: begin
                    if (m_axis_mm2s_tvalid && m_axis_mm2s_tready) begin
                        if (unpack_idx == 3'd7) begin 
                            m_axi_araddr <= m_axi_araddr + 4;

                            if (rd_bytes_left <= 4) begin
                                rd_done <= 1'b1;
                                r_state <= R_DONE;
                            end else begin
                                rd_bytes_left <= rd_bytes_left - 4;
                                r_state       <= R_ADDR;
                            end
                        end else begin
                            unpack_idx <= unpack_idx + 1'b1;
                        end
                    end
                end

                R_DONE: begin
                    if (!busy) begin
                        r_state <= R_IDLE;
                    end
                end
            endcase
        end
    end


    // S2MM Engine (Pack 4-bit Stream -> Write to Memory)

    typedef enum logic [2:0] {W_IDLE, W_PACK, W_ADDR, W_DATA, W_RESP, W_DONE} w_state_t;
    w_state_t w_state;

    logic [63:0] pack_buf;
    logic [3:0]  pack_elm_cnt;
    logic [31:0] wr_bytes_left;

    assign s_axis_s2mm_tready = (w_state == W_PACK);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state       <= W_IDLE;
            wr_done       <= 1'b0;
            m_axi_awaddr  <= '0;
            m_axi_awlen   <= '0;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata   <= '0;
            m_axi_wvalid  <= 1'b0;
            m_axi_wlast   <= 1'b0;
            m_axi_bready  <= 1'b0;
            pack_elm_cnt  <= '0;
            pack_buf      <= '0;
            wr_bytes_left <= '0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    wr_done <= 1'b0;
                    if (start_pulse) begin
                        m_axi_awaddr  <= reg_dest_addr;
                        wr_bytes_left <= reg_xfer_len;
                        pack_elm_cnt  <= '0;
                        w_state       <= W_PACK;
                    end
                end

                W_PACK: begin
                    if (s_axis_s2mm_tvalid && s_axis_s2mm_tready) begin
                        pack_buf[(pack_elm_cnt * 4) +: 4] <= s_axis_s2mm_tdata;
                        pack_elm_cnt <= pack_elm_cnt + 1'b1;

                        if (pack_elm_cnt == 4'd15) begin
                            w_state <= W_ADDR;
                        end
                    end
                end

                W_ADDR: begin
                    m_axi_awvalid <= 1'b1;
                    m_axi_awlen   <= 8'd1; // 2 words burst = 8 bytes
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        m_axi_wdata   <= pack_buf[31:0];
                        m_axi_wlast   <= 1'b0;
                        w_state       <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (!m_axi_wlast) begin
                            m_axi_wdata <= pack_buf[63:32];
                            m_axi_wlast <= 1'b1;
                        end else begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wlast  <= 1'b0;
                            m_axi_bready <= 1'b1;
                            w_state      <= W_RESP;
                        end
                    end
                end

                W_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        m_axi_awaddr <= m_axi_awaddr + 8; 
                        if (wr_bytes_left <= 8) begin
                            wr_done <= 1'b1;
                            w_state <= W_DONE;
                        end else begin
                            wr_bytes_left <= wr_bytes_left - 8;
                            pack_elm_cnt  <= '0;
                            w_state       <= W_PACK;
                        end
                    end
                end

                W_DONE: begin
                    if (!busy) begin
                        w_state <= W_IDLE;
                    end
                end
            endcase
        end
    end

endmodule