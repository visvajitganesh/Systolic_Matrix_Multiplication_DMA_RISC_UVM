# RISC-V RV32I Processor Components

A SystemVerilog implementation of core RISC-V RV32I processor pipeline building blocks, including the Instruction Fetch unit with skid buffer support, Load/Store Unit (LSU), Instruction Decoder, Arithmetic Logic Unit (ALU), Register File, Instruction Memory (IMEM), Data Memory (DMEM), shared macro definitions, and comprehensive self-checking testbenches.

---

## 📑 Project Overview

This repository contains parameterizable, synthesizable SystemVerilog hardware modules designed for a standard 32-bit RISC-V architecture (RV32I):

- **RISC-V Definitions (`riscv_defs.sv`)**: Macro definitions for opcodes, instruction field slices, funct3/funct7 codes, and ALU control codes.
- **Instruction Fetch (`riscv_fetch.sv`)**: Pipeline instruction fetch module with PC generation, branch target redirection, pipeline squash/flush handling, and an integrated skid buffer for zero-bubble stall cycles.
- **Load/Store Unit (`riscv_lsu.sv`)**: Memory stage interface unit handling address alignment, byte/halfword lane replication, write-strobe generation, sign/zero extension for load data, and multi-cycle stall freeze logic.
- **Instruction Decoder (`riscv_decode.sv`)**: Combinational decoder parsing RV32I opcodes, immediate generation, register addresses, and control flags.
- **Arithmetic Logic Unit (`riscv_alu.sv`)**: Parameterizable combinational unit supporting arithmetic, logical, shift, and comparison operations.
- **Register File (`riscv_regfile.sv`)**: Synchronous write, dual-port asynchronous read register file with hardwired `x0 = 0` behavior.
- **Instruction Memory (`riscv_imem.sv`)**: Synchronous 1-cycle latency memory for instruction fetching with misaligned and out-of-bounds error checking.
- **Data Memory (`riscv_dmem.sv`)**: Synchronous 1-cycle latency data memory with byte-strobe support and read-during-write pass-through logic.
- **Verification Testbenches**: Comprehensive self-checking testbenches with targeted, edge-case, and randomized verification.

---

## 🏛️ Module Architecture & Port Descriptions

### 1. Header & Definitions (`riscv_defs.sv`)
Provides crucial RISC-V RV32I opcodes, instruction slices, and control bit vectors:
- **Opcodes**: R-type (`0110011`), I-type ALU (`0010011`), Load (`0000011`), Store (`0100011`), Branch (`1100011`), JAL (`1101111`), JALR (`1100111`), LUI (`0110311`), AUIPC (`0010111`).
- **Instruction Field Slices**: `OPCODE_R`, `RD_R`, `FUNCT3_R`, `RS1_R`, `RS2_R`, `FUNCT7_R`.
- **ALU Control Codes (`ALU_OP_W = 4`)**: `ALU_ADD` (`4'd0`), `ALU_SUB` (`4'd1`), `ALU_AND` (`4'd2`), `ALU_OR` (`4'd3`), `ALU_XOR` (`4'd4`), `ALU_SLT` (`4'd5`), `ALU_SLTU` (`4'd6`), `ALU_SLL` (`4'd7`), `ALU_SRL` (`4'd8`), `ALU_SRA` (`4'd9`), `ALU_PASS_B` (`4'd10`).

---

### 2. Instruction Fetch Stage (`riscv_fetch.sv`)

#### Architecture & Features
- **PC Generation**: Automatically increments PC by +4 every clock cycle unless stalled or redirected.
- **Branch Redirection**: Immediately updates PC on `branch_taken_i` assertion.
- **Squash Logic**: Invalidate current pipeline payload without advancing program counter.
- **Integrated Skid Buffer**: Prevents payload corruption during downstream pipeline stalls by capturing incoming memory data on stall assertion and serving it consistently until the stall clears.

