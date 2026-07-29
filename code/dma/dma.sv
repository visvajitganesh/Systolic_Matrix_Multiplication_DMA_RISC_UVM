`timescale 1ns / 1ps

module dma #(
parameter AXI_ADDR_WIDTH = 32,
parameter AXI_DATA_WIDTH = 32,
parameter STREAM_WIDTH   = 4
)(
input  logic  clk,
input  logic  rst,

input  logic [4:0]s_axi_lite_awaddr,
input  logic  s_axi_lite_awvalid,
output logic  s_axi_lite_awready,
input  logic [AXI_DATA_WIDTH-1:0] s_axi_lite_wdata,
input  logic  s_axi_lite_wvalid,
output logic  s_axi_lite_wready,
output logic [1:0]s_axi_lite_bresp,
output logic  s_axi_lite_bvalid,
input  logic  s_axi_lite_bready,

input  logic [4:0]s_axi_lite_araddr,
input  logic  s_axi_lite_arvalid,
output logic  s_axi_lite_arready,
output logic [AXI_DATA_WIDTH-1:0] s_axi_lite_rdata,
output logic [1:0]s_axi_lite_rresp,
output logic  s_axi_lite_rvalid,
input  logic  s_axi_lite_rready,

output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
output logic [7:0]m_axi_arlen,
output logic [2:0]m_axi_arsize,
output logic [1:0]m_axi_arburst,
output logic  m_axi_arvalid,
input  logic  m_axi_arready,

input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
input  logic [1:0]m_axi_rresp,
input  logic  m_axi_rlast,
input  logic  m_axi_rvalid,
output logic  m_axi_rready,

output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
output logic [7:0]m_axi_awlen,
output logic [2:0]m_axi_awsize,
output logic [1:0]m_axi_awburst,
output logic  m_axi_awvalid,
input  logic  m_axi_awready,

output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
output logic [(AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb,
output logic  m_axi_wlast,
output logic  m_axi_wvalid,
input  logic  m_axi_wready,

input  logic [1:0]m_axi_bresp,
input  logic  m_axi_bvalid,
output logic  m_axi_bready,


// MM2S 
output logic [STREAM_WIDTH-1:0]   m_axis_tdata,
output logic  m_axis_tvalid,
input  logic  m_axis_tready,

// S2MM 
input  logic [STREAM_WIDTH-1:0]   s_axis_tdata,
input  logic  s_axis_tvalid,
output logic  s_axis_tready
);


/////////////////////////////////////////////////////////////////////////
// Offset:
// 0x00: CTRL_REG  [0: Start Pulse, 1: Clear Status Flags]
// 0x04: STATUS[0: Busy Flag,   1: Done Flag (Polled by RISC-V)]
// 0x08: SRC_ADDR  [31:0] DDR Source Base Address
// 0x0C: DEST_ADDR [31:0] DDR Destination Base Address
// 0x10: XFER_LEN  [31:0] Total transfer size in bytes
/////////////////////////////////////////////////////////////////////////

logic [31:0] reg_ctrl;
logic [31:0] reg_status;
logic [31:0] reg_src_addr;
logic [31:0] reg_dest_addr;
logic [31:0] reg_trnsf_len;

logic start_pulse;
logic clear_status_pulse;
logic rd_done, wr_done;
logic active;


always_ff @(posedge clk or negedge rst) begin
 if (!rst) begin
  reg_ctrl <='0;
  reg_src_addr <='0;
  reg_dest_addr<='0;
  reg_trnsf_len <='0;
  s_axi_lite_awready <= 1'b0;
  s_axi_lite_wready<=1'b0;
  s_axi_lite_bvalid<=1'b0;
 end else begin
 if (~s_axi_lite_awready && s_axi_lite_awvalid && s_axi_lite_wvalid) begin
  s_axi_lite_awready <= 1'b1;
  s_axi_lite_wready<=1'b1;
  case (s_axi_lite_awaddr[4:0])
    5'h00: reg_ctrl<=s_axi_lite_wdata;
    5'h08: reg_src_addr<=s_axi_lite_wdata;
    5'h0C: reg_dest_addr <= s_axi_lite_wdata;
    5'h10: reg_trnsf_len<=s_axi_lite_wdata;
    default: ; 
  endcase
 end else begin
 s_axi_lite_awready <= 1'b0;
 s_axi_lite_wready<=1'b0;
end

if (s_axi_lite_awready && s_axi_lite_wready) begin
  s_axi_lite_bvalid <= 1'b1;
end else if (s_axi_lite_bready) begin
  s_axi_lite_bvalid <= 1'b0;
end

if (reg_ctrl[0]) reg_ctrl[0] <= 1'b0; 
if (reg_ctrl[1]) reg_ctrl[1] <= 1'b0; 
end
end

assign start_pulse= reg_ctrl[0];
assign clear_status_pulse = reg_ctrl[1];
assign s_axi_lite_bresp=2'b00; 
assign s_axi_lite_rresp=2'b00; 


always_ff @(posedge clk or negedge rst) begin
  if (!rst) begin
     s_axi_lite_arready <= 1'b0;
     s_axi_lite_rvalid<=1'b0;
     s_axi_lite_rdata <='0;
  end else begin
  if (~s_axi_lite_arready && s_axi_lite_arvalid) begin
     s_axi_lite_arready <= 1'b1;
     s_axi_lite_rvalid<=1'b1;
     case (s_axi_lite_araddr[4:0])
        5'h00: s_axi_lite_rdata <= reg_ctrl;
        5'h04: s_axi_lite_rdata <= reg_status; 
        5'h08: s_axi_lite_rdata <= reg_src_addr;
        5'h0C: s_axi_lite_rdata <= reg_dest_addr;
        5'h10: s_axi_lite_rdata <= reg_trnsf_len;
     endcase
   end else begin
        s_axi_lite_arready <= 1'b0;
        if (s_axi_lite_rready) s_axi_lite_rvalid <= 1'b0;
    end
  end
end

always_ff @(posedge clk or negedge rst) begin
  if (!rst) begin
    reg_status <= '0;
    active <= 1'b0;
  end else begin
  if (clear_status_pulse) begin
    reg_status <= '0;
  end else if (start_pulse) begin
    active<= 1'b1;
    reg_status[0] <= 1'b1; 
    reg_status[1] <= 1'b0;
  end else if (active && rd_done && wr_done) begin
   active<= 1'b0;
   reg_status[0] <= 1'b0; 
   reg_status[1] <= 1'b1; 
  end
 end
end


assign m_axi_arsize  = 3'b010; 
assign m_axi_arburst = 2'b01;  
assign m_axi_awsize  = 3'b010; 
assign m_axi_awburst = 2'b01;  
assign m_axi_wstrb   = 4'b1111;

// MM2S
typedef enum logic [1:0] {r_idle, r_addr, r_data, r_done} r_state_t;
r_state_t r_state;

logic [127:0] unpack_buf;  
logic [4:0]   unpack_elm_cnt;  
logic [31:0]  rd_bytes_left;
logic [1:0]   word_cnt;

assign m_axis_tdata  = unpack_buf[(unpack_elm_cnt * 4) +: 4];
assign m_axis_tvalid = (r_state == r_data) && (unpack_elm_cnt < 32);

always_ff @(posedge clk or negedge rst) begin
  if (!rst) begin
    r_state <= r_idle;
    m_axi_arvalid <=1'b0;
    m_axi_rready<= 1'b0;
    m_axi_araddr<= '0;
    m_axi_arlen <= 8'd0;
    unpack_elm_cnt <= '0;
    word_cnt<= '0;
    rd_done <= 1'b0;
  end else begin
  case (r_state)
  r_idle: begin
    rd_done <= 1'b0;
    if (start_pulse) begin
      m_axi_araddr<=reg_src_addr;
      rd_bytes_left <= reg_trnsf_len;
      r_state <=r_addr;
    end
   end

  r_addr: begin 
    m_axi_arvalid <= 1'b1;
    m_axi_arlen <=8'd3; 
    if (m_axi_arvalid && m_axi_arready) begin
      m_axi_arvalid <= 1'b0;
      m_axi_rready<=1'b1;
      word_cnt<='0;
      r_state <=r_data;
    end
   end

   r_data: begin
     if (m_axi_rvalid && m_axi_rready) begin
       unpack_buf[(word_cnt * 32) +: 32] <= m_axi_rdata;
       word_cnt <= word_cnt + 1'b1;
       if (m_axi_rlast) begin
         m_axi_rready<= 1'b0;
         unpack_elm_cnt <= '0;
       end
      end

     if (m_axis_tvalid && m_axis_tready) begin
       unpack_elm_cnt <= unpack_elm_cnt + 1'b1;
       if (unpack_elm_cnt == 5'd31) begin
         m_axi_araddr <= m_axi_araddr + 16;
         if (rd_bytes_left <= 16) begin
           rd_done <= 1'b1;
           r_state <= r_done;
         end else begin
           rd_bytes_left <= rd_bytes_left - 16;
           r_state <=r_addr;
         end
      end
    end
   end

   r_done: begin 
     r_state <= r_idle;
   end
endcase
end
end

//S2MM
typedef enum logic [2:0] {w_idle, w_pack, w_addr, w_data1,w_data2, w_resp, w_done} w_state_t;
w_state_t w_state;
    
 
logic [63:0] pack_buf;
logic [3:0] pack_elm_cnt;
logic [31:0] wr_byte_left;
    
assign s_axis_tready = (w_state==w_pack);

always_ff@(posedge clk or negedge rst) begin
  if(!rst) begin
    wr_done<=1'b0;
    m_axi_awaddr<='0;
    m_axi_bready<=1'b0;
    m_axi_awvalid<=1'b0;
    m_axi_wvalid<=1'b0;
    pack_elm_cnt<='0;
    m_axi_awlen <=8'b0;
  end else begin
    case(w_state)
      w_idle:begin
        wr_done<=1'b0;
        if(start_pulse) begin
          m_axi_awaddr<=reg_dest_addr;
          wr_byte_left<=reg_trnsf_len;
          w_state <= w_pack;
        end
      end
      
      w_pack: begin
        if(s_axis_tvalid && s_axis_tready) begin
          pack_buf[(pack_elm_cnt*4) +: 4] <= s_axis_tdata;
          pack_elm_cnt<=pack_elm_cnt+1;
          if(pack_elm_cnt==4'd15) begin
            w_state<=w_addr;
          end
        end
       end
       
       w_addr: begin
        m_axi_awvalid<=1'b1;
        m_axi_awlen<=8'd1;
        if(m_axi_awvalid && m_axi_awready) begin
          m_axi_awvalid<=1'b0;
          m_axi_wvalid<=1'b1;
          w_state<=w_data1;
        end
       end
       
       w_data1: begin
        m_axi_wdata<=pack_buf[31:0];
        m_axi_wlast<=1'b0;
        if(m_axi_wvalid && m_axi_wready) begin
          w_state<=w_data2;
        end
       end
       
       w_data2: begin
         m_axi_wdata<=pack_buf[63:32];
         m_axi_wlast<=1'b1;
         if(m_axi_wvalid && m_axi_wready) begin
            w_state<=w_resp; 
            m_axi_wvalid<=1'b0;
            m_axi_bready<=1'b1;
         end
       end
       
       w_resp: begin
         if(m_axi_bvalid && m_axi_bready) begin
           m_axi_bready<=1'b0;
           m_axi_awaddr<=m_axi_awaddr+16;
           if(wr_byte_left<=16) begin
             wr_done<=1'b1;
             w_state<=w_done;
           end else begin
             wr_byte_left<=wr_byte_left-16;
             w_state<=w_pack;
           end
         end
       end
       
       w_done: begin
         w_state<=w_idle;
       end
    endcase
  end
//  pack_buf[(pack_elm_cnt)*4 +:4] <= s_axis_tdata;
end
endmodule