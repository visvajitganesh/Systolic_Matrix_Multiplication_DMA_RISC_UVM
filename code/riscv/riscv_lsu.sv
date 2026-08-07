module riscv_lsu
(
    input                clk_i,
    input                rst_i,

    // from riscv_pipe_ctrl's MEMORY-stage outputs
    input                valid_mem_i,
    input                is_load_mem_i,
    input                is_store_mem_i,
    input        [31:0]  addr_mem_i,        // = alu_result_mem_o from pipe_ctrl
    input        [31:0]  store_data_mem_i,  // = store_data_mem_o from pipe_ctrl
    input        [1:0]   mem_size_mem_i,
    input                mem_unsigned_mem_i,

    // data memory interface
    output       [31:0]  dmem_addr_o,
    output       [31:0]  dmem_wdata_o,
    output       [3:0]   dmem_wstrb_o,   // byte-lane write-enable -- think about why this is 4 bits, not 1
    input        [31:0]  dmem_rdata_i,

    // back to riscv_pipe_ctrl
    output       [31:0]  mem_rdata_o      // = mem_rdata_i port on riscv_pipe_ctrl -- extended, ready to use
);

    always_comb begin
        dmem_addr_o = addr_mem_i;

        if (!is_store_mem_i) begin
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
                          endcase
                default : dmem_wstrb_o = '0; 
            endcase
        end


    end

    

endmodule
