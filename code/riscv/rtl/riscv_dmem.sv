module riscv_dmem
#(
    parameter DEPTH = 1024,     // Number of 32-bit words
    parameter INIT_FILE = ""    // Memory preload file, empty = zero-filled
)(
    input               clk_i,
    input               rst_i,
    input        [31:0] addr_i,
    input        [31:0] wdata_i,
    input         [3:0] wstrb_i,
    
    output logic [31:0] rdata_o,              // Valid after 1 cycle after addr_i is applied
    output logic        error_unaligned_o,    // Misaligned access exception (1 cycle delay)
    output logic        error_out_of_bounds_o // Address >= DEPTH exception (1 cycle delay)
);

    // Memory array storage
    logic [31:0] mem [0:DEPTH - 1];

    // Preload/Zero initialize memory array
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
            // if no file given, mem starts as 'x (unknown) in simulation --
            // real hardware wouldn't guarantee zeros either, so for a clean
            // testbench you may want an else-branch that zero-fills instead:
        else
            for (int i = 0; i < DEPTH; i++) begin
                mem[i] = 32'b0;
            end
    end

    // Combinational address checking
    logic error_unaligned_w;
    logic error_out_of_bounds_w;

    assign error_unaligned_w     = (addr_i[1:0] != 2'b00);
    assign error_out_of_bounds_w = (addr_i[31:2] >= DEPTH);

    // Synchronous Read and Write Memory Operation (1 Cycle Latency) 
    always @(posedge clk_i) begin
        if (rst_i) begin
            rdata_o               <= 32'h0000_0000;
            error_unaligned_o     <= 1'b0;
            error_out_of_bounds_o <= 1'b0;
        end
        else begin
            // Register error status flags (aligned with 1-cycle data delay)
            error_unaligned_o     <= error_unaligned_w;
            error_out_of_bounds_o <= error_out_of_bounds_w;

            if (!error_unaligned_w && !error_out_of_bounds_w) begin
                if (wstrb_i[0])
                    mem[addr_i[31:2]][7:0]   <= wdata_i[7:0];
                if (wstrb_i[1])
                    mem[addr_i[31:2]][15:8]  <= wdata_i[15:8];
                if (wstrb_i[2])
                    mem[addr_i[31:2]][23:16] <= wdata_i[23:16];
                if (wstrb_i[3])
                    mem[addr_i[31:2]][31:24] <= wdata_i[31:24];

                // Read-During-Write
                rdata_o[7:0]   <= wstrb_i[0] ? wdata_i[7:0]   : mem[addr_i[31:2]][7:0];
                rdata_o[15:8]  <= wstrb_i[1] ? wdata_i[15:8]  : mem[addr_i[31:2]][15:8];
                rdata_o[23:16] <= wstrb_i[2] ? wdata_i[23:16] : mem[addr_i[31:2]][23:16];
                rdata_o[31:24] <= wstrb_i[3] ? wdata_i[31:24] : mem[addr_i[31:2]][31:24];
            end
            else begin
                rdata_o <= 32'h0000_0000;
            end
        end
    end
endmodule