#### Input & Output Ports
| Direction | Port Name | Width / Type | Description |
| :--- | :--- | :--- | :--- |
| **Input** | `clk_i` | `logic` | Clock input |
| **Input** | `rst_i` | `logic` | Active-high reset signal |
| **Input** | `branch_taken_i` | `logic` | Directs PC to update to `branch_target_i` |
| **Input** | `branch_target_i` | `[31:0]` | Target address for branch/jump redirection |
| **Input** | `squash_i` | `logic` | Flushes current in-flight instruction and invalidates validity output |
| **Input** | `stall_i` | `logic` | Holds program counter and activates skid buffer |
| **Input** | `imem_rdata_i` | `[31:0]` | Instruction data read from Instruction Memory |
| **Output** | `imem_addr_o` | `[31:0]` | Target fetch address sent to Instruction Memory |
| **Output** | `pc_o` | `[31:0]` | Program counter corresponding to current `instr_o` output |
| **Output** | `instr_o` | `logic [31:0]` | Instruction payload provided to Decode/Issue stage |
| **Output** | `valid_o` | `logic` | Valid output signal indicating `instr_o` is clean and un-flushed |

---

### 3. Load/Store Unit (`riscv_lsu.sv`)

#### Architecture & Features
- **Store Alignment & Replication**: Dynamically aligns write byte strobes (`dmem_wstrb_o`) and replicates sub-word store data (`SB`, `SH`) across appropriate 32-bit memory byte lanes based on low-order address bits (`addr_mem_i[1:0]`).
- **Load Response Processing**: Registers transaction metadata across memory latency and performs sign extension (`LB`, `LH`) or zero extension (`LBU`, `LHU`) on incoming read data based on requested access size and signedness flags.
- **Pipeline Stall Protection**: Retains original memory metadata registers unchanged during downstream stall conditions (`stall_i`), preventing control state drift during multi-cycle transactions or AXI bus delays.

#### Input & Output Ports
| Direction | Port Name | Width / Type | Description |
| :--- | :--- | :--- | :--- |
| **Input** | `clk_i` | `logic` | Clock input |
| **Input** | `rst_i` | `logic` | Active-high reset signal |
| **Input** | `stall_i` | `logic` | Pipeline stall signal; freezes metadata tracking registers |
| **Input** | `valid_mem_i` | `logic` | Active memory stage transaction valid flag |
| **Input** | `is_load_mem_i` | `logic` | Memory read command flag |
| **Input** | `is_store_mem_i` | `logic` | Memory write command flag |
| **Input** | `addr_mem_i` | `[31:0]` | Memory access byte address (from ALU result) |
| **Input** | `store_data_mem_i` | `[31:0]` | Write data payload from pipeline register |
| **Input** | `mem_size_mem_i` | `[1:0]` | Access size control (`00`=Byte, `01`=Halfword, `10`=Word) |
| **Input** | `mem_unsigned_mem_i` | `logic` | Unsigned load control (`1`=Zero extend, `0`=Sign extend) |
| **Output** | `dmem_addr_o` | `logic [31:0]` | Address output routed to Data Memory |
| **Output** | `dmem_wdata_o` | `logic [31:0]` | Byte lane-aligned write data sent to Data Memory |
| **Output** | `dmem_wstrb_o` | `logic [3:0]` | Active byte-lane enable write strobes |
| **Input** | `dmem_rdata_i` | `[31:0]` | Raw word data read from Data Memory |
| **Output** | `mem_rdata_o` | `logic [31:0]` | Aligned, sign/zero-extended load data returned to pipeline |

---

### 4. Instruction Decoder (`riscv_decode.sv`)

