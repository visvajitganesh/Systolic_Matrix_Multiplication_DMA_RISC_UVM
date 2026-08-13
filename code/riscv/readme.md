# RISC-V RV32I Processor Components

A SystemVerilog implementation of core RISC-V RV32I processor pipeline building blocks, including the Instruction Fetch unit with skid buffer support, Instruction Decoder, Arithmetic Logic Unit (ALU), Register File, Instruction Memory (IMEM), Data Memory (DMEM), shared macro definitions, and comprehensive self-checking testbenches.

---

## 📑 Project Overview

This repository contains parameterizable, synthesizable SystemVerilog hardware modules designed for a standard 32-bit RISC-V architecture (RV32I):

- **RISC-V Definitions (`riscv_defs.sv`)**: Macro definitions for opcodes, instruction field slices, funct3/funct7 codes, and ALU control codes.
- **Instruction Fetch (`riscv_fetch.sv`)**: Pipeline instruction fetch module with PC generation, branch target redirection, pipeline squash/flush handling, and an integrated skid buffer for zero-bubble stall cycles.
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

### 3. Instruction Decoder (`riscv_decode.sv`)

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

---

### 4. Arithmetic Logic Unit (`riscv_alu.sv`)

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

---

### 5. Register File (`riscv_regfile.sv`)

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

---

### 6. Instruction Memory (`riscv_imem.sv`)

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

---

### 7. Data Memory (`riscv_dmem.sv`)

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

---

## 🧪 Verification & Testbenches

- **`tb_riscv_fetch.sv`**: Verifies sequential fetch operation, skid buffer retention during single and multi-cycle stalls, branch redirection, simultaneous stall/branch conditions, pipeline squashing/flushing, and includes 100 cycles of randomized stress tests.
- **`tb_riscv_decode.sv`**: Exhaustively verifies control signal leakage protection during invalid funct3/funct7 decodes, upper-bit shift checks (SLLI/SRAI), and standard opcode decoding.
- **`tb_riscv_alu.sv`**: Validates basic execution operations, edge-case signed/unsigned comparisons, and 500 constraint-free random test patterns.
- **`tb_riscv_regfile.sv`**: Tests asynchronous reset, `x0` register immutability, read-during-write hazard timing, full register sweeping, and write-protection logic.
- **`tb_riscv_imem.sv`**: Verifies 1-cycle instruction retrieval, active reset NOP output (`0x00000013`), boundary access checks, and fault recoveries.
- **`tb_riscv_dmem.sv`**: Tests 1-cycle read/write memory timing, byte-strobe lane combinations, read-during-write pass-through, and address boundary exception flags.

---
