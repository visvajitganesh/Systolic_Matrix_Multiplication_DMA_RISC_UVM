module riscv_pipe_ctrl
(
    input                clk_i,
    input                rst_i,

    input                squash_i,            // comes from EXECUTE's own branch-resolution logic -- NEW instruction entering is wrong-path -- insert a bubble instead 

    // ---- inputs from EXECUTE (this cycle's freshly computed instruction) ----
    input                valid_exec_i,        // is there actually a real instruction in EXECUTE this cycle, or is this a bubble
    input        [31:0]  pc_exec_i,           // this instruction's own PC. Carried forward mainly for exception reporting / debug tracing
    input        [4:0]   rd_exec_i,           // the destination register index (instr[11:7]) for WB
    input                rd_valid_exec_i,     // does this instruction actually write a register at all? For WB
    input                is_load_exec_i,      // tells WB which of the two possible values (alu_result vs. mem_rdata) to select for rd
    input                is_store_exec_i,     // tells MEMORY whether it should actually perform a write to data memory this cycle
    
    input        [31:0]  alu_result_exec_i,   // ALU output -- doubles as the load/store address for LW/SW
    input        [31:0]  store_data_exec_i,   // rs2 value, for SW
    input        [1:0]   mem_size_exec_i,     // decoder's mem_size_o (byte/half/word)
    input                mem_unsigned_exec_i, // decode's mem_unsigned_o — needed by MEMORY (or WB)

    // ---- outputs: latched, one stage later, feeding MEMORY (external LSU reads these) ----
    // Every _mem_o output is just the registered, one-cycle-later copy of its matching _exec_i input
    output logic         valid_mem_o,         // is there actually a real instruction in EXECUTE this cycle
    output logic [31:0]  pc_mem_o,            // Registered pc_exec_i.
    output logic [4:0]   rd_mem_o,            // Registered rd_exec_i — destination index, now visible to MEMORY/WRITEBACK.
    output logic         rd_valid_mem_o,      // Registered rd_valid_exec_i.
    output logic         is_load_mem_o,       // Registered is_load_exec_i — used both by the external LSU (to know whether to actually read memory) and internally by hop 2's WB-value mux.
    output logic         is_store_mem_o,      // Registered is_store_exec_i — tells the external LSU whether to perform a write this cycle.
    output logic [31:0]  alu_result_mem_o,    // Registered alu_result_exec_i — for the LSU, this is the memory address to access; for non-memory instructions, this is the value hop 2 will select for rd.
    output logic [31:0]  store_data_mem_o,    // Registered store_data_exec_i — the data the external LSU should write into memory, if is_store_mem_o is set.
    output logic [1:0]   mem_size_mem_o,      // Registered mem_size_exec_i — tells the external LSU how many bytes to access.
    output logic         mem_unsigned_mem_o,  // Registered mem_unsigned_exec_i — tells the external LSU whether to sign- or zero-extend the loaded value before returning it.

    // ---- input: LSU's read dat, already sign/zero extended by LSU ----
    input        [31:0]  mem_rdata_i,         // The 32-bit value read from data memory this cycle by the external LSU, already sign/zero-extended according to mem_size_mem_o/mem_unsigned_mem_o. Only meaningful when is_load_mem_o is set — otherwise ignored.

    // ---- outputs: latched, feeding WRITEBACK ----
    output logic         valid_wb_o,          // Registered valid_mem_o — is there a real instruction now sitting in WRITEBACK, ready to commit? 
    output logic [31:0]  pc_wb_o,             // Registered pc_mem_o
    output logic [4:0]   rd_wb_o,             // Registered rd_mem_o — the register index WRITEBACK should write to.
    output logic         rd_valid_wb_o,       // Registered rd_valid_mem_o — gates whether WRITEBACK actually asserts the regfile's write-enable this cycle.
    output logic [31:0]  result_wb_o          // final muxed value: alu_result or mem_rdata 
);

    // ---- execute -> memory ----
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i || squash_i) begin
            valid_mem_o        <= '0;
            pc_mem_o           <= '0;
            rd_mem_o           <= '0;
            rd_valid_mem_o     <= '0;
            is_load_mem_o      <= '0;
            is_store_mem_o     <= '0;
            alu_result_mem_o   <= '0;
            store_data_mem_o   <= '0;
            mem_size_mem_o     <= '0;
            mem_unsigned_mem_o <= '0;
        end
        else begin
            valid_mem_o        <= valid_exec_i;
            pc_mem_o           <= pc_exec_i;
            rd_mem_o           <= rd_exec_i;
            rd_valid_mem_o     <= rd_valid_exec_i;
            is_load_mem_o      <= is_load_exec_i;
            is_store_mem_o     <= is_store_exec_i;
            alu_result_mem_o   <= alu_result_exec_i;
            store_data_mem_o   <= store_data_exec_i;
            mem_size_mem_o     <= mem_size_exec_i;
            mem_unsigned_mem_o <= mem_unsigned_exec_i;
        end
    end

    // ---- memory -> writeback ----
    // NOTE: no squash port here.

    logic [31:0] wb_value_c;

    assign wb_value_c = is_load_mem_o ? mem_rdata_i : alu_result_mem_o;

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            valid_wb_o    <= '0;
            pc_wb_o       <= '0;
            rd_wb_o       <= '0;
            rd_valid_wb_o <= '0;
            result_wb_o   <= '0;
        end
        else begin
            valid_wb_o    <= valid_mem_o;
            pc_wb_o       <= pc_mem_o;
            rd_wb_o       <= rd_mem_o;
            rd_valid_wb_o <= rd_valid_mem_o;
            result_wb_o   <= wb_value_c;
        end
    end

endmodule