#### Input & Output Ports
| Direction | Port Name | Width / Type | Description |
| :--- | :--- | :--- | :--- |
| **Input** | `instr_i` | `[31:0]` | 32-bit RISC-V raw instruction input |
| **Output** | `is_alu_o` | `logic` | Asserted for R-type/I-type ALU operations |
| **Output** | `is_load_o` | `logic` | Asserted for Load instructions |
| **Output** | `is_store_o` | `logic` | Asserted for Store instructions |
| **Output** | `is_branch_o` | `logic` | Asserted for Branch instructions |
| **Output** | `is_jal_o` | `logic` | Asserted for JAL instruction |
| **Output** | `is_jalr_o` | `logic` | Asserted for JALR instruction |
| **Output** | `invalid_o` | `logic` | Asserted when opcode or funct fields are unrecognized |
| **Output** | `alu_op_o` | `[ALU_OP_W - 1:0]` (4 bits) | Encoded ALU operation code |
| **Output** | `alu_src_b_imm_o` | `logic` | Selects immediate operand (`1`) or register operand `rs2` (`0`) for ALU input B |
| **Output** | `alu_src_a_pc_o` | `logic` | Selects PC (`1`) or register operand `rs1` (`0`) for ALU input A |
| **Output** | `rd_o` | `[4:0]` | Destination register index |
| **Output** | `rs1_o` | `[4:0]` | Source register 1 index |
| **Output** | `rs2_o` | `[4:0]` | Source register 2 index |
| **Output** | `rd_valid_o` | `logic` | High if instruction writes back to destination register |
| **Output** | `branch_funct3_o` | `[2:0]` | Extracted funct3 field for branch condition testing |
| **Output** | `mem_size_o` | `[1:0]` | Load/Store access size (`00`=Byte, `01`=Halfword, `10`=Word) |
| **Output** | `mem_unsigned_o` | `logic` | Sign extension control (`1`=Unsigned LBU/LHU, `0`=Signed) |
| **Output** | `imm_o` | `[31:0]` | Sign-extended immediate value formatted by instruction type |

#### Functional Requirements & Specifications

* **Header Dependency:**
  * Include `"riscv_defs.sv"` to access global instruction field macros (`OPCODE_R`, `FUNCT3_R`, `FUNCT7_R`, `RD_R`, `RS1_R`, `RS2_R`) and opcode/funct definitions.

* **Module Interface:**
  * **Inputs:** `instr_i` (32-bit raw instruction word).
  * **Instruction Type Flags:** `is_alu_o`, `is_load_o`, `is_store_o`, `is_branch_o`, `is_jal_o`, `is_jalr_o`, `invalid_o`.
  * **Datapath & Execution Control:**
    * `alu_op_o` (`ALU_OP_W`-bit ALU control select signal).
    * `alu_src_b_imm_o` (1-bit flag: `1` selects immediate, `0` selects register `rs2`).
    * `alu_src_a_pc_o` (1-bit flag: `1` selects PC, `0` selects register `rs1`).

  * **Register File Control & Index Addressing:**
    * `rd_o`, `rs1_o`, `rs2_o` (5-bit register index addresses).
    * `rd_valid_o` (1-bit write-enable indicator for `rd`).

  * **Memory & Branch Control:**
    * `branch_funct3_o` (3-bit branch condition sub-type).
    * `mem_size_o` (2-bit access width: `00`=byte, `01`=halfword, `10`=word).
    * `mem_unsigned_o` (1-bit flag: `1`=zero-extend, `0`=sign-extend).

  * **Immediate Value:** `imm_o` (32-bit reconstructed sign-extended immediate).

