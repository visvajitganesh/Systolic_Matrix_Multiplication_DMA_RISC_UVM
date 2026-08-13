/*
Branch signal -> chnage direction of the pc
Sqaush signal -> invalidate the instruction itself
Stall signal  -> hold the pc value
*/
`include "riscv_defs.sv"

module riscv_fetch
(
    input                clk_i,
    input                rst_i,

    // Redirect from execute/branch-resolution stage.
    input                branch_taken_i,
    input         [31:0] branch_target_i,
    input                squash_i,

    // Stall from downstream (scoreboard hazard. memory not ready. etc)
    input                stall_i,

    // Instruction memory interface
    output        [31:0] imem_addr_o,
    input         [31:0] imem_rdata_i,

    // To decode/issue --- all three will arrive at the same cycle
    output        [31:0] pc_o,    // this instruction's own PC (needed for AUIPC, JAL, branch target calc)
    output  logic [31:0] instr_o,
    output               valid_o
);

    logic [31:0] pc_q;      // address being requested THIS cycle
    logic [31:0] pc_e_q;    // address that corresponds to imem_rdata_i THIS cycle
    logic        valid_q;   // is that returned instruction actually good?

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            pc_q <= 32'h0;            
        else if (branch_taken_i)   
            pc_q <= branch_target_i;
        // else if (!stall_i)              // (*) 
        else if (!stall_i && !squash_i)
            pc_q <= pc_q + 32'd4;
        // else: stalled, keep re-requesting the same address -> hold pc_q unchanged
    end

    /*
    (*) When squash_i is asserted without branch_taken_i, the pipeline flushes the current instruction
    but does not redirect to a new address. pc_q must hold its value during a squash so that it
    re-requests the squashed/next valid PC once the flush bubble clears
    */

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) 
            valid_q <= 1'b0;
        else if (squash_i || branch_taken_i)  // Instr previous to this has already been fired -- make it invalid
            valid_q <= 1'b0;
        else if (!stall_i)
            valid_q <= 1'b1;
        // else: stalled -- hold valid_q as-is
    end

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            pc_e_q <= 32'h0;
        else if (!stall_i)
            pc_e_q <= pc_q;
        // else: stalled -- hold pc_e_q as-is, so it still matches whatever imem_rdata_i is holding stable
    end

    // Skid buffer control state

    logic [31:0] instr_buff_q;  // Saved instruction captured during stall
    logic        use_buff_q;    // Want the stall_i to affect on the next immediate cycle 
    
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            use_buff_q <= 1'b0;
        else if (squash_i || branch_taken_i)  // (*)    
            use_buff_q <= 1'b0;
        else
            use_buff_q <= stall_i;
    end

    /*
    (*)  If stall arrives at the same time as branch/squash -- to see its effect.
    If you remove that line, it doesnt make the behavior wrong.
    Explicitly invalidate skid buffer selection on flush.
    It guarantees that as soon as the flush happens, instr_o stops outputting wrong-path buffer data 
    and immediately reflects live memory data (imem_rdata_i) for the new target.
    */

    // Latch instruction on first cycle of a stall (no reset needed on datapath)
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            instr_buff_q <= '0;
        else if (stall_i && !use_buff_q)
            instr_buff_q <= imem_rdata_i;
    end
    
    // assign instr_o = stall_i ? instr_hold_q : imem_rdata_i;   // It changes the instr midway whenever stall_i arrives
    assign instr_o = use_buff_q ? instr_buff_q : imem_rdata_i;
    assign pc_o    = pc_e_q;

    assign imem_addr_o = pc_q;
    assign valid_o     = valid_q;

endmodule 

/*
Extra Comments:
assign instr_o     = imem_rdata_i; doesnt work when there is a stall.
pc_o(pc_e_q) stalls but instr_o doesnt because i-memory is already processing 
what was there in pc_q which gets reflected. Hence buffer is needed.
*/
