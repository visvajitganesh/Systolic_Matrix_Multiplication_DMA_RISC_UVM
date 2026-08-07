module riscv_issue
(
    input                          clk_i,
    input                          rst_i,

    input                          squash_i,
    input                          stall_i,      // from downstream (e.g. LSU not ready) -- may not be needed yet, think about it

    // ---- from DECODE (combinational, this cycle) ----
    input                          valid_dec_i,
    input                   [31:0] pc_dec_i,
    input                    [4:0] rd_dec_i,
    input                    [4:0] rs1_dec_i,
    input                    [4:0] rs2_dec_i,
    input                          rd_valid_dec_i,
    input                          is_load_dec_i,
    input                          is_store_dec_i,
    input                          is_branch_dec_i,
    input        [`ALU_OP_W - 1:0] alu_op_dec_i,
    input                          alu_src_b_imm_dec_i,
    input                          alu_src_a_pc_dec_i,
    input                    [1:0] mem_size_dec_i,
    input                          mem_unsigned_dec_i,
    input                   [31:0] imm_dec_i,

    input                   [31:0] alu_result_exec_i,

    // ---- for the scoreboard + bypass: state of in-flight instructions ----
    input                          valid_mem_i,       // from riscv_pipe_ctrl
    input                    [4:0] rd_mem_i,
    input                          rd_valid_mem_i,
    
    input                   [31:0] alu_result_mem_i,  // for bypass (non-load only)
    input                          is_load_mem_i, 

    input                          valid_wb_i,
    input                    [4:0] rd_wb_i,
    input                          rd_valid_wb_i,
    input                   [31:0] result_wb_i,       // for bypass (loads AND alu -- already muxed)

    // ---- outputs ----
    output                         stall_o,      // tell FETCH/DECODE to freeze

    // registered, feeding EXECUTE next cycle
    output                         valid_exec_o,
    output                  [31:0] pc_exec_o,
    output                   [4:0] rd_exec_o,
    output                         rd_valid_exec_o,
    output                         is_load_exec_o,
    output                         is_store_exec_o,
    output logic [`ALU_OP_W - 1:0] alu_op_exec_o,
    output                  [31:0] operand_a_exec_o,   // rs1 value (bypassed) or PC
    output                  [31:0] operand_b_exec_o,   // rs2 value (bypassed) or imm
    output                  [31:0] store_data_exec_o,  // rs2 value (bypassed), for SW
    output                   [1:0] mem_size_exec_o,
    output                         mem_unsigned_exec_o
);

    // scoreboard

    logic [31:0] scoreboard;

    always_comb begin
        scoreboard = 32'b0;

        if (valid_exec_o && rd_valid_exec_o)
            scoreboard[rd_exec_o] = 1'b1;
        if (valid_mem_i && rd_valid_mem_i)
            scoreboard[rd_mem_i]  = 1'b1;
        if (valid_wb_i && rd_valid_wb_i)
            scoreboard[rd_wb_i]   = 1'b1;
    end

    assign stall_o = valid_dec_i && (scoreboard[rs1_dec_i] || scoreboard[rs2_dec_i] || (rd_valid_dec_i && scoreboard[rd_dec_i]));

    // forwarding 

    logic [31:0] raw_rs1_value;
    logic [31:0] raw_rs2_value;

    logic [31:0] bypassed_rs1;
    logic [31:0] bypassed_rs2;

    riscv_regfile #(
        .DATA_WIDTH(32)
    ) u_regfile (
        .clk_i       (clk_i),
        .rst_i       (rst_i),

        .rd0_i       (rd_wb_i),
        .rd0_value_i (result_wb_i),
        .rd0_wren_i  (valid_wb_i && rd_valid_wb_i),

        .ra0_i       (rs1_dec_i),
        .rb0_i       (rs2_dec_i),
        .ra0_value_o (raw_rs1_value),
        .rb0_value_o (raw_rs2_value) 
);

    always_comb begin
        bypassed_rs1 = raw_rs1_value;

        if (valid_wb_i && rd_valid_wb_i && (rd_wb_i == rs1_dec_i))
            bypassed_rs1 = result_wb_i;
        if (valid_mem_i && rd_valid_mem_i && !is_load_mem_i && (rd_mem_i == rs1_dec_i))
            bypassed_rs1 = alu_result_mem_i;
        if (valid_exec_o && rd_valid_exec_o && (rd_exec_o == rs1_dec_i))
            bypassed_rs1 = alu_result_exec_i;
    end

    always_comb begin
        bypassed_rs2 = raw_rs2_value;

        if (valid_wb_i && rd_valid_wb_i && (rd_wb_i == rs2_dec_i))
            bypassed_rs2 = result_wb_i;
        if (valid_mem_i && rd_valid_mem_i && !is_load_mem_i && (rd_mem_i == rs2_dec_i))
            bypassed_rs2 = alu_result_mem_i;
        if (valid_exec_o && rd_valid_exec_o && (rd_exec_o == rs2_dec_i))
            bypassed_rs2 = alu_result_exec_i;
    end

    // assign operand_a_exec_o = alu_src_a_pc_dec_i  ? pc_dec_i  : bypassed_rs1;
    // assign operand_b_exec_o = alu_src_b_imm_dec_i ? imm_dec_i : bypassed_rs2;

    // assign store_data_exec_o = bypass_rs2;

    // issue -> execute

    always_ff @(posedge clk_i or posedge rst_i)
        if (rst_i || squash_i) begin
            valid_exec_o        <= '0;
            pc_exec_o           <= '0;
            rd_exec_o           <= '0;
            rd_valid_exec_o     <= '0;
            is_load_exec_o      <= '0;
            is_store_exec_o     <= '0;
            alu_op_exec_o       <= '0;
            operand_a_exec_o    <= '0;
            operand_b_exec_o    <= '0;
            store_data_exec_o   <= '0;   
            mem_size_exec_o     <= '0;
            mem_unsigned_exec_o <= '0;
        end
        else if (!stall_o) begin 
            valid_exec_o        <= valid_dec_i;
            pc_exec_o           <= pc_dec_i;
            rd_exec_o           <= rd_dec_i;
            rd_valid_exec_o     <= rd_valid_dec_i;
            is_load_exec_o      <= is_load_dec_i;
            is_store_exec_o     <= is_store_dec_i;
            alu_op_exec_o       <= alu_op_dec_i;
            operand_a_exec_o    <= alu_src_a_pc_dec_i  ? pc_dec_i  : bypassed_rs1;
            operand_b_exec_o    <= alu_src_b_imm_dec_i ? imm_dec_i : bypassed_rs2;
            store_data_exec_o   <= bypassed_rs2;   // SW always wants raw rs2, not the muxed operand_b
            mem_size_exec_o     <= mem_size_dec_i;
            mem_unsigned_exec_o <= mem_unsigned_dec_i;
        end
        // else: stalled -- hold current values (implicit)

endmodule