* **Instruction Decoding Logic (`always_comb`):**
  * **Default Safe Driving:** Set all control classification flags (`is_*`), `invalid_o`, `alu_src_*`, `rd_valid_o`, and internal validity flags (`rs1_valid`, `rs2_valid`) to `1'b0`. Set default `alu_op_o = \`ALU_ADD``and memory flags to`0`.
  * **Opcode Decoding (`case (instr_i[\`OPCODE_R"])`):**
    * **R-Type (`OPCODE_OP`):** Assert `is_alu_o`, `rd_valid_o`, `rs1_valid`, and `rs2_valid`. Decode `FUNCT3_R` and `FUNCT7_R` to map operations (`ADD`, `SUB`, `SLT`, `SLTU`, `AND`, `OR`, `XOR`, `SLL`, `SRL`, `SRA`). Assert `invalid_o` and deassert flags on invalid `FUNCT7` values.
    * **I-Type ALU (`OPCODE_OP_IMM`):** Assert `is_alu_o`, `rd_valid_o`, `rs1_valid`, and `alu_src_b_imm_o`. Decode `FUNCT3_R` to assign `alu_op_o`. Validate `FUNCT7` for shift instructions (`SLL`, `SRL`, `SRA`).
    * **Load Instructions (`OPCODE_LOAD`):** Assert `is_load_o`, `rd_valid_o`, `rs1_valid`, `alu_src_b_imm_o`, and set `alu_op_o = \`ALU_ADD``. Decode `FUNCT3_R`to configure`mem_size_o`and`mem_unsigned_o` (`WORD`, `HALF`, `BYTE`, `HALF_U`, `BYTE_U`).
    * **Store Instructions (`OPCODE_STORE`):** Assert `is_store_o`, `rs1_valid`, `rs2_valid`, `alu_src_b_imm_o`, and set `alu_op_o = \`ALU_ADD``. Decode `FUNCT3_R`to configure`mem_size_o`.
    * **Branch Instructions (`OPCODE_BRANCH`):** Assert `is_branch_o`, `rs1_valid`, and `rs2_valid`. Map branch operations via `FUNCT3_R` to ALU ops (`SUB` for equality checks, `SLT`/`SLTU` for comparison checks).
    * **JAL (`OPCODE_JAL`):** Assert `is_jal_o`, `rd_valid_o`, `alu_src_a_pc_o`, `alu_src_b_imm_o`, and set `alu_op_o = \`ALU_ADD``.
    * **JALR (`OPCODE_JALR`):** Verify `FUNCT3_R == 3'b000`. Assert `is_jalr_o`, `rd_valid_o`, `rs1_valid`, `alu_src_b_imm_o`, and set `alu_op_o = \`ALU_ADD``.
    * **LUI (`OPCODE_LUI`):** Assert `is_alu_o`, `rd_valid_o`, `alu_src_b_imm_o`, and set `alu_op_o = \`ALU_PASS_B``.
    * **AUIPC (`OPCODE_AUIPC`):** Assert `is_alu_o`, `rd_valid_o`, `alu_src_a_pc_o`, `alu_src_b_imm_o`, and set `alu_op_o = \`ALU_ADD``.
    * **Default / Unrecognized Opcode:** Assert `invalid_o = 1'b1`.

* **Register Index Masking (`assign` statements):**
  * Pass source/destination field bits (`instr_i[\`RD_R`]`, `instr_i[`RS1_R`]`, `instr_i[`RS2_R`]`) to `rd_o`, `rs1_o`, and `rs2_o` only when their respective validation bit (`rd_valid_o`, `rs1_valid`, `rs2_valid`) is active; otherwise, drive to `5'd0`.

* **Immediate Reconstruction Logic (`always_comb`):**
  * Decode instruction bit slices based on `instr_i[\`OPCODE_R`]` and sign-extend to 32 bits:
    * **I-Type / Load / JALR:** Extend `instr_i[31:20]` (12 bits).
    * **S-Type (Store):** Combine `instr_i[31:25]` and `instr_i[11:7]`.
    * **B-Type (Branch):** Reconstruct scramble pattern `{instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0}` with 19-bit sign extension.
    * **J-Type (JAL):** Reconstruct scramble pattern `{instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0}` with 11-bit sign extension.
    * **U-Type (LUI / AUIPC):** Shift upper 20 bits (`instr_i[31:12]`) and zero-fill lower 12 bits (`{instr_i[31:12], 12'b0}`).
    * **Default:** Drive `imm_o` to `'0`.

* **Branch Output Formatting:**
  * Assign `branch_funct3_o` to pass `instr_i[\`FUNCT3_R`]`when`is_branch_o`is active, otherwise drive to`0`.
 
---

### 5. Arithmetic Logic Unit (`riscv_alu.sv`)

#### Parameters
| Parameter | Default | Description |
| :--- | :--- | :--- |
| `DATA_WIDTH` | `32` | Bit width for data operands and result |

#### Input & Output Ports
| Direction | Port Name | Width / Type | Description |
| :--- | :--- | :--- | :--- |
| **Input** | `alu_op_i` | `[ALU_OP_W - 1:0]` (4 bits) | Selects the ALU operation to execute |
| **Input** | `operand_a_i` | `[DATA_WIDTH - 1:0]` (32 bits) | Operand A input |
| **Input** | `operand_b_i` | `[DATA_WIDTH - 1:0]` (32 bits) | Operand B input / shift amount |
| **Output** | `result_o` | `[DATA_WIDTH - 1:0]` (32 bits) | Calculated result output |

#### Functional Requirements & Specifications

* **Header Dependency:**
  * Include `"riscv_defs.sv"` to import global definitions, macro operations (such as `ALU_ADD`, `ALU_SUB`, etc.), and the operation selector width macro `ALU_OP_W`.


* **Module Interface:**
  * **Parameters:**
    * `DATA_WIDTH`: Integer defining the bit width of input operands and output result (default: `32`).

  * **Inputs:**
    * `alu_op_i`: Operation select signal of width `\`ALU_OP_W` bits.
    * `operand_a_i`: Primary source input vector of width `DATA_WIDTH`.
    * `operand_b_i`: Secondary source input vector of width `DATA_WIDTH`.

  * **Outputs:**
    * `result_o`: Computed output vector of width `DATA_WIDTH`.

