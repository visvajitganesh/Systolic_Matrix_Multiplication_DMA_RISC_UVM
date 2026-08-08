`timescale 1ns / 1ps

module dma #(parameter ADDR_WIDTH=32,
             parameter DATA_WIDTH=32,
             parameter STREAM_WIDTH=4
             )(
    input  logic clk,  
    input  logic rst_n,    
    
    // AXI4-Lite Register Slave Interface
    // Write address 
    input  logic [ADDR_WIDTH-1:0] s_axi_lite_awaddr,   // Write address from host
    input  logic  s_axi_lite_awvalid,  // Write address valid
    output logic  s_axi_lite_awready,  // DMA ready to accept write address

    // Write data 
    input  logic [DATA_WIDTH-1:0] s_axi_lite_wdata,    // Write data from host
    input  logic  s_axi_lite_wvalid,   // Write data valid
    output logic  s_axi_lite_wready,   // DMA ready to accept write data

    // Write response 
    output logic [1:0]  s_axi_lite_bresp,    // Write response (OKAY/ERROR/etc.)
    output logic s_axi_lite_bvalid,   // Write response valid
    input  logic s_axi_lite_bready,   // Host ready to accept write response

    // Read address 
    input  logic [ADDR_WIDTH-1:0] s_axi_lite_araddr,   // Read address from host
    input  logic s_axi_lite_arvalid,  // Read address valid
    output logic s_axi_lite_arready,  // DMA ready to accept read address

    // Read data 
    output logic [DATA_WIDTH-1:0] s_axi_lite_rdata,    // Read data to host
    output logic [1:0]  s_axi_lite_rresp,    // Read response (OKAY/ERROR/etc.)
    output logic s_axi_lite_rvalid,   
    input  logic s_axi_lite_rready,  


    // AXI4 Master Interface (Memory Read & Write)

    output logic [ADDR_WIDTH-1:0] m_axi_araddr,   
    output logic [7:0]  m_axi_arlen,    // Burst length (beats - 1)
    output logic [2:0]  m_axi_arsize,   // Bytes per beat (fixed to 4B here)
    output logic [1:0]  m_axi_arburst,  // Burst type (fixed to INCR here)
    output logic m_axi_arvalid,  
    input  logic  m_axi_arready,  

    // Read data  (R) - returns data requested via AR channel
    input  logic [DATA_WIDTH-1:0] m_axi_rdata,    // Read data from memory
    input  logic [1:0]  m_axi_rresp,   
    input  logic m_axi_rlast,    // Indicates last beat of read burst
    input  logic m_axi_rvalid,  
    output logic m_axi_rready, 

    // Write address  (AW) - used by the S2MM write engine
    output logic [ADDR_WIDTH-1:0] m_axi_awaddr,  
    output logic [7:0]  m_axi_awlen,    // Burst length (beats - 1)
    output logic [2:0]  m_axi_awsize,   // Bytes per beat (fixed to 4B here)
    output logic [1:0]  m_axi_awburst,  // Burst type (fixed to INCR here)
    output logic m_axi_awvalid, 
    input  logic m_axi_awready,  

    // Write data  (W) - carries the data being written
    output logic [DATA_WIDTH-1:0] m_axi_wdata,    
    output logic [(DATA_WIDTH/8)-1:0]  m_axi_wstrb,   // one bit per byte lane (4 bits for 32-bit data)
    output logic m_axi_wvalid,   
    output logic m_axi_wlast,   
    input  logic  m_axi_wready,   
    
    // Write response (B) - completion/error status of the write
    input  logic [1:0]  m_axi_bresp,    // Write response (error checking)
    input  logic m_axi_bvalid,  
    output logic m_axi_bready, 


    // AXI-Stream Accelerator Interfaces
    output logic [STREAM_WIDTH-1:0]  m_axis_mm2s_tdata,   // 4-bit nibble output data
    output logic  m_axis_mm2s_tvalid,  // Nibble data valid
    input  logic   m_axis_mm2s_tready,  // Downstream accelerator ready

    // S2MM stream input: 4-bit nibbles coming in from accelerator, packed
    input  logic [STREAM_WIDTH-1:0]  s_axis_s2mm_tdata,  
    input  logic  s_axis_s2mm_tvalid, 
    output logic  s_axis_s2mm_tready  
);

    // Register address map (byte offsets within the AXI-Lite address space)

    localparam ADDR_CTRL = 32'h00;  // Control register (bit0 = start)
    localparam ADDR_STAT = 32'h04;  // Status register (busy/done/error)
    localparam ADDR_SRC = 32'h08;  // Source address 
    localparam ADDR_DEST = 32'h0C;  // Destination address 
    localparam ADDR_LEN = 32'h10;  // Transfer length register (in bytes)

    localparam [2:0] AXSIZE_4B = 3'b010; // 2^2 = 4 bytes/beat (word-sized beats)
    localparam [1:0] AXBURST_INCR = 2'b01;  // INCR burst type (incrementing address)

    // since this DMA only ever transfers 32-bit words in incrementing bursts.
    assign m_axi_arsize  = AXSIZE_4B;
    assign m_axi_arburst = AXBURST_INCR;
    assign m_axi_awsize  = AXSIZE_4B;
    assign m_axi_awburst = AXBURST_INCR;

    // Memory-mapped configuration/status registers (written/read via AXI-Lite)
    logic [DATA_WIDTH-1:0] reg_ctrl;       // Holds last value written to CTRL register
    logic [DATA_WIDTH-1:0] reg_status;     // Live status: bit0=busy, bit1=done, bit2=error
    logic [DATA_WIDTH-1:0] reg_src_addr;   
    logic [DATA_WIDTH-1:0] reg_dest_addr; 
    logic [DATA_WIDTH-1:0] reg_xfer_len;   // Number of bytes to transfer (READ side)
    logic [30:0] reg_wr_xfer_len;
    // NOTE: reg_wr_xfer_len is derived as reg_xfer_len/2, NOT an independent
    // register. This assumes the accelerator between MM2S and S2MM always
    // reduces data volume exactly 2:1 (e.g. a systolic array taking 2 input
    // matrices -> 1 output matrix of the same element count/width - true for
    // this project's fixed 4x4x4-bit geometry: 32 elements in, 16 out).
    // If you connect anything that does NOT reduce data 2:1 (e.g. a simple
    // passthrough/loopback for testing), the write engine will finish and
    // stop accepting stream data before the read engine has sent everything,
    // stalling the read engine forever (mm2s_tready is tied to the S2MM
    // engine's readiness via the accelerator in between). See the corrected
    // testbench for a stream model that respects this 2:1 contract.

    logic start_pulse;   // One-cycle pulse asserted when CTRL[0] is written as 1
    logic rd_done, wr_done;   
    logic rd_error, wr_error;  
    logic busy;         
    // busy is simply bit 0 of the status register
    assign busy = reg_status[0];
    assign reg_wr_xfer_len = reg_xfer_len>>1;
    // Sets Busy=1 when a transfer starts, and updates Done/Error/Busy

    always_ff @(posedge clk or negedge rst_n) begin                                      /////////
        if (!rst_n) begin                                                                       //  
            reg_status <= 32'h0;      // On reset: not busy, not done, no error                 //   
        end else begin                                                                          //   
            if (start_pulse) begin                                                              //   
                reg_status <= 32'h1; // Set Busy = 1, Done = 0                                  //  
            end else if (rd_done && wr_done) begin                                              /////// Status logic (reg_status) used for polling   
                // Both engines finished: clear busy, set done, report error if any             //
                reg_status <= {29'h0, (rd_error || wr_error), 1'b1, 1'b0};                      //   
                // bit0=Busy(0), bit1=Done(1), bit2=Error                                       //   
            end                                                                                 //   
            // otherwise (mid-transfer, not yet done): hold current status value                //
        end                                                                                     //   
    end                                                                                  /////////
  
  
    // AXI-Lite Slave Register Write Control
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl  <= '0;
            reg_src_addr  <= '0;
            reg_dest_addr <= '0;
            reg_xfer_len  <= '0;
            start_pulse <= 1'b0;
            s_axi_lite_awready <= 1'b0;
            s_axi_lite_wready <= 1'b0;
            s_axi_lite_bvalid <= 1'b0;
            s_axi_lite_bresp <= 2'b00;
        end else begin
            start_pulse <= 1'b0; // Pulse self-clears every cycle unless re-asserted below
            if (s_axi_lite_awvalid && s_axi_lite_wvalid && !s_axi_lite_bvalid) begin
                // Single-cycle handshake: assert AWREADY/WREADY for this beat
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
                // Issue the write response (assume OKAY, since bresp stays 2'b00)
                s_axi_lite_bvalid <= 1'b1;
            end else begin
                // No write accepted this cycle: de-assert ready signals
                s_axi_lite_awready <= 1'b0;
                s_axi_lite_wready  <= 1'b0;
            end
            // Clear BVALID once the host has accepted the write response
            if (s_axi_lite_bvalid && s_axi_lite_bready) begin
                s_axi_lite_bvalid <= 1'b0;
            end
        end
    end

    // AXI-Lite Slave Register Read Logic
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
                    default:  s_axi_lite_rdata <= 32'h0;
                endcase
            end else begin        
                s_axi_lite_arready <= 1'b0;
            end
            if (s_axi_lite_rvalid && s_axi_lite_rready) begin
                s_axi_lite_rvalid <= 1'b0;
            end
        end
    end


    // MM2S Engine (Memory-to-Stream)

    // Read engine states:
    //   R_IDLE   - waiting for a start_pulse to begin a new transfer
    //   R_ADDR   - issuing the read address (AR channel handshake)
    //   R_DATA   - waiting for read data to arrive (R channel handshake)
    //   R_UNPACK - streaming out the 8 nibbles of the word just read
    //   R_DONE   - transfer complete; waiting for status to be cleared (not busy)
    
    
    typedef enum logic [2:0] {R_IDLE, R_ADDR, R_DATA, R_UNPACK, R_DONE} r_state_t;
    r_state_t r_state;
   
    logic [31:0] rd_buf;         
    logic [31:0] rd_bytes_left;  
    logic [2:0]  unpack_idx;   

    assign m_axis_mm2s_tdata = rd_buf[(unpack_idx * 4) +: 4];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state            <= R_IDLE;
            m_axi_araddr       <= '0;
            m_axi_arlen        <= '0;
            m_axi_arvalid      <= 1'b0;
            m_axi_rready       <= 1'b0;
            m_axis_mm2s_tvalid <= 1'b0;
            rd_done            <= 1'b0;
            rd_error           <= 1'b0;
            unpack_idx         <= '0;
            rd_bytes_left      <= '0;
        end else begin
            case (r_state)

                // Wait for the host to trigger a new transfer via CTRL register
                R_IDLE: begin
                    if (start_pulse) begin
                        m_axi_araddr  <= reg_src_addr;  
                        rd_bytes_left <= reg_xfer_len; 
                        rd_done <= 1'b0;           
                        rd_error <= 1'b0;        
                        r_state  <= R_ADDR;        
                    end
                end

                // Issue a single-beat (4-byte) read request on the AR channel
                R_ADDR: begin
                    m_axi_arvalid <= 1'b1;
                    m_axi_arlen   <= 8'd0; // Single beat read (arsize=4B, arburst=INCR)
                    // Wait for the AXI slave/memory to accept the address
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0; // Address accepted; drop ARVALID
                        m_axi_rready  <= 1'b1; // Now ready to receive the read data
                        r_state       <= R_DATA;
                    end
                end

                // Wait for the read data (R channel) to come back from memory
                R_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        rd_buf  <= m_axi_rdata;             // Latch the word read
                        if (m_axi_rresp != 2'b00) rd_error <= 1'b1; 
                        m_axi_rready <= 1'b0;                
                        unpack_idx   <= '0;                    
                        r_state   <= R_UNPACK;
                    end
                end


                R_UNPACK: begin
                    m_axis_mm2s_tvalid <= 1'b1;
                    if (m_axis_mm2s_tvalid && m_axis_mm2s_tready) begin
                        if (unpack_idx == 3'd7) begin // Transmitted 8 nibbles (4 bytes)
                            m_axis_mm2s_tvalid <= 1'b0;
                            m_axi_araddr  <= m_axi_araddr + 4; // Advance to next word

                            if (rd_bytes_left <= 4) begin
                                // This was the last word of the transfer
                                rd_done <= 1'b1;
                                r_state <= R_DONE;
                            end else begin
                                // More words remain: fetch the next one
                                rd_bytes_left <= rd_bytes_left - 4;
                                r_state       <= R_ADDR;
                            end
                        end else begin
                            // Advance to the next nibble within the current word
                            unpack_idx <= unpack_idx + 1'b1;
                        end
                    end
                end

                R_DONE: begin
                    m_axis_mm2s_tvalid <= 1'b0;
                    if (!busy) begin
                        r_state <= R_IDLE;
                    end
                end
            endcase
        end
    end

    // S2MM Engine (Stream-to-Memory)
    // memory as a 2-beat AXI4 burst.

    // Write engine states:
    //   W_IDLE - waiting for a start_pulse to begin a new transfer
    //   W_PACK - accepting incoming nibbles and packing them into pack_buf
    //   W_ADDR - issuing the write address (AW channel handshake)
    //   W_DATA - sending the two write-data beats (W channel handshake)
    //   W_RESP - waiting for the write response (B channel handshake)
    //   W_DONE - transfer complete; waiting for status to be cleared (not busy)
    
    
    typedef enum logic [2:0] {W_IDLE, W_PACK, W_ADDR, W_DATA, W_RESP, W_DONE} w_state_t;
    w_state_t w_state;

    logic [63:0] pack_buf;        // Holds 16 packed nibbles (8 bytes = 2 words)
    logic [3:0]  pack_elm_cnt;    // Count of nibbles packed so far (0-15)
    logic [31:0] wr_bytes_left;  

    // Only accept incoming stream data while actively packing (W_PACK state)
    assign s_axis_s2mm_tready = (w_state == W_PACK);


    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state <= W_IDLE;
            wr_done <= 1'b0;
            wr_error <= 1'b0;
            m_axi_awaddr <= '0;
            m_axi_awlen <= '0;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata <= '0;
            m_axi_wstrb <= '0;
            m_axi_wvalid  <= 1'b0;
            m_axi_wlast <= 1'b0;
            m_axi_bready  <= 1'b0;
            pack_elm_cnt  <= '0;
            pack_buf   <= '0;
            wr_bytes_left <= '0;
        end else begin
            case (w_state)

                // Wait for the host to trigger a new transfer via CTRL register
                W_IDLE: begin
                    wr_done  <= 1'b0;   // Clear completion flag
                    wr_error <= 1'b0;   // Clear error flag
                    if (start_pulse) begin
                        m_axi_awaddr  <= reg_dest_addr;  
                        wr_bytes_left <= {1'b0,reg_wr_xfer_len}; 
                        pack_elm_cnt  <= '0;  
                        w_state  <= W_PACK;
                    end
                end
                
                
                // pack_buf (LSB-first), 4 bits at a time.
                W_PACK: begin
                    if (s_axis_s2mm_tvalid && s_axis_s2mm_tready) begin
                        pack_buf[(pack_elm_cnt * 4) +: 4] <= s_axis_s2mm_tdata;
                        pack_elm_cnt <= pack_elm_cnt + 1'b1;

                        // Check if we packed 16 nibbles (8 bytes) or reached full length
                        if (pack_elm_cnt == 4'd15) begin
                            // Buffer full (64 bits / 2 words): ready to write it out
                            w_state <= W_ADDR;
                        end
                    end
                end

                // Issue a 2-beat (8-byte) write request on the AW channel
                W_ADDR: begin
                    m_axi_awvalid <= 1'b1;
                    m_axi_awlen  <= 8'd1; // 2-beat burst = 8 bytes (awsize=4B, awburst=INCR)
                    // Wait for the AXI slave/memory to accept the write address
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;    
                        m_axi_wvalid  <= 1'b1;           // Start sending write data
                        m_axi_wdata  <= pack_buf[31:0]; 
                        m_axi_wstrb  <= 4'b1111;        // full 32-bit word, all lanes valid
                        m_axi_wlast  <= 1'b0;          
                        w_state <= W_DATA;
                    end
                end

                // Send the two write-data beats (lower word, then upper word)
                W_DATA: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (!m_axi_wlast) begin
                            // First beat was accepted: send the second (last) beat
                            m_axi_wdata <= pack_buf[63:32]; // Second beat: upper 32 bits
                            m_axi_wstrb <= 4'b1111;
                            m_axi_wlast <= 1'b1;
                        end else begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wstrb  <= 4'b0000;
                            m_axi_wlast  <= 1'b0;
                            m_axi_bready <= 1'b1;
                            w_state      <= W_RESP;
                        end
                    end
                end

                // Wait for the write response (B channel) from memory
                W_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        if (m_axi_bresp != 2'b00) wr_error <= 1'b1; // Flag AXI write errors
                        m_axi_bready <= 1'b0;
                        m_axi_awaddr <= m_axi_awaddr + 8; // Offset dest address by 8 bytes

                        if (wr_bytes_left <= 8) begin
                            // This was the last burst of the transfer
                            wr_done <= 1'b1;
                            w_state <= W_DONE;
                        end else begin
                            wr_bytes_left <= wr_bytes_left - 8;
                            pack_elm_cnt  <= '0;
                            w_state  <= W_PACK;
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

// =============================================================================

module bram_core #(
    parameter int DATA_WIDTH = 32,
    parameter int DEPTH      = 48,
    parameter int ADDR_WIDTH = $clog2(DEPTH),
    parameter int STRB_WIDTH = DATA_WIDTH/8
)(
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     req_valid,
    input  logic                     req_we,
    input  logic [ADDR_WIDTH-1:0]    req_addr,
    input  logic [DATA_WIDTH-1:0]    req_wdata,
    input  logic [STRB_WIDTH-1:0]    req_wstrb,

    output logic                     resp_valid,
    output logic [DATA_WIDTH-1:0]    resp_rdata
);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    int b;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid <= 1'b0;
            resp_rdata <= '0;
        end else begin
            resp_valid <= 1'b0;
            if (req_valid) begin
                if (req_we) begin
                    for (b = 0; b < STRB_WIDTH; b++) begin
                        if (req_wstrb[b])
                            mem[req_addr][b*8 +: 8] <= req_wdata[b*8 +: 8];
                    end
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
    parameter int MEM_ADDR_WIDTH = 6,      // $clog2(48)
    parameter int STRB_WIDTH     = AXI_DATA_WIDTH/8
)(
    input  logic                        clk,
    input  logic                        rst_n,

    // ---- AXI4 write address channel ----
    input  logic [AXI_ADDR_WIDTH-1:0]   awaddr,
    input  logic [7:0]                  awlen,
    input  logic [2:0]                  awsize,   // expected: 3'b010 (4B/beat)
    input  logic [1:0]                  awburst,  // expected: 2'b01  (INCR)
    input  logic                        awvalid,
    output logic                        awready,

    // ---- AXI4 write data channel ----
    input  logic [AXI_DATA_WIDTH-1:0]   wdata,
    input  logic [STRB_WIDTH-1:0]       wstrb,
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
    input  logic [2:0]                  arsize,   // expected: 3'b010 (4B/beat)
    input  logic [1:0]                  arburst,  // expected: 2'b01  (INCR)
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
    output logic [STRB_WIDTH-1:0]       mem_req_wstrb,
    input  logic                        mem_gnt,        // arbiter grant
    input  logic                        mem_resp_valid,
    input  logic [AXI_DATA_WIDTH-1:0]   mem_resp_rdata
);

    // This slave only supports fixed 4-byte-beat INCR bursts (which is all
    // dma.sv ever issues - it hardcodes AXSIZE_4B/AXBURST_INCR). awsize/
    // awburst/arsize/arburst are captured/connected (not left dangling as
    // before), but behavior doesn't branch on them since only one fixed
    // mode is supported.
    logic [2:0] awsize_lat, arsize_lat;
    logic [1:0] awburst_lat, arburst_lat;

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
            mem_req_wstrb <= '0;
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
                        awsize_lat  <= awsize;
                        awburst_lat <= awburst;
                        state       <= WR_BURST;
                    end else if (arvalid) begin
                        raddr_cnt   <= araddr[MEM_ADDR_WIDTH+1:2];
                        rbeats_left <= arlen + 1'b1;
                        arsize_lat  <= arsize;
                        arburst_lat <= arburst;
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
                        mem_req_wstrb <= wstrb;
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
    input  logic [(AXI_DATA_WIDTH/8)-1:0] wstrb,
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
    output logic [(AXI_DATA_WIDTH/8)-1:0] mem_req_wstrb,
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
            mem_req_wstrb <= '0;
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
                        mem_req_wstrb <= wstrb;
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
    parameter int ADDR_WIDTH = 6,
    parameter int STRB_WIDTH = DATA_WIDTH/8
)(
    input  logic                     clk,
    input  logic                     rst_n,

    // Port A - DMA (AXI4), higher priority
    input  logic                     a_req_valid,
    input  logic                     a_req_we,
    input  logic [ADDR_WIDTH-1:0]    a_req_addr,
    input  logic [DATA_WIDTH-1:0]    a_req_wdata,
    input  logic [STRB_WIDTH-1:0]    a_req_wstrb,
    output logic                     a_gnt,
    output logic                     a_resp_valid,
    output logic [DATA_WIDTH-1:0]    a_resp_rdata,

    // Port B - RISC (AXI4-Lite), lower priority
    input  logic                     b_req_valid,
    input  logic                     b_req_we,
    input  logic [ADDR_WIDTH-1:0]    b_req_addr,
    input  logic [DATA_WIDTH-1:0]    b_req_wdata,
    input  logic [STRB_WIDTH-1:0]    b_req_wstrb,
    output logic                     b_gnt,
    output logic                     b_resp_valid,
    output logic [DATA_WIDTH-1:0]    b_resp_rdata,

    // to bram_core
    output logic                     mem_req_valid,
    output logic                     mem_req_we,
    output logic [ADDR_WIDTH-1:0]    mem_req_addr,
    output logic [DATA_WIDTH-1:0]    mem_req_wdata,
    output logic [STRB_WIDTH-1:0]    mem_req_wstrb,
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
        mem_req_wstrb = grant_a ? a_req_wstrb : b_req_wstrb;
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
    parameter int MEM_ADDR_WIDTH = $clog2(BRAM_DEPTH),
    parameter int STRB_WIDTH     = AXI_DATA_WIDTH/8
)(
    input  logic clk,
    input  logic rst_n,

    // ===== AXI4 (full) slave port - connects to DMA m_axi_* master =====
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [7:0]                s_axi_awlen,
    input  logic [2:0]                s_axi_awsize,
    input  logic [1:0]                s_axi_awburst,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [STRB_WIDTH-1:0]     s_axi_wstrb,
    input  logic                      s_axi_wlast,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [7:0]                s_axi_arlen,
    input  logic [2:0]                s_axi_arsize,
    input  logic [1:0]                s_axi_arburst,
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
    input  logic [STRB_WIDTH-1:0]     s_axi_lite_wstrb,
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
    logic [STRB_WIDTH-1:0]     a_req_wstrb;

    logic                     b_req_valid, b_req_we, b_gnt, b_resp_valid;
    logic [MEM_ADDR_WIDTH-1:0] b_req_addr;
    logic [AXI_DATA_WIDTH-1:0] b_req_wdata, b_resp_rdata;
    logic [STRB_WIDTH-1:0]     b_req_wstrb;

    logic                     mem_req_valid, mem_req_we, mem_resp_valid;
    logic [MEM_ADDR_WIDTH-1:0] mem_req_addr;
    logic [AXI_DATA_WIDTH-1:0] mem_req_wdata, mem_resp_rdata;
    logic [STRB_WIDTH-1:0]     mem_req_wstrb;

    // ---- AXI4 (DMA) slave wrapper ----
    axi4_slave_if #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .MEM_ADDR_WIDTH (MEM_ADDR_WIDTH)
    ) u_axi4 (
        .clk(clk), .rst_n(rst_n),
        .awaddr(s_axi_awaddr), .awlen(s_axi_awlen),
        .awsize(s_axi_awsize), .awburst(s_axi_awburst),
        .awvalid(s_axi_awvalid), .awready(s_axi_awready),
        .wdata(s_axi_wdata), .wstrb(s_axi_wstrb), .wlast(s_axi_wlast),
        .wvalid(s_axi_wvalid), .wready(s_axi_wready),
        .bresp(s_axi_bresp),   .bvalid(s_axi_bvalid),   .bready(s_axi_bready),
        .araddr(s_axi_araddr), .arlen(s_axi_arlen),
        .arsize(s_axi_arsize), .arburst(s_axi_arburst),
        .arvalid(s_axi_arvalid), .arready(s_axi_arready),
        .rdata(s_axi_rdata),   .rresp(s_axi_rresp),   .rlast(s_axi_rlast), .rvalid(s_axi_rvalid), .rready(s_axi_rready),
        .mem_req_valid(a_req_valid), .mem_req_we(a_req_we),
        .mem_req_addr(a_req_addr),   .mem_req_wdata(a_req_wdata), .mem_req_wstrb(a_req_wstrb),
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
        .wdata(s_axi_lite_wdata), .wstrb(s_axi_lite_wstrb), .wvalid(s_axi_lite_wvalid), .wready(s_axi_lite_wready),
        .bresp(s_axi_lite_bresp),   .bvalid(s_axi_lite_bvalid),   .bready(s_axi_lite_bready),
        .araddr(s_axi_lite_araddr), .arvalid(s_axi_lite_arvalid), .arready(s_axi_lite_arready),
        .rdata(s_axi_lite_rdata),   .rresp(s_axi_lite_rresp),   .rvalid(s_axi_lite_rvalid), .rready(s_axi_lite_rready),
        .mem_req_valid(b_req_valid), .mem_req_we(b_req_we),
        .mem_req_addr(b_req_addr),   .mem_req_wdata(b_req_wdata), .mem_req_wstrb(b_req_wstrb),
        .mem_gnt(b_gnt), .mem_resp_valid(b_resp_valid), .mem_resp_rdata(b_resp_rdata)
    );

    // ---- Arbiter (DMA priority over RISC) ----
    bram_arbiter #(
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ADDR_WIDTH (MEM_ADDR_WIDTH)
    ) u_arb (
        .clk(clk), .rst_n(rst_n),
        .a_req_valid(a_req_valid), .a_req_we(a_req_we), .a_req_addr(a_req_addr),
        .a_req_wdata(a_req_wdata), .a_req_wstrb(a_req_wstrb),
        .a_gnt(a_gnt), .a_resp_valid(a_resp_valid), .a_resp_rdata(a_resp_rdata),
        .b_req_valid(b_req_valid), .b_req_we(b_req_we), .b_req_addr(b_req_addr),
        .b_req_wdata(b_req_wdata), .b_req_wstrb(b_req_wstrb),
        .b_gnt(b_gnt), .b_resp_valid(b_resp_valid), .b_resp_rdata(b_resp_rdata),
        .mem_req_valid(mem_req_valid), .mem_req_we(mem_req_we),
        .mem_req_addr(mem_req_addr),   .mem_req_wdata(mem_req_wdata), .mem_req_wstrb(mem_req_wstrb),
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
        .req_addr(mem_req_addr),   .req_wdata(mem_req_wdata), .req_wstrb(mem_req_wstrb),
        .resp_valid(mem_resp_valid), .resp_rdata(mem_resp_rdata)
    );

endmodule

module dma_bram #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int STREAM_WIDTH   = 4,
    parameter int BRAM_DEPTH     = 48
)(
    input logic clk,
    input logic rst_n,

    // =========================================================================
    // 1. Host AXI4-Lite Slave Interface -> Controls DMA Configuration Registers
    // =========================================================================
    input  logic [AXI_ADDR_WIDTH-1:0] s_dma_axi_lite_awaddr,
    input  logic                      s_dma_axi_lite_awvalid,
    output logic                      s_dma_axi_lite_awready,

    input  logic [AXI_DATA_WIDTH-1:0] s_dma_axi_lite_wdata,
    input  logic                      s_dma_axi_lite_wvalid,
    output logic                      s_dma_axi_lite_wready,

    output logic [1:0]                s_dma_axi_lite_bresp,
    output logic                      s_dma_axi_lite_bvalid,
    input  logic                      s_dma_axi_lite_bready,

    input  logic [AXI_ADDR_WIDTH-1:0] s_dma_axi_lite_araddr,
    input  logic                      s_dma_axi_lite_arvalid,
    output logic                      s_dma_axi_lite_arready,

    output logic [AXI_DATA_WIDTH-1:0] s_dma_axi_lite_rdata,
    output logic [1:0]                s_dma_axi_lite_rresp,
    output logic                      s_dma_axi_lite_rvalid,
    input  logic                      s_dma_axi_lite_rready,

    // =========================================================================
    // 2. RISC CPU AXI4-Lite Slave Interface -> Direct Access to Shared BRAM
    // =========================================================================
    input  logic [AXI_ADDR_WIDTH-1:0] s_bram_axi_lite_awaddr,
    input  logic                      s_bram_axi_lite_awvalid,
    output logic                      s_bram_axi_lite_awready,

    input  logic [AXI_DATA_WIDTH-1:0] s_bram_axi_lite_wdata,
    input  logic [(AXI_DATA_WIDTH/8)-1:0] s_bram_axi_lite_wstrb,
    input  logic                      s_bram_axi_lite_wvalid,
    output logic                      s_bram_axi_lite_wready,

    output logic [1:0]                s_bram_axi_lite_bresp,
    output logic                      s_bram_axi_lite_bvalid,
    input  logic                      s_bram_axi_lite_bready,

    input  logic [AXI_ADDR_WIDTH-1:0] s_bram_axi_lite_araddr,
    input  logic                      s_bram_axi_lite_arvalid,
    output logic                      s_bram_axi_lite_arready,

    output logic [AXI_DATA_WIDTH-1:0] s_bram_axi_lite_rdata,
    output logic [1:0]                s_bram_axi_lite_rresp,
    output logic                      s_bram_axi_lite_rvalid,
    input  logic                      s_bram_axi_lite_rready,

    // =========================================================================
    // 3. AXI-Stream Accelerator Interfaces
    // =========================================================================
    // MM2S: DMA output stream (to processing block)
    output logic [STREAM_WIDTH-1:0]   m_axis_mm2s_tdata,
    output logic                      m_axis_mm2s_tvalid,
    input  logic                      m_axis_mm2s_tready,

    // S2MM: DMA input stream (from processing block)
    input  logic [STREAM_WIDTH-1:0]   s_axis_s2mm_tdata,
    input  logic                      s_axis_s2mm_tvalid,
    output logic                      s_axis_s2mm_tready
);

    // -------------------------------------------------------------------------
    // Internal AXI4 Full Master (DMA) -> Slave (Shared BRAM) Wires
    // -------------------------------------------------------------------------
    logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr;
    logic [7:0]                m_axi_awlen;
    logic [2:0]                m_axi_awsize;
    logic [1:0]                m_axi_awburst;
    logic                      m_axi_awvalid;
    logic                      m_axi_awready;

    logic [AXI_DATA_WIDTH-1:0] m_axi_wdata;
    logic [(AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb;
    logic                      m_axi_wvalid;
    logic                      m_axi_wlast;
    logic                      m_axi_wready;

    logic [1:0]                m_axi_bresp;
    logic                      m_axi_bvalid;
    logic                      m_axi_bready;

    logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0]                m_axi_arlen;
    logic [2:0]                m_axi_arsize;
    logic [1:0]                m_axi_arburst;
    logic                      m_axi_arvalid;
    logic                      m_axi_arready;

    logic [AXI_DATA_WIDTH-1:0] m_axi_rdata;
    logic [1:0]                m_axi_rresp;
    logic                      m_axi_rlast;
    logic                      m_axi_rvalid;
    logic                      m_axi_rready;

    // -------------------------------------------------------------------------
    // DMA Engine Instance
    // -------------------------------------------------------------------------
    dma #(
        .ADDR_WIDTH   (AXI_ADDR_WIDTH),
        .DATA_WIDTH   (AXI_DATA_WIDTH),
        .STREAM_WIDTH (STREAM_WIDTH)
    ) u_dma (
        .clk                   (clk),
        .rst_n                 (rst_n),

        // AXI4-Lite Control Registers Interface
        .s_axi_lite_awaddr     (s_dma_axi_lite_awaddr),
        .s_axi_lite_awvalid    (s_dma_axi_lite_awvalid),
        .s_axi_lite_awready    (s_dma_axi_lite_awready),
        .s_axi_lite_wdata      (s_dma_axi_lite_wdata),
        .s_axi_lite_wvalid     (s_dma_axi_lite_wvalid),
        .s_axi_lite_wready     (s_dma_axi_lite_wready),
        .s_axi_lite_bresp      (s_dma_axi_lite_bresp),
        .s_axi_lite_bvalid     (s_dma_axi_lite_bvalid),
        .s_axi_lite_bready     (s_dma_axi_lite_bready),
        .s_axi_lite_araddr     (s_dma_axi_lite_araddr),
        .s_axi_lite_arvalid    (s_dma_axi_lite_arvalid),
        .s_axi_lite_arready    (s_dma_axi_lite_arready),
        .s_axi_lite_rdata      (s_dma_axi_lite_rdata),
        .s_axi_lite_rresp      (s_dma_axi_lite_rresp),
        .s_axi_lite_rvalid     (s_dma_axi_lite_rvalid),
        .s_axi_lite_rready     (s_dma_axi_lite_rready),

        // AXI4 Master Memory Interface
        .m_axi_araddr          (m_axi_araddr),
        .m_axi_arlen           (m_axi_arlen),
        .m_axi_arsize          (m_axi_arsize),
        .m_axi_arburst         (m_axi_arburst),
        .m_axi_arvalid         (m_axi_arvalid),
        .m_axi_arready         (m_axi_arready),
        .m_axi_rdata           (m_axi_rdata),
        .m_axi_rresp           (m_axi_rresp),
        .m_axi_rlast           (m_axi_rlast),
        .m_axi_rvalid          (m_axi_rvalid),
        .m_axi_rready          (m_axi_rready),
        .m_axi_awaddr          (m_axi_awaddr),
        .m_axi_awlen           (m_axi_awlen),
        .m_axi_awsize          (m_axi_awsize),
        .m_axi_awburst         (m_axi_awburst),
        .m_axi_awvalid         (m_axi_awvalid),
        .m_axi_awready         (m_axi_awready),
        .m_axi_wdata           (m_axi_wdata),
        .m_axi_wstrb           (m_axi_wstrb),
        .m_axi_wvalid          (m_axi_wvalid),
        .m_axi_wlast           (m_axi_wlast),
        .m_axi_wready          (m_axi_wready),
        .m_axi_bresp           (m_axi_bresp),
        .m_axi_bvalid          (m_axi_bvalid),
        .m_axi_bready          (m_axi_bready),

        // Streaming Interfaces
        .m_axis_mm2s_tdata     (m_axis_mm2s_tdata),
        .m_axis_mm2s_tvalid    (m_axis_mm2s_tvalid),
        .m_axis_mm2s_tready    (m_axis_mm2s_tready),
        .s_axis_s2mm_tdata     (s_axis_s2mm_tdata),
        .s_axis_s2mm_tvalid    (s_axis_s2mm_tvalid),
        .s_axis_s2mm_tready    (s_axis_s2mm_tready)
    );

    // -------------------------------------------------------------------------
    // Shared BRAM Top Instance
    // -------------------------------------------------------------------------
    bram_axi_top #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .BRAM_DEPTH     (BRAM_DEPTH)
    ) u_bram_axi (
        .clk                  (clk),
        .rst_n                (rst_n),

        // AXI4 Slave Port (Connected to DMA Master)
        .s_axi_awaddr         (m_axi_awaddr),
        .s_axi_awlen          (m_axi_awlen),
        .s_axi_awsize         (m_axi_awsize),
        .s_axi_awburst        (m_axi_awburst),
        .s_axi_awvalid        (m_axi_awvalid),
        .s_axi_awready        (m_axi_awready),
        .s_axi_wdata          (m_axi_wdata),
        .s_axi_wstrb          (m_axi_wstrb),
        .s_axi_wlast          (m_axi_wlast),
        .s_axi_wvalid         (m_axi_wvalid),
        .s_axi_wready         (m_axi_wready),
        .s_axi_bresp          (m_axi_bresp),
        .s_axi_bvalid         (m_axi_bvalid),
        .s_axi_bready         (m_axi_bready),
        .s_axi_araddr         (m_axi_araddr),
        .s_axi_arlen          (m_axi_arlen),
        .s_axi_arsize         (m_axi_arsize),
        .s_axi_arburst        (m_axi_arburst),
        .s_axi_arvalid        (m_axi_arvalid),
        .s_axi_arready        (m_axi_arready),
        .s_axi_rdata          (m_axi_rdata),
        .s_axi_rresp          (m_axi_rresp),
        .s_axi_rlast          (m_axi_rlast),
        .s_axi_rvalid         (m_axi_rvalid),
        .s_axi_rready         (m_axi_rready),

        // AXI4-Lite Slave Port (Connected to RISC Interface)
        .s_axi_lite_awaddr    (s_bram_axi_lite_awaddr),
        .s_axi_lite_awvalid   (s_bram_axi_lite_awvalid),
        .s_axi_lite_awready   (s_bram_axi_lite_awready),
        .s_axi_lite_wdata     (s_bram_axi_lite_wdata),
        .s_axi_lite_wstrb     (s_bram_axi_lite_wstrb),
        .s_axi_lite_wvalid    (s_bram_axi_lite_wvalid),
        .s_axi_lite_wready    (s_bram_axi_lite_wready),
        .s_axi_lite_bresp     (s_bram_axi_lite_bresp),
        .s_axi_lite_bvalid    (s_bram_axi_lite_bvalid),
        .s_axi_lite_bready    (s_bram_axi_lite_bready),
        .s_axi_lite_araddr    (s_bram_axi_lite_araddr),
        .s_axi_lite_arvalid   (s_bram_axi_lite_arvalid),
        .s_axi_lite_arready   (s_bram_axi_lite_arready),
        .s_axi_lite_rdata     (s_bram_axi_lite_rdata),
        .s_axi_lite_rresp     (s_bram_axi_lite_rresp),
        .s_axi_lite_rvalid    (s_bram_axi_lite_rvalid),
        .s_axi_lite_rready    (s_bram_axi_lite_rready)
    );

endmodule