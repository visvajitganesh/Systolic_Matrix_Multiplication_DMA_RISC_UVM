`timescale 1ns / 1ps

module dma #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter STREAM_WIDTH = 4
)(
    input  logic clk,  
    input  logic rst_n,    
    
    // AXI4-Lite Register Slave Interface

    // Write address 
    input  logic [ADDR_WIDTH - 1:0] s_axi_lite_awaddr,   // Write address from host
    input  logic                    s_axi_lite_awvalid,  // Write address valid
    output logic                    s_axi_lite_awready,  // DMA ready to accept write address

    // Write data 
    input  logic [DATA_WIDTH - 1:0] s_axi_lite_wdata,    // Write data from host
    input  logic                    s_axi_lite_wvalid,   // Write data valid
    output logic                    s_axi_lite_wready,   // DMA ready to accept write data

    // Write response 
    output logic [1:0]              s_axi_lite_bresp,    // Write response (OKAY/ERROR/etc.)
    output logic                    s_axi_lite_bvalid,   // Write response valid
    input  logic                    s_axi_lite_bready,   // Host ready to accept write response

    // Read address 
    input  logic [ADDR_WIDTH - 1:0] s_axi_lite_araddr,   // Read address from host
    input  logic                    s_axi_lite_arvalid,  // Read address valid
    output logic                    s_axi_lite_arready,  // DMA ready to accept read address

    // Read data 
    output logic [DATA_WIDTH - 1:0] s_axi_lite_rdata,    // Read data to host
    output logic [1:0]              s_axi_lite_rresp,    // Read response (OKAY/ERROR/etc.)
    output logic                    s_axi_lite_rvalid,   
    input  logic                    s_axi_lite_rready,  

    // AXI4 Master Interface (Memory Read & Write)

    // Read Address (AR) - asks for data from memory
    output logic [ADDR_WIDTH - 1:0]     m_axi_araddr,   
    output logic [7:0]                  m_axi_arlen,    // Burst length (beats - 1)
    output logic [2:0]                  m_axi_arsize,   // Bytes per beat (fixed to 4B here)
    output logic [1:0]                  m_axi_arburst,  // Burst type (fixed to INCR here)
    output logic                        m_axi_arvalid,  
    input  logic                        m_axi_arready,  

    // Read data  (R) - returns data requested via AR channel
    input  logic [DATA_WIDTH - 1:0]     m_axi_rdata,    // Read data from memory
    input  logic [1:0]                  m_axi_rresp,   
    input  logic                        m_axi_rlast,    // Indicates last beat of read burst
    input  logic                        m_axi_rvalid,  
    output logic                        m_axi_rready, 

    // Write address  (AW) - used by the S2MM write engine
    output logic [ADDR_WIDTH - 1:0]     m_axi_awaddr,  
    output logic [7:0]                  m_axi_awlen,    // Burst length (beats - 1)
    output logic [2:0]                  m_axi_awsize,   // Bytes per beat (fixed to 4B here)
    output logic [1:0]                  m_axi_awburst,  // Burst type (fixed to INCR here)
    output logic                        m_axi_awvalid, 
    input  logic                        m_axi_awready,  

    // Write data  (W) - carries the data being written
    output logic [DATA_WIDTH - 1:0]     m_axi_wdata,    
    output logic [(DATA_WIDTH/8) - 1:0] m_axi_wstrb,   
    output logic                        m_axi_wvalid,   
    output logic                        m_axi_wlast,   
    input  logic                        m_axi_wready,   
    
    // Write response (B) - completion/error status of the write
    input  logic [1:0]                  m_axi_bresp,    // Write response (error checking)
    input  logic                        m_axi_bvalid,  
    output logic                        m_axi_bready, 


    // AXI-Stream Accelerator Interfaces

    output logic [STREAM_WIDTH - 1:0]  m_axis_mm2s_tdata,   // 4-bit nibble output data
    output logic                       m_axis_mm2s_tvalid,  // Nibble data valid
    input  logic                       m_axis_mm2s_tready,  // Downstream accelerator ready

    // S2MM stream input: 4-bit nibbles coming in from accelerator, packed
    input  logic [STREAM_WIDTH - 1:0]  s_axis_s2mm_tdata,  
    input  logic                       s_axis_s2mm_tvalid, 
    output logic                       s_axis_s2mm_tready  
);

    // Dynamic sizing calculation parameters
    localparam int BYTES_PER_WORD    = DATA_WIDTH / 8;
    localparam int UNPACK_LIMIT      = DATA_WIDTH / STREAM_WIDTH;
    localparam int UNPACK_IDX_WIDTH  = $clog2(UNPACK_LIMIT);
    localparam int PACK_BUF_WIDTH    = DATA_WIDTH * 2;
    localparam int PACK_LIMIT        = PACK_BUF_WIDTH / STREAM_WIDTH;
    localparam int PACK_CNT_WIDTH    = $clog2(PACK_LIMIT + 1);

    // Register address map (byte offsets within the AXI-Lite address space)

    localparam ADDR_CTRL = 32'h00;  // Control register (bit0 = start)
    localparam ADDR_STAT = 32'h04;  // Status register (busy/done/error)
    localparam ADDR_SRC  = 32'h08;  // Source address 
    localparam ADDR_DEST = 32'h0C;  // Destination address 
    localparam ADDR_LEN  = 32'h10;  // Transfer length register (in bytes)

    localparam [2:0] AXSIZE_BYTES = $clog2(BYTES_PER_WORD); // 2^2 = 4 bytes/beat (word-sized beats)
    localparam [1:0] AXBURST_INCR = 2'b01;  // INCR burst type (incrementing address)

    // since this DMA only ever transfers 32-bit words in incrementing bursts.
    assign m_axi_arsize  = AXSIZE_BYTES;
    assign m_axi_arburst = AXBURST_INCR;
    assign m_axi_awsize  = AXSIZE_BYTES;
    assign m_axi_awburst = AXBURST_INCR;

    // Memory-mapped configuration/status registers (written/read via AXI-Lite)
    logic [DATA_WIDTH - 1:0] reg_ctrl;         // Holds last value written to CTRL register
    logic [DATA_WIDTH - 1:0] reg_status;       // Live status: bit0=busy, bit1=done, bit2=error
    logic [DATA_WIDTH - 1:0] reg_src_addr;   
    logic [DATA_WIDTH - 1:0] reg_dest_addr; 
    logic [DATA_WIDTH - 1:0] reg_xfer_len;     // Number of bytes to transfer
    logic [DATA_WIDTH - 2:0] reg_wr_xfer_len;

    logic start_pulse;         // One-cycle pulse asserted when CTRL[0] is written as 1
    logic rd_done, wr_done;   
    logic rd_error, wr_error;  
    logic busy;                // busy is simply bit 0 of the status register      
    
    assign busy = reg_status[0];                 // Sets Busy=1 when a transfer starts, and updates Done/Error/Busy
    assign reg_wr_xfer_len = reg_xfer_len >> 1;  // Stores half of amount of data received from memory into memory
    
    // Status Register Update

    always_ff @(posedge clk or negedge rst_n) begin                                      /////////
        if (!rst_n) begin                                                                       //  
            reg_status <= 32'h0;      // On reset: not busy, not done, no error                 //   
        end                                                                                     //
        else begin                                                                              //   
            if (start_pulse) begin                                                              //   
                reg_status <= 32'h1;  // Set Busy = 1, Done = 0                                 //  
            end                                                                                 //
            else if (rd_done && wr_done) begin                                              /////// Status logic (reg_status) used for polling   
                // Both engines finished: clear busy, set done, report error if any             //
                reg_status <= {{(DATA_WIDTH - 3){1'b0}}, (rd_error || wr_error), 1'b1, 1'b0};   //   
                // bit0=Busy(0), bit1=Done(1), bit2=Error                                       //   
            end                                                                                 //   
            // otherwise (mid-transfer, not yet done): hold current status value                //
        end                                                                                     //   
    end                                                                                  /////////
  
  
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
        end 
        else begin
            start_pulse <= 1'b0; // Pulse self-clears every cycle unless re-asserted below
            
            if (s_axi_lite_awvalid && s_axi_lite_wvalid && !s_axi_lite_bvalid) begin
                // Single-cycle handshake: assert AWREADY/WREADY for this beat
                s_axi_lite_awready <= 1'b1;
                s_axi_lite_wready  <= 1'b1;

                case (s_axi_lite_awaddr[7:0])
                    ADDR_CTRL: begin
                        reg_ctrl <= s_axi_lite_wdata;
                        if (s_axi_lite_wdata[0]) 
                            start_pulse <= 1'b1;
                    end
                    ADDR_SRC:  reg_src_addr  <= s_axi_lite_wdata; 
                    ADDR_DEST: reg_dest_addr <= s_axi_lite_wdata; 
                    ADDR_LEN:  reg_xfer_len  <= s_axi_lite_wdata; 
                endcase

                // Issue the write response (assume OKAY, since bresp stays 2'b00)
                s_axi_lite_bvalid <= 1'b1;
            end 
            else begin
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
        end 
        else begin
            if (s_axi_lite_arvalid && !s_axi_lite_rvalid) begin
                s_axi_lite_arready <= 1'b1; 
                s_axi_lite_rvalid  <= 1'b1;

                case (s_axi_lite_araddr[7:0])
                    ADDR_CTRL:  s_axi_lite_rdata <= reg_ctrl;
                    ADDR_STAT:  s_axi_lite_rdata <= reg_status;
                    ADDR_SRC :  s_axi_lite_rdata <= reg_src_addr;
                    ADDR_DEST:  s_axi_lite_rdata <= reg_dest_addr;
                    ADDR_LEN :  s_axi_lite_rdata <= reg_xfer_len;
                    default  :  s_axi_lite_rdata <= 32'h0;
                endcase
            end 
            else begin        
                s_axi_lite_arready <= 1'b0;
            end


            if (s_axi_lite_rvalid && s_axi_lite_rready) begin
                s_axi_lite_rvalid  <= 1'b0;
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
   
    logic [DATA_WIDTH - 1:0]        rd_buf;         
    logic [DATA_WIDTH - 1:0]        rd_bytes_left;  
    logic [UNPACK_IDX_WIDTH - 1:0]  unpack_idx;   

    assign m_axis_mm2s_tdata = rd_buf[(unpack_idx * STREAM_WIDTH) +: STREAM_WIDTH];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_araddr       <= '0;
            m_axi_arlen        <= '0;
            m_axi_arvalid      <= 1'b0;
            m_axi_rready       <= 1'b0;
            m_axis_mm2s_tvalid <= 1'b0;

            rd_done            <= 1'b0;
            rd_error           <= 1'b0;
            unpack_idx         <= '0;
            rd_bytes_left      <= '0;
            r_state            <= R_IDLE;
        end 
        else begin
            case (r_state)

                // Wait for the host to trigger a new transfer via CTRL register
                R_IDLE: begin
                    if (start_pulse) begin
                        m_axi_araddr  <= reg_src_addr;  
                        rd_bytes_left <= reg_xfer_len; 
                        rd_done       <= 1'b0;           
                        rd_error      <= 1'b0;        
                        r_state       <= R_ADDR;        
                    end
                end

                // Issue a single-beat (4-byte) read request on the AR channel
                R_ADDR: begin
                    m_axi_arvalid <= 1'b1;
                    m_axi_arlen   <= 8'd0;       // Single beat read (arsize=4B, arburst=INCR)

                    // Wait for the AXI slave/memory to accept the address
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;   // Address accepted; drop ARVALID
                        m_axi_rready  <= 1'b1;   // Now ready to receive the read data
                        r_state       <= R_DATA;
                    end
                end

                // Wait for the read data (R channel) to come back from memory
                R_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        rd_buf       <= m_axi_rdata;             // Latch the word read
                        
                        if (m_axi_rresp != 2'b00) 
                            rd_error <= 1'b1; 

                        m_axi_rready <= 1'b0;                
                        unpack_idx   <= '0;                    
                        r_state      <= R_UNPACK;
                    end
                end

                R_UNPACK: begin
                    m_axis_mm2s_tvalid <= 1'b1;

                    if (m_axis_mm2s_tvalid && m_axis_mm2s_tready) begin
                        if (unpack_idx == (UNPACK_LIMIT - 1)) begin               // Transmitted 8 nibbles (4 bytes)
                            m_axis_mm2s_tvalid <= 1'b0;
                            m_axi_araddr       <= m_axi_araddr + BYTES_PER_WORD; // Advance to next word

                            if (rd_bytes_left <= BYTES_PER_WORD) begin           // This was the last word of the transfer
                                rd_done <= 1'b1;
                                r_state <= R_DONE;
                            end 
                            else begin
                                rd_bytes_left <= rd_bytes_left - BYTES_PER_WORD; // More words remain: fetch the next one
                                r_state       <= R_ADDR;
                            end
                        end 
                        else begin
                            unpack_idx <= unpack_idx + 1'b1;        // Advance to the next nibble within the current word
                        end
                    end
                end

                R_DONE: begin
                    m_axis_mm2s_tvalid <= 1'b0;
                    if (!busy) begin
                        r_state        <= R_IDLE;
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

    // parameterize these
    logic [PACK_BUF_WIDTH - 1:0] pack_buf;        // Holds 16 packed nibbles (8 bytes = 2 words)
    logic [PACK_CNT_WIDTH - 1:0] pack_elm_cnt;    // Count of nibbles packed so far (0-15)
    logic [DATA_WIDTH - 1:0]     wr_bytes_left;  

    assign s_axis_s2mm_tready = (w_state == W_PACK); // Only accept incoming stream data while actively packing (W_PACK state)

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axi_awaddr  <= '0;
            m_axi_awlen   <= '0;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata   <= '0;
            m_axi_wstrb   <= '0;
            m_axi_wvalid  <= 1'b0;
            m_axi_wlast   <= 1'b0;
            m_axi_bready  <= 1'b0;

            pack_elm_cnt  <= '0;
            pack_buf      <= '0;
            wr_bytes_left <= '0;

            wr_done       <= 1'b0;
            wr_error      <= 1'b0;
            w_state       <= W_IDLE;
        end 
        else begin
            case (w_state)

                // Wait for the host to trigger a new transfer via CTRL register
                W_IDLE: begin
                    wr_done  <= 1'b0;   // Clear completion flag
                    wr_error <= 1'b0;   // Clear error flag

                    if (start_pulse) begin
                        m_axi_awaddr  <= reg_dest_addr;  
                        wr_bytes_left <= {1'b0, reg_wr_xfer_len}; 
                        pack_elm_cnt  <= '0;  
                        w_state       <= W_PACK;
                    end
                end
                
                
                // pack_buf (LSB-first), 4 bits at a time.
                W_PACK: begin
                    if (s_axis_s2mm_tvalid && s_axis_s2mm_tready) begin
                        pack_buf[(pack_elm_cnt * STREAM_WIDTH) +: STREAM_WIDTH] <= s_axis_s2mm_tdata;
                        pack_elm_cnt                                            <= pack_elm_cnt + 1'b1;

                        // Check if we packed 16 nibbles (8 bytes) or reached full length
                        if (pack_elm_cnt == (PACK_LIMIT - 1)) begin
                            w_state <= W_ADDR;       // Buffer full (64 bits / 2 words): ready to write it out
                        end
                    end
                end

                // Issue a 2-beat (8-byte) write request on the AW channel
                W_ADDR: begin
                    m_axi_awvalid <= 1'b1;
                    m_axi_awlen   <= 8'd1; // 2-beat burst = 8 bytes (awsize = 4B, awburst = INCR)

                    // Wait for the AXI slave/memory to accept the write address
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;    
                        m_axi_wvalid  <= 1'b1;           // Start sending write data
                        m_axi_wdata   <= pack_buf[DATA_WIDTH - 1:0]; 
                        m_axi_wstrb   <= '1;        // full 32-bit word, all lanes valid
                        m_axi_wlast   <= 1'b0;     

                        w_state       <= W_DATA;
                    end
                end

                // Send the two write-data beats (lower word, then upper word)
                W_DATA: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (!m_axi_wlast) begin
                            // First beat was accepted: send the second (last) beat
                            m_axi_wdata <= pack_buf[(DATA_WIDTH * 2) - 1 : DATA_WIDTH]; // Second beat: upper 32 bits
                            m_axi_wstrb <= '1;
                            m_axi_wlast <= 1'b1;
                        end 
                        else begin
                            m_axi_wvalid <= 1'b0;
                            m_axi_wstrb  <= '0;
                            m_axi_wlast  <= 1'b0;
                            m_axi_bready <= 1'b1;
                            w_state      <= W_RESP;
                        end
                    end
                end

                // Wait for the write response (B channel) from memory
                W_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        if (m_axi_bresp != 2'b00) 
                            wr_error <= 1'b1;             // Flag AXI write errors

                        m_axi_bready <= 1'b0;
                        m_axi_awaddr <= m_axi_awaddr + (BYTES_PER_WORD * 2); // Offset dest address by 8 bytes

                        if (wr_bytes_left <= (BYTES_PER_WORD * 2)) begin
                            // This was the last burst of the transfer
                            wr_done <= 1'b1;
                            w_state <= W_DONE;
                        end 
                        else begin
                            wr_bytes_left <= wr_bytes_left - (BYTES_PER_WORD * 2);
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