* **Internal Signal & Parameter Calculations:**
  * Define `SHIFT_W` as a local parameter evaluated using `$clog2(DATA_WIDTH)` to derive the exact number of lower bits required from `operand_b_i` for shift amounts (e.g., 5 bits for 32-bit data).
  * Declare `signed_a_ext` as a signed logic signal of width `2 * DATA_WIDTH` bits used to perform arithmetic shifts safely.

* **Combinational Execution Logic (`always_comb`):**
  * **Sign-Extension Register Preparation:** Sign-extend `operand_a_i` into the upper half of `signed_a_ext` by replicating bit `[DATA_WIDTH - 1]` across `DATA_WIDTH` positions and concatenating `operand_a_i` in the lower half.
  * **Operation Selection (`unique case`):** Evaluates `alu_op_i` combinationally to set `result_o`:
    * **`ALU_ADD`**: Perform binary addition (`operand_a_i + operand_b_i`).
    * **`ALU_SUB`**: Perform binary subtraction (`operand_a_i - operand_b_i`).
    * **`ALU_AND`**: Bitwise AND operation (`operand_a_i & operand_b_i`).
    * **`ALU_OR`**: Bitwise OR operation (`operand_a_i | operand_b_i`).
    * **`ALU_XOR`**: Bitwise XOR operation (`operand_a_i ^ operand_b_i`).
    * **`ALU_SLT`**: Signed less-than comparison (`$signed(operand_a_i) < $signed(operand_b_i)`). Return `1` in bit `0` (zero-padded) if true, else `'0`.
    * **`ALU_SLTU`**: Unsigned less-than comparison (`operand_a_i < operand_b_i`). Return `1` in bit `0` (zero-padded) if true, else `'0`.
    * **`ALU_SLL`**: Logical left-shift `operand_a_i` by the shift amount specified in the lower `SHIFT_W` bits of `operand_b_i`.
    * **`ALU_SRL`**: Logical right-shift `operand_a_i` by the shift amount specified in the lower `SHIFT_W` bits of `operand_b_i`.
    * **`ALU_SRA`**: Perform signed arithmetic right-shift on `signed_a_ext` using `>>>` by `operand_b_i[SHIFT_W - 1:0]` and assign to `result_o` (truncating upper bits).
    * **`ALU_PASS_B`**: Directly pass `operand_b_i` to `result_o`.
    * **`default`**: Drive `result_o` to all zeros (`'b0`).

