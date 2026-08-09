module riscv_core #( 
    parameter logic [31:0] DMEM_BASE = 32'h0000_0000,
    parameter logic [31:0] DMEM_SIZE = 32'h0000_1000  // 4KB local memory 
)(
    input       clk_i,
    input       rst_i,

    // Master AXI4-Lite Ports to connect to DMA/Peripherals
    output logic [31:0] m_axi_lite_awaddr,
    output logic  [2:0] m_axi_lite_awprot,
    output logic        m_axi_lite_awvalid,
    input               m_axi_lite_awready,

    output logic [31:0] m_axi_lite_wdata,
    output logic  [3:0] m_axi_lite_wstrb,
    output logic        m_axi_lite_wvalid,
    input               m_axi_lite_wready,

    input         [1:0] m_axi_lite_bresp,
    input               m_axi_lite_bvalid,
    output logic        m_axi_lite_bready,

    output logic [31:0] m_axi_lite_araddr,
    output logic  [2:0] m_axi_lite_arprot,
    output logic        m_axi_lite_arvalid,
    input               m_axi_lite_arready,

    input               m_axi_lite_rdata,
    input               m_axi_lite_rresp,
    input               m_axi_lite_rvalid,
    output logic        m_axi_lite_rready
);

    // Cross-cutting signals
    logic        squash_w;         // driven by branch resolution 
    logic        branch_taken_w;   // driven by branch resolution
    logic [31:0] branch_target_w;  // driven by branch resolution 
    logic        issue_stall_w;    // driven by riscv_issue 
    logic        axi_stall_w;

    // Instruction Memory
    logic [31:0] imem_addr_w;
    logic [31:0] imem_rdata_w;     // driven by instruction memory

    riscv_imem #(
        .INIT_FILE("code.hex")
    ) u_imem (
        .clk_i   (clk_i),
        .addr_i  (imem_addr_w),
        .rdata_o (imem_rdata_w)
    );

    // Fetch Unit
    logic [31:0] fetch_pc_w;
    logic [31:0] fetch_instr_w;
    logic        fetch_valid_w;

    riscv_fetch u_fetch
    (
        .clk_i            (clk_i),
        .rst_i            (rst_i),
        .branch_taken_i   (branch_taken_w),
        .branch_target_i  (branch_target_w),
        .squash_i         (squash_w),
        .stall_i          (issue_stall_w || axi_stall_w),
        .imem_addr_o      (imem_addr_w),
        .imem_rdata_i     (imem_rdata_w),
        .pc_o             (fetch_pc_w),
        .instr_o          (fetch_instr_w),
        .valid_o          (fetch_valid_w)
    );

    // Decode unit
    logic                   dec_is_alu_w, dec_is_load_w, dec_is_store_w, dec_is_branch_w;
    logic                   dec_is_jal_w, dec_is_jalr_w, dec_invalid_w;
    logic [`ALU_OP_W - 1:0] dec_alu_op_w;
    logic                   dec_alu_src_b_imm_w, dec_alu_src_a_pc_w;
    logic             [4:0] dec_rd_w, dec_rs1_w, dec_rs2_w;
    logic                   dec_rd_valid_w;
    logic             [2:0] dec_branch_funct3_w;
    logic             [1:0] dec_mem_size_w;
    logic                   dec_mem_unsigned_w;
    logic            [31:0] dec_imm_w;

    riscv_decode u_decode
    (
        .instr_i          (fetch_instr_w),
        .is_alu_o         (dec_is_alu_w),
        .is_load_o        (dec_is_load_w),
        .is_store_o       (dec_is_store_w),
        .is_branch_o      (dec_is_branch_w),
        .is_jal_o         (dec_is_jal_w),
        .is_jalr_o        (dec_is_jalr_w),
        .invalid_o        (dec_invalid_w),       // not consumed anywhere for now
        .alu_op_o         (dec_alu_op_w),
        .alu_src_b_imm_o  (dec_alu_src_b_imm_w),
        .alu_src_a_pc_o   (dec_alu_src_a_pc_w),
        .rd_o             (dec_rd_w),
        .rs1_o            (dec_rs1_w),
        .rs2_o            (dec_rs2_w),
        .rd_valid_o       (dec_rd_valid_w),
        .branch_funct3_o  (dec_branch_funct3_w),
        .mem_size_o       (dec_mem_size_w),
        .mem_unsigned_o   (dec_mem_unsigned_w),
        .imm_o            (dec_imm_w)
    );

    // Issue -> Execute signals (outputs of riscv_issue)
    logic                   exec_valid_w;
    logic            [31:0] exec_pc_w;
    logic             [4:0] exec_rd_w;
    logic                   exec_rd_valid_w;
    logic                   exec_is_load_w;
    logic                   exec_is_store_w;
    logic [`ALU_OP_W - 1:0] exec_alu_op_w;
    logic            [31:0] exec_operand_a_w;
    logic            [31:0] exec_operand_b_w;
    logic            [31:0] exec_store_data_w;
    logic             [1:0] exec_mem_size_w;
    logic                   exec_mem_unsigned_w;
    logic            [31:0] exec_imm_w;
    logic                   exec_is_branch_w;
    logic             [2:0] exec_branch_funct3_w;
    logic                   exec_is_jal_w;
    logic                   exec_is_jalr_w;

    // Pipeline(MEM/MEM2/WB) -> Issue (Feedback Signals)
    logic        pc_valid_mem_w, pc_rd_valid_mem_w, pc_is_load_mem_w;
    logic  [4:0] pc_rd_mem_w;
    logic [31:0] pc_alu_result_mem_w;
 
    logic        pc_valid_mem2_w, pc_rd_valid_mem2_w, pc_is_load_mem2_w;
    logic  [4:0] pc_rd_mem2_w;
    logic [31:0] pc_alu_result_mem2_w;
 
    logic        pc_valid_wb_w, pc_rd_valid_wb_w;
    logic  [4:0] pc_rd_wb_w;
    logic [31:0] pc_result_wb_w;

    // Issue Unit
    riscv_issue u_issue
    (
        .clk_i                 (clk_i),
        .rst_i                 (rst_i),
        .squash_i              (squash_w),
        .stall_i               (axi_stall_w),
        .valid_dec_i           (fetch_valid_w),
        .pc_dec_i              (fetch_pc_w),
        .rd_dec_i              (dec_rd_w),
        .rs1_dec_i             (dec_rs1_w),
        .rs2_dec_i             (dec_rs2_w),
        .rd_valid_dec_i        (dec_rd_valid_w),
        .is_load_dec_i         (dec_is_load_w),
        .is_store_dec_i        (dec_is_store_w),
        .is_branch_dec_i       (dec_is_branch_w),
        .alu_op_dec_i          (dec_alu_op_w),
        .alu_src_b_imm_dec_i   (dec_alu_src_b_imm_w),
        .alu_src_a_pc_dec_i    (dec_alu_src_a_pc_w),
        .mem_size_dec_i        (dec_mem_size_w),
        .mem_unsigned_dec_i    (dec_mem_unsigned_w),
        .imm_dec_i             (dec_imm_w),
        .branch_funct3_dec_i   (dec_branch_funct3_w),
        .is_jal_dec_i          (dec_is_jal_w),
        .is_jalr_dec_i         (dec_is_jalr_w),
 
        .alu_result_exec_i     (alu_result_w),        // from ALU
 
        .valid_mem_i           (pc_valid_mem_w),
        .rd_mem_i              (pc_rd_mem_w),
        .rd_valid_mem_i        (pc_rd_valid_mem_w),
        .alu_result_mem_i      (pc_alu_result_mem_w),
        .is_load_mem_i         (pc_is_load_mem_w),
 
        .valid_mem2_i          (pc_valid_mem2_w),
        .rd_mem2_i             (pc_rd_mem2_w),
        .rd_valid_mem2_i       (pc_rd_valid_mem2_w),
        .alu_result_mem2_i     (pc_alu_result_mem2_w),
        .is_load_mem2_i        (pc_is_load_mem2_w),
 
        .valid_wb_i            (pc_valid_wb_w),
        .rd_wb_i               (pc_rd_wb_w),
        .rd_valid_wb_i         (pc_rd_valid_wb_w),
        .result_wb_i           (pc_result_wb_w),
 
        .stall_o               (issue_stall_w),
 
        .valid_exec_o          (exec_valid_w),
        .pc_exec_o             (exec_pc_w),
        .rd_exec_o             (exec_rd_w),
        .rd_valid_exec_o       (exec_rd_valid_w),
        .is_load_exec_o        (exec_is_load_w),
        .is_store_exec_o       (exec_is_store_w),
        .alu_op_exec_o         (exec_alu_op_w),
        .operand_a_exec_o      (exec_operand_a_w),
        .operand_b_exec_o      (exec_operand_b_w),
        .store_data_exec_o     (exec_store_data_w),
        .mem_size_exec_o       (exec_mem_size_w),
        .mem_unsigned_exec_o   (exec_mem_unsigned_w),
        .imm_exec_o            (exec_imm_w),
        .is_branch_exec_o      (exec_is_branch_w),
        .branch_funct3_exec_o  (exec_branch_funct3_w),
        .is_jal_exec_o         (exec_is_jal_w),
        .is_jalr_exec_o        (exec_is_jalr_w)
    );
 
    // Execute Unit
    // ALU
    logic [31:0] alu_result_w;
 
    riscv_alu u_alu
    (
        .alu_op_i    (exec_alu_op_w),
        .operand_a_i (exec_operand_a_w),
        .operand_b_i (exec_operand_b_w),
        .result_o    (alu_result_w)
    );

    // Branch Resolution
    logic [31:0] branch_target_adder_w = exec_pc_w + exec_imm_w;
    logic        alu_zero_w            = (alu_result_w == 32'b0);

    logic branch_taken_c = exec_is_branch_w && (
        (exec_branch_funct3_w == `FUNCT3_BEQ  &&  alu_zero_w)      ||
        (exec_branch_funct3_w == `FUNCT3_BNE  && !alu_zero_w)      ||
        (exec_branch_funct3_w == `FUNCT3_BLT  &&  alu_result_w[0]) ||
        (exec_branch_funct3_w == `FUNCT3_BGE  && !alu_result_w[0]) ||
        (exec_branch_funct3_w == `FUNCT3_BLTU &&  alu_result_w[0]) ||
        (exec_branch_funct3_w == `FUNCT3_BGEU && !alu_result_w[0])
        );

    logic jump_taken_c = exec_is_jal_w || exec_is_jalr_w;

    assign branch_taken_w  = exec_valid_w && (branch_taken_c || jump_taken_c);
    assign branch_target_w = (exec_is_jal_w || exec_is_jalr_w) ? alu_result_w : branch_target_adder_w;
    assign squash_w        = branch_taken_w;

    // Pipeline(MEM/MEM2/WB) Control Unit
    logic        pc_is_store_mem_w;
    logic [31:0] pc_store_data_mem_w;
    logic  [1:0] pc_mem_size_mem_w;
    logic        pc_mem_unsigned_mem_w;
    logic [31:0] lsu_rdata_w;
 
    riscv_pipe_ctrl u_pipe_ctrl
    (
        .clk_i                (clk_i),
        .rst_i                (rst_i),
        .squash_i             (squash_w),
        .stall_i              (axi_stall_w),
        .valid_exec_i         (exec_valid_w),
        .pc_exec_i            (exec_pc_w),
        .rd_exec_i            (exec_rd_w),
        .rd_valid_exec_i      (exec_rd_valid_w),
        .is_load_exec_i       (exec_is_load_w),
        .is_store_exec_i      (exec_is_store_w),
        .is_jal_exec_i        (exec_is_jal_w),
        .is_jalr_exec_i       (exec_is_jalr_w),
        .alu_result_exec_i    (alu_result_w),
        .store_data_exec_i    (exec_store_data_w),
        .mem_size_exec_i      (exec_mem_size_w),
        .mem_unsigned_exec_i  (exec_mem_unsigned_w),
 
        .valid_mem_o          (pc_valid_mem_w),
        .pc_mem_o             (),               // unused externally
        .rd_mem_o             (pc_rd_mem_w),
        .rd_valid_mem_o       (pc_rd_valid_mem_w),
        .is_load_mem_o        (pc_is_load_mem_w),
        .is_store_mem_o       (pc_is_store_mem_w),
        .is_jal_mem_o         (),               // unused externally
        .is_jalr_mem_o        (),               // unused externally
        .alu_result_mem_o     (pc_alu_result_mem_w),
        .store_data_mem_o     (pc_store_data_mem_w),
        .mem_size_mem_o       (pc_mem_size_mem_w),
        .mem_unsigned_mem_o   (pc_mem_unsigned_mem_w),
 
        .valid_mem2_o         (pc_valid_mem2_w),
        .pc_mem2_o            (),
        .rd_mem2_o            (pc_rd_mem2_w),
        .rd_valid_mem2_o      (pc_rd_valid_mem2_w),
        .is_load_mem2_o       (pc_is_load_mem2_w),
        .is_jal_mem2_o        (),
        .is_jalr_mem2_o       (),
        .alu_result_mem2_o    (pc_alu_result_mem2_w),
 
        .mem_rdata_i          (lsu_rdata_w),
 
        .valid_wb_o           (pc_valid_wb_w),
        .pc_wb_o              (),
        .rd_wb_o              (pc_rd_wb_w),
        .rd_valid_wb_o        (pc_rd_valid_wb_w),
        .result_wb_o          (pc_result_wb_w)
    );
 
    // LS Unit
    logic [31:0] dmem_addr_w;
    logic [31:0] dmem_wdata_w;
    logic [3:0]  dmem_wstrb_w;

    logic sel_dmem_w;
    logic sel_dmem_q;

    // Address Decode: Check if the address is in DMEM range (0x0000_0000 to 0x0000_0FFF)
    assign sel_dmem_w = (dmem_addr_w >= DMEM_BASE) && (dmem_addr_w < (DEM_BASE + DMEM_SIZE));

    // Latch target selection for the read resonse cycle
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            sel_dmem_q <= 1'b1;
        end
        else if (!axi_stall_w) begin
            sel_dmem_q <= sel_dmem_w;
        end
    end

    // Gated writes/valid signals based on target
    logic [3:0] dmem_wstrb_gated_w;
    logic       axi_lite_mem_valid_mem_w;

    assign dmem_wstrb_gated_w       = sel_dmem_w ? dmem_wstrb_w : 4'b0000;
    assign axi_lite_mem_valid_mem_w = pc_valid_mem_w && !sel_dmem_w; 

    logic [31:0] dmem_rdata_w;
    logic [31:0] axi_lite_rdata_w;
    logic [31:0] selected_rdata_w;

    assign selected_rdata_w = sel_dmem_q ? dmem_rdata_w : axi_lite_rdata_w;
 
    riscv_lsu u_lsu
    (
        .clk_i               (clk_i),
        .rst_i               (rst_i),
        .stall_i             (axi_stall_w),
        .valid_mem_i         (pc_valid_mem_w),
        .is_load_mem_i       (pc_is_load_mem_w),
        .is_store_mem_i      (pc_is_store_mem_w),
        .addr_mem_i          (pc_alu_result_mem_w),
        .store_data_mem_i    (pc_store_data_mem_w),
        .mem_size_mem_i      (pc_mem_size_mem_w),
        .mem_unsigned_mem_i  (pc_mem_unsigned_mem_w),
 
        .dmem_addr_o         (dmem_addr_w),
        .dmem_wdata_o        (dmem_wdata_w),
        .dmem_wstrb_o        (dmem_wstrb_w),
        .dmem_rdata_i        (selected_rdata_w),       // Receives data from selected target
 
        .mem_rdata_o         (lsu_rdata_w)
    );
 
    // Data memory (DMEM)
    riscv_dmem #(.INIT_FILE("data.hex")) u_dmem
    (
        .clk_i   (clk_i),
        .addr_i  (dmem_addr_w),
        .wdata_i (dmem_wdata_w),
        .wstrb_i (dmem_wstrb_gated_w),   // Writes muted if target is AXI
        .rdata_o (dmem_rdata_w)
    );

    // AXI-Lite Master Bridge(DMA)
    riscv_axi_lite_bridge u_axil_bridge (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .valid_mem_i    (axil_valid_mem_w), // Active only when target is AXI
        .is_load_mem_i  (pc_is_load_mem_w),
        .is_store_mem_i (pc_is_store_mem_w),
        .addr_mem_i     (dmem_addr_w),
        .wdata_mem_i    (dmem_wdata_w),
        .wstrb_mem_i    (dmem_wstrb_w),
        .rdata_mem_o    (axil_rdata_w),
        .stall_o        (axi_stall_w),

        .m_axil_awaddr  (m_axil_awaddr),
        .m_axil_awprot  (m_axil_awprot),
        .m_axil_awvalid (m_axil_awvalid),
        .m_axil_awready (m_axil_awready),
        .m_axil_wdata   (m_axil_wdata),
        .m_axil_wstrb   (m_axil_wstrb),
        .m_axil_wvalid  (m_axil_wvalid),
        .m_axil_wready  (m_axil_wready),
        .m_axil_bresp   (m_axil_bresp),
        .m_axil_bvalid  (m_axil_bvalid),
        .m_axil_bready  (m_axil_bready),
        .m_axil_araddr  (m_axil_araddr),
        .m_axil_arprot  (m_axil_arprot),
        .m_axil_arvalid (m_axil_arvalid),
        .m_axil_arready (m_axil_arready),
        .m_axil_rdata   (m_axil_rdata),
        .m_axil_rresp   (m_axil_rresp),
        .m_axil_rvalid  (m_axil_rvalid),
        .m_axil_rready  (m_axil_rready) 
    );

endmodule