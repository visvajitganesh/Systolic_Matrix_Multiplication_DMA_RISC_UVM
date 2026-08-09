module riscv_axi_lite_bridge #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    input logic                     clk_i,
    input logic                     rst_i,

    // Core LSU Interface
    input  logic                    valid_mem_i,
    input  logic                    is_load_mem_i,
    input  logic                    is_store_mem_i,
    input  logic [ADDR_WIDTH - 1:0] addr_mem_i,
    input  logic [DATA_WIDTH - 1:0] wdata_mem_i,
    input  logic              [3:0] wstrb_mem_i,
    output logic [DATA_WIDTH - 1:0] rdata_mem_o,
    output logic                    stall_o,        // Stalls core during pending AXI transaction

    // AXI4-Lite Master Interface

    // Write Address Channel
    output logic [ADDR_WIDTH - 1:0] m_axi_lite_awaddr,
    output logic              [2:0] m_axi_lite_awprot,
    output logic                    m_axi_lite_awvalid,
    input  logic                    m_axi_lite_awready,

    // Write Data Channel
    output logic [DATA_WIDTH - 1:0] m_axi_lite_wdata,
    output logic              [3:0] m_axi_lite_wstrb,
    output logic                    m_axi_lite_wvalid,
    input  logic                    m_axi_lite_wready,

    // Write Response Channel
    input  logic              [1:0] m_axi_lite_bresp,
    input  logic                    m_axi_lite_bvalid,
    output logic                    m_axi_lite_bready,

    // Read Address Channel
    output logic [ADDR_WIDTH - 1:0] m_axi_lite_araddr,
    output logic              [2:0] m_axi_lite_arprot,
    output logic                    m_axi_lite_arvalid,
    input  logic                    m_axi_lite_arready,

    // Read Data Channel
    input  logic [DATA_WIDTH - 1:0] m_axi_lite_rdata,
    input  logic              [1:0] m_axi_lite_rresp,
    input  logic                    m_axi_lite_rvalid,
    output logic                    m_axi_lite_arready
);

    typedef enum logic [1:0] {
        IDLE,
        READ,
        WRITE,
        WRITE_RESP
    } state_t;

    state_t curremt_state, next_state;

    logic aw_done_q, w_done_q;

    // Output Assignments
    assign m_axi_lite_awprot = 3'b000;
    assign m_axi_lite_arprot = 3'b000;
    assign rdata_mem_o       = m_axi_lite_rdata;

    // Combinational logic: Output signals and Next State computation

    always_comb begin
        next_state         = current_state;
        m_axi_lite_awvalid = 1'b0;
        m_axi_lite_awaddr  = addr_mem_i;
        m_axi_lite_wvalid  = 1'b0;
        m_axi_lite_wdata   = wdata_mem_i;
        m_axi_lite_wstrb   = wstrb_mem_i;
        m_axi_lite_bready  = 1'b0;
        m_axi_lite_arvalid = 1'b0;
        m_axi_lite_araddr  = addr_mem_i;
        m_axi_lite_rready  = 1'b0;
        stall_o            = 1'b0;  

        case (current_state)
            IDLE       : begin
                if (valid_mem_i) begin
                    if (is_load_mem_i) begin
                        m_axi_lite_arvalid = 1'b1;
                        stall_o            = 1'b1;

                        if (m_axi_lite_arready) begin
                            next_state = READ;
                        end
                    end

                    else if (is_store_mem_i) begin
                        m_axi_lite_awvalid = 1'b1;
                        m_axi_lite_wvalid  = 1'b1;
                        stall_o            = 1'b1;
                        next_state         = WRITE;
                    end
                end
            end

            READ       : begin
                stall_o           = 1'b1;
                m_axi_lite_rready = 1'b1;

                if (m_axi_lite_rvalid) begin
                    stall_o    = 1'b1;
                    next_state = IDLE;
                end
            end

            WRITE      : begin
                stall_o            = 1'b1;
                m_axi_lite_awvalid = !aw_done_q;
                m_axi_lite_wvalid  = !w_done_q;

                if ((m_axi_lite_awready || aw_done_q) && (m_axi_lite_wready || w_done_q)) begin
                    next_state = WRITE_RESP;
                end
            end

            WRITE_RESP : begin
                stall_o = 1'b1;
                m_axi_lite_bready = 1'b1;

                if (m_axi_lite_bvalid) begin
                    stall_o    = 1'b0;
                    next_state = IDLE;
                end
            end

            default    : next_state = IDLE;
        endcase
    end

    // Sequnetial logic: State register and write handshake tracking
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            current_state <= IDLE;
            aw_done_q     <= 1'b0;
            w_done_q      <= 1'b0;
        end
        else begin
            current_state <= next_state;

            if (current_state == WRITE) begin
                if (m_axi_lite_awvalid && m_axi_lite_awready)
                    aw_done_q <= 1'b1;
                
                if (m_axi_lite_wvalid && m_axi_lite_wready)
                    w_done_q  <= 1'b1; 
            end
            else begin
                aw_done_q <= 1'b0;
                w_done_q  <= 1'b0;
            end
        end
    end

endmodule