---

### 6. Register File (`riscv_regfile.sv`)

#### Parameters
| Parameter | Default | Description |
| :--- | :--- | :--- |
| `DATA_WIDTH` | `32` | Data width of each register entry |

#### Input & Output Ports
| Direction | Port Name | Width / Type | Description |
| :--- | :--- | :--- | :--- |
| **Input** | `clk_i` | `logic` | Clock input |
| **Input** | `rst_i` | `logic` | Active-high asynchronous reset |
| **Input** | `rd0_i` | `[4:0]` | Destination register index for write (0–31) |
| **Input** | `rd0_value_i` | `[DATA_WIDTH - 1:0]` (32 bits) | Write data payload |
| **Input** | `rd0_wren_i` | `logic` | Active-high write enable |
| **Input** | `ra0_i` | `[4:0]` | Read Port 1 register address |
| **Input** | `rb0_i` | `[4:0]` | Read Port 2 register address |
| **Output** | `ra0_value_o` | `[DATA_WIDTH - 1:0]` (32 bits) | Asynchronous read data output for Port 1 |
| **Output** | `rb0_value_o` | `[DATA_WIDTH - 1:0]` (32 bits) | Asynchronous read data output for Port 2 |

#### Functional Requirements & Specifications

* **Module Interface:**
  * **Parameters:**
    * `DATA_WIDTH`: Integer defining the bit width of each register (default: `32`).

  * **Inputs:**
    * `clk_i` (clock signal).
    * `rst_i` (active-high asynchronous reset signal).
    * `rd0_i` (5-bit write address targeting registers 0 to 31).
    * `rd0_value_i` (`DATA_WIDTH`-bit write data).
    * `rd0_wren_i` (1-bit write enable control signal).
    * `ra0_i` (5-bit read address port 1).
    * `rb0_i` (5-bit read address port 2).

  * **Outputs:**
    * `ra0_value_o` (`DATA_WIDTH`-bit asynchronous output for read address 1).
    * `rb0_value_o` (`DATA_WIDTH`-bit asynchronous output for read address 2).

* **Register Storage Array:**
  * Declare an internal register file array `r_xx` consisting of 32 words (`[0:31]`), each having a width of `DATA_WIDTH` bits.

* **Synchronous Write Operation with Asynchronous Reset (`always_ff @(posedge clk_i or posedge rst_i)`):**
  * **Reset Condition (`rst_i == 1`):** Asynchronously clear all 32 registers in `r_xx` to all-zeros using an assignment pattern (`'{default: '0}`).
  * **Write Operation (`rst_i == 0`):** On the rising clock edge (`posedge clk_i`), commit `rd0_value_i` to `r_xx[rd0_i]` **only if**:
    1. Write enable is active (`rd0_wren_i == 1`).
    2. Target destination address is not register zero (`rd0_i != 5'b00000`).

  * **Zero Register (`x0`) Protection:** Register 0 must be hard-coded to ignore synchronous write operations, maintaining its value or preventing write commits.

* **Asynchronous Read Operation (`assign` statements):**
  * **Dual Asynchronous Read Ports:** Read data combinationally without waiting for a clock edge.
  * **Read Port 1 (`ra0_value_o`):** Continuously output `'0` if `ra0_i == 5'b00000`; otherwise, output the current contents of `r_xx[ra0_i]`.
  * **Read Port 2 (`rb0_value_o`):** Continuously output `'0` if `rb0_i == 5'b00000`; otherwise, output the current contents of `r_xx[rb0_i]`.

---

### 7. Instruction Memory (`riscv_imem.sv`)

#### Parameters
| Parameter | Default | Description |
| :--- | :--- | :--- |
| `DEPTH` | `1024` | Number of 32-bit instruction words stored |
| `INIT_FILE` | `""` | Optional file path for memory initialization via `$readmemh` |

