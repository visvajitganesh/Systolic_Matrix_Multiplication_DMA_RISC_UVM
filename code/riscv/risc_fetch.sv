module riscv_fetch
(
    input          clk_i,
    input          rst_i,

    // Redirect from execute/branch-resolution stage.
    input          branch_taken_i,
    input   [31:0] branch_target_i,

    // Stall from downstream (scoreboard hazard. memory not ready. etc)
    input          stall_i,

    // Instruction memory interface
    output  [31:0] imem_addr_o,
    input   [31:0] imem_rdata_i,

    // To decode/issue
    output  [31:0] pc_o,    // this instruction's own PC (needed for AUIPC, JAL, branch target calc)
    output  [31:0] instr_o,
    output         valid_o
);

    logic [31:0] pc_q;      // address being requested THIS cycle
    logic [31:0] pc_e_q;    // address that corresponds to imem_rdata_i THIS cycle
    logic        valid_q;   // is that returned instruction actually good?

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            pc_q <= 32'h0;      //or your reset vector.
        else if (branch_taken_i)   
            pc_q <= branch_target_i;
        else if (!stall_i)
            pc_q <= pc_q + 32'd4;
        // else: stalled, keep re-requesting the same address -> hold pc_q unchanged
    end

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) 
            valid_q <= 1'b0;
        else if (!stall_i)
            valid_q <= 1'b1;
        // else: stalled -- hold valid_q as-is
    end

    always_ff @(posedge clk_i) begin
        if (!stall_i)
            pc_e_q <= pc_q;
        // else: stalled -- hold pc_e_q as-is, so it still matches whatever imem_rdata_i is holding stable
    end

    assign instr_o     = imem_rdata_i;
    assign imem_addr_o = pc_q;

    assign pc_o        = pc_e_q;
    assign valid_o     = valid_q;

endmodule   
