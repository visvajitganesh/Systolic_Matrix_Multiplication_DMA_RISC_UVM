

`include "riscv_defs.sv"

module riscv_lsu
(
    input               clk_i,
    input               rst_i,

    input               stall_i,           // AXI transaction pending -- freeze the registers

    // from riscv_pipe_ctrl's MEMORY-stage outputs
    input               valid_mem_i,
    input               is_load_mem_i,
    input               is_store_mem_i,
    input        [31:0] addr_mem_i,        // = alu_result_mem_o from pipe_ctrl
    input        [31:0] store_data_mem_i,  // = store_data_mem_o from pipe_ctrl
    input        [1:0]  mem_size_mem_i,
    input               mem_unsigned_mem_i,

    // data memory interface
    output       [31:0] dmem_addr_o,
    output       [31:0] dmem_wdata_o,
    output        [3:0] dmem_wstrb_o,   // byte-lane write-enable -- think about why this is 4 bits, not 1
    input        [31:0] dmem_rdata_i,

    // back to riscv_pipe_ctrl
    output       [31:0] mem_rdata_o      // = mem_rdata_i port on riscv_pipe_ctrl -- extended, ready to use
);
    assign dmem_addr_o = addr_mem_i;

    always_comb begin

        if (!valid_mem_i || !is_store_mem_i) begin
            dmem_wstrb_o = 4'b0000;
        end
        else begin
            case(mem_size_mem_i)
                2'b10   : dmem_wstrb_o = 4'b1111;
                2'b01   : dmem_wstrb_o = addr_mem_i[1] ? 4'b1100 : 4'b0011;
                2'b00   : case (addr_mem_i[1:0])
                            2'b00   : dmem_wstrb_o = 4'b0001;
                            2'b01   : dmem_wstrb_o = 4'b0010;
                            2'b10   : dmem_wstrb_o = 4'b0100;
                            2'b11   : dmem_wstrb_o = 4'b1000;
                            default : dmem_wstrb_o = 4'b0000;
                          endcase
                default : dmem_wstrb_o = '0; 
            endcase
        end

        if (!valid_mem_i || !is_store_mem_i) begin
            dmem_wdata_o = 'b0;
        end
        else begin
            case(mem_size_mem_i)
                2'b10   : dmem_wdata_o = store_data_mem_i;
                2'b01   : dmem_wdata_o = {2{store_data_mem_i[15:0]}};
                2'b00   : dmem_wdata_o = {4{store_data_mem_i[7:0]}};
                default : dmem_wdata_o = '0; 
            endcase
        end

    end

    logic       valid_mem_q;
    logic       is_load_mem_q;

    logic [1:0] mem_size_q;
    logic       mem_unsigned_q;
    logic [1:0] addr_lsb_q;

    logic [7:0]  byte_sel;
    logic [15:0] half_sel;

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            valid_mem_q    <= 1'b0;
            is_load_mem_q  <= 1'b0;
            mem_size_q     <= '0;
            mem_unsigned_q <= '0;
            addr_lsb_q     <= '0;
        end
        else if (stall_i) begin
            // AXI transaction still pending -- keep remembering the
            // ORIGINAL access's metadata, don't let it drift onto whatever
            // riscv_pipe_ctrl happens to be holding this cycle.
        end
        else begin
            valid_mem_q    <= valid_mem_i;
            is_load_mem_q  <= is_load_mem_i;
            mem_size_q     <= mem_size_mem_i;
            mem_unsigned_q <= mem_unsigned_mem_i;
            addr_lsb_q     <= addr_mem_i[1:0];
        end
    end

    always_comb begin
        case (addr_lsb_q)
            2'b00   : byte_sel = dmem_rdata_i[7:0];
            2'b01   : byte_sel = dmem_rdata_i[15:8];
            2'b10   : byte_sel = dmem_rdata_i[23:16];
            2'b11   : byte_sel = dmem_rdata_i[31:24];
            default : byte_sel = dmem_rdata_i[7:0];
        endcase

        half_sel = addr_lsb_q[1] ? dmem_rdata_i[31:16] : dmem_rdata_i[15:0];

        if (valid_mem_q && is_load_mem_q) begin
            case (mem_size_q)
                2'b00   : mem_rdata_o = mem_unsigned_q ? {24'b0, byte_sel} : {{24{byte_sel[7]}}, byte_sel};
                2'b01   : mem_rdata_o = mem_unsigned_q ? {16'b0, half_sel} : {{16{half_sel[15]}}, half_sel};
                2'b10   : mem_rdata_o = dmem_rdata_i;
                default : mem_rdata_o = dmem_rdata_i;
            endcase
        end
        else begin
            mem_rdata_o = '0;
        end
    end
     
endmodule