#### Input & Output Ports
| Direction | Port Name | Width / Type | Description |
| :--- | :--- | :--- | :--- |
| **Input** | `clk_i` | `logic` | Clock input |
| **Input** | `rst_i` | `logic` | Active-high reset signal |
| **Input** | `addr_i` | `[31:0]` | Instruction fetch byte address |
| **Output** | `rdata_o` | `[31:0]` | Synchronous 1-cycle read instruction data (NOP on exception) |
| **Output** | `error_unaligned_o` | `logic` | High if `addr_i[1:0] != 2'b00` |
| **Output** | `error_out_of_bounds_o` | `logic` | High if address index exceeds memory `DEPTH` |

#### Functional Requirements & Specifications

* **Module Interface:**
  * **Parameters:**
    * `DEPTH`: Integer specifying the total number of 32-bit memory words (default: `1024`).
    * `INIT_FILE`: String specifying a path to a hexadecimal initialization file (default: empty `""`).

  * **Inputs:** `clk_i` (clock), `rst_i` (active-high reset), `addr_i` (32-bit byte address).
  * **Outputs:** `rdata_o` (32-bit instruction output), `error_unaligned_o` (1-bit flag), `error_out_of_bounds_o` (1-bit flag).


* **Memory Storage & Pre-loading:**
  * Declare an internal array of 32-bit logic vectors ranging from index `0` to `DEPTH - 1`.
  * In an `initial` block, check if `INIT_FILE` is non-empty; if so, load the memory array using `$readmemh`.


* **Address Checking Logic (Combinational):**
  * **Unaligned Access Check:** Check if the lower 2 bits of `addr_i` are non-zero (`addr_i[1:0] != 2'b00`).
  * **Out-of-Bounds Check:** Check if the word index from `addr_i[31:2]` is greater than or equal to `DEPTH`.


* **Synchronous Behavior (`always_ff @(posedge clk_i)`):**
  * **Reset State (`rst_i == 1`):**
    * Set `rdata_o` to the RISC-V NOP instruction binary (`32'h0000_0013`).
    * Clear `error_unaligned_o` and `error_out_of_bounds_o` to `1'b0`.


  * **Normal Operation (`rst_i == 0`):**
    * Register both unaligned and out-of-bounds error flags to their respective outputs.
    * **Valid Access:** If *neither* error condition is true, output the word from memory at index `addr_i[31:2]`.
    * **Invalid Access:** If *either* error condition is true, substitute and output `32'h0000_0013` (NOP) to prevent illegal or `X` state propagation.

---

### 8. Data Memory (`riscv_dmem.sv`)

#### Parameters
| Parameter | Default | Description |
| :--- | :--- | :--- |
| `DEPTH` | `1024` | Number of 32-bit data words stored |
| `INIT_FILE` | `""` | Optional file path for preloading memory contents |

#### Input & Output Ports
| Direction | Port Name | Width / Type | Description |
| :--- | :--- | :--- | :--- |
| **Input** | `clk_i` | `logic` | Clock input |
| **Input** | `rst_i` | `logic` | Active-high reset signal |
| **Input** | `addr_i` | `[31:0]` | Target memory byte address |
| **Input** | `wdata_i` | `[31:0]` | Write data input payload |
| **Input** | `wstrb_i` | `[3:0]` | Byte lane write enable strobes |
| **Output** | `rdata_o` | `[31:0]` | Synchronous 1-cycle read data (supports same-cycle write pass-through) |
| **Output** | `error_unaligned_o` | `logic` | High if byte address is misaligned (`addr_i[1:0] != 2'b00`) |
| **Output** | `error_out_of_bounds_o` | `logic` | High if target word index exceeds memory `DEPTH` |

#### Functional Requirements & Specifications

