# RISC-V 
---

## 📑 Project Overview

This repository contains parameterizable, synthesizable SystemVerilog modules designed for a standard 32-bit RISC-V processor architecture (RV32I):

- **RISC-V Definitions (`riscv_defs.sv`)**: Macro definitions for opcodes, instruction fields, funct3/funct7 codes, and internal ALU operation codes.
- **Arithmetic Logic Unit (`riscv_alu.sv`)**: Fully combinational unit supporting arithmetic, logical, comparison, shift, and pass-through operations.
- **Register File (`riscv_regfile.sv`)**: Dual-port asynchronous read and single-port synchronous write register file with hardwired `x0 = 0` behavior.
- **Verification Testbenches (`tb_riscv_alu.sv`, `tb_riscv_regfile.sv`)**: Self-checking testbenches with randomized and targeted functional tests.

---

## 🏛️ Module Architecture & Port Descriptions

### 1. Header & Definitions (`riscv_defs.sv`)
Provides crucial RISC-V RV32I opcodes and bit field selectors:
- **Opcodes**: R-type (`0110011`), I-type ALU (`0010011`), Load (`0000011`), Store (`0100011`), Branch (`1100011`), JAL (`1101111`), JALR (`1100111`), LUI (`0110311`), AUIPC (`0010111`).
- **Instruction Field Slices**: `OPCODE_R`, `RD_R`, `FUNCT3_R`, `RS1_R`, `RS2_R`, `FUNCT7_R`.
- **ALU Control Codes (`ALU_OP_W = 4`)**:
  - `4'd0`: `ALU_ADD`
  - `4'd1`: `ALU_SUB`
  - `4'd2`: `ALU_AND`
  - `4'd3`: `ALU_OR`
  - `4'd4`: `ALU_XOR`
  - `4'd5`: `ALU_SLT` (Set Less Than - Signed)
  - `4'd6`: `ALU_SLTU` (Set Less Than - Unsigned)
  - `4'd7`: `ALU_SLL` (Shift Left Logical)
  - `4'd8`: `ALU_SRL` (Shift Right Logical)
  - `4'd9`: `ALU_SRA` (Shift Right Arithmetic)
  - `4'd10`: `ALU_PASS_B` (Pass Operand B)

---

### 2. Arithmetic Logic Unit (`riscv_alu.sv`)

#### Parameters
| Parameter | Default | Description |
| :--- | :--- | :--- |
| `DATA_WIDTH` | `32` | Data bus width for operands and result |

#### Input & Output Ports
| Direction | Port Name | Width / Type | Description |
| :--- | :--- | :--- | :--- |
| **Input** | `alu_op_i` | `[`ALU_OP_W - 1:0]` (4 bits) | Selects the ALU operation to execute |
| **Input** | `operand_a_i` | `[DATA_WIDTH - 1:0]` (32 bits) | First operand source |
| **Input** | `operand_b_i` | `[DATA_WIDTH - 1:0]` (32 bits) | Second operand source / shift amount |
| **Output** | `result_o` | `[DATA_WIDTH - 1:0]` (32 bits) | Arithmetic/logical output result |

#### Key Design Features
- Combinational operation via `always_comb` block with `unique case`.
- Shift operations indexed using low `$clog2(DATA_WIDTH)` bits (lower 5 bits of `operand_b_i` for 32-bit width).
- Explicit sign-extension for arithmetic right shifts (`ALU_SRA`).

---

### 3. Register File (`riscv_regfile.sv`)

#### Parameters
| Parameter | Default | Description |
| :--- | :--- | :--- |
| `DATA_WIDTH` | `32` | Width of each register entry and data ports |

#### Input & Output Ports
| Direction | Port Name | Width / Type | Description |
| :--- | :--- | :--- | :--- |
| **Input** | `clk_i` | `logic` | Clock input |
| **Input** | `rst_i` | `logic` | Active-high asynchronous reset |
| **Input** | `rd0_i` | `[4:0]` | Write register address destination (0–31) |
| **Input** | `rd0_value_i` | `[DATA_WIDTH - 1:0]` (32 bits) | Data to write into register `rd0_i` |
| **Input** | `rd0_wren_i` | `logic` | Write enable signal (active high) |
| **Input** | `ra0_i` | `[4:0]` | Read address select for Port 1 |
| **Input** | `rb0_i` | `[4:0]` | Read address select for Port 2 |
| **Output** | `ra0_value_o` | `[DATA_WIDTH - 1:0]` (32 bits) | Asynchronous read data output for Port 1 |
| **Output** | `rb0_value_o` | `[DATA_WIDTH - 1:0]` (32 bits) | Asynchronous read data output for Port 2 |

#### Key Design Features
- Synchronous write on `posedge clk_i` with check for `rd0_i != 5'b00000`.
- Asynchronous dual read ports for single-cycle execution pipelines.
- Zero-register enforcement: Address `5'b00000` (`x0`) is hardwired to zero on read operations.

---

## 🧪 Testbenches & Verification

### ALU Testbench (`tb_riscv_alu.sv`)
- **Directed Tests**: Verifies `ADD`, `SUB`, `AND`, `OR`, `XOR`, `PASS_B`, signed/unsigned comparisons (`SLT`, `SLTU`), and shifts (`SLL`, `SRL`, `SRA`).
- **Randomized Testing**: Runs 500 constraint-free random test vectors using `$urandom()` and `$urandom_range()` compared against a reference function (`get_expected`).

### Register File Testbench (`tb_riscv_regfile.sv`)
1. **Asynchronous Reset Check**: Confirms all 32 registers reset to zero.
2. **`x0` Immutability Check**: Asserts that writing `0xDEADBEEF` to `x0` leaves its value as `0`.
3. **Read-During-Write (RAW Hazard)**: Evaluates asynchronous read response timing during active write cycles.
4. **Full Sweep & Dual Read**: Writes unique pattern data to registers `x1`–`x31` and reads concurrently via `ra0` and `rb0`.
5. **Write Enable Protection**: Verifies that register values remain unmodified when `rd0_wren_i = 0`.

---