* **Module Interface:**
  * **Parameters:**
    * `DEPTH`: Integer specifying total 32-bit memory words (default: `1024`).
    * `INIT_FILE`: String specifying path to hex initialization file (default: empty `""`).

  * **Inputs:** `clk_i` (clock), `rst_i` (active-high reset), `addr_i` (32-bit byte address), `wdata_i` (32-bit write data), `wstrb_i` (4-bit byte write strobe).
  * **Outputs:** `rdata_o` (32-bit read data), `error_unaligned_o` (1-bit flag), `error_out_of_bounds_o` (1-bit flag).


* **Memory Storage & Pre-loading:**
  * Declare an internal array of 32-bit logic vectors ranging from index `0` to `DEPTH - 1`.
  * In an `initial` block:
    * If `INIT_FILE` is non-empty, load memory contents using `$readmemh`.
    * If `INIT_FILE` is empty (`""`), explicitly zero-fill all locations from `0` to `DEPTH - 1` in a loop.

* **Address Checking Logic (Combinational):**
  * **Unaligned Access Check:** Check if the lower 2 bits of `addr_i` are non-zero (`addr_i[1:0] != 2'b00`).
  * **Out-of-Bounds Check:** Check if the word index `addr_i[31:2]` is greater than or equal to `DEPTH`.


* **Synchronous Read/Write Operation (`always @(posedge clk_i)`):**
  * **Reset State (`rst_i == 1`):**
    * Clear `rdata_o` to `32'h0000_0000`.
    * Clear `error_unaligned_o` and `error_out_of_bounds_o` to `1'b0`.

  * **Normal Operation (`rst_i == 0`):**
    * Register both unaligned and out-of-bounds error flags to their respective output pins.
    * **Valid Access Condition:** If *neither* error condition is true:
      * **Byte-Enable Writes:** Write byte `k` of `wdata_i` (`[8k+7 : 8k]`) into `mem[addr_i[31:2]][8k+7 : 8k]` only if `wstrb_i[k] == 1` (for `k = 0, 1, 2, 3`). Unasserted strobe bits leave the corresponding memory bytes unchanged.
      * **Read-During-Write Forwarding:** For each byte `k` of `rdata_o`: if `wstrb_i[k] == 1`, forward the new write byte `wdata_i[8k+7 : 8k]`; otherwise, output the existing memory byte `mem[addr_i[31:2]][8k+7 : 8k]`.


    * **Invalid Access Condition:** If *either* error condition is true, block memory writes and drive `rdata_o` to `32'h0000_0000`.

---

## 🧪 Verification & Testbenches

- **`tb_riscv_fetch.sv`**: Verifies sequential fetch operation, skid buffer retention during single and multi-cycle stalls, branch redirection, simultaneous stall/branch conditions, pipeline squashing/flushing, and includes 100 cycles of randomized stress tests.
- **`tb_riscv_lsu.sv`**: Validates store byte-lane strobe generation, byte/halfword write data replication across byte offsets, signed vs. zero-extended load extraction (`LB`, `LBU`, `LH`, `LHU`, `LW`), multi-cycle stall hold behavior, and a 200-iteration randomized stress test against a golden reference model.
- **`tb_riscv_decode.sv`**: Exhaustively verifies control signal leakage protection during invalid funct3/funct7 decodes, upper-bit shift checks (SLLI/SRAI), and standard opcode decoding.
- **`tb_riscv_alu.sv`**: Validates basic execution operations, edge-case signed/unsigned comparisons, and 500 constraint-free random test patterns.
- **`tb_riscv_regfile.sv`**: Tests asynchronous reset, `x0` register immutability, read-during-write hazard timing, full register sweeping, and write-protection logic.
- **`tb_riscv_imem.sv`**: Verifies 1-cycle instruction retrieval, active reset NOP output (`0x00000013`), boundary access checks, and fault recoveries.
- **`tb_riscv_dmem.sv`**: Tests 1-cycle read/write memory timing, byte-strobe lane combinations, read-during-write pass-through, and address boundary exception flags.

---

