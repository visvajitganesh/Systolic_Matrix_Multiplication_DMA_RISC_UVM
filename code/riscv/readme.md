# RISCV

---

## 📑 Project Overview

This repository contains parameterizable, synthesizable SystemVerilog modules designed for a standard 32-bit RISC-V processor architecture (RV32I):

- **RISC-V Definitions (`riscv_defs.sv`)**: Macro definitions for opcodes, instruction fields, funct3/funct7 codes, and internal ALU operation codes.
- **Arithmetic Logic Unit (`riscv_alu.sv`)**: Fully combinational unit supporting arithmetic, logical, comparison, shift, and pass-through operations.
- **Register File (`riscv_regfile.sv`)**: Dual-port asynchronous read and single-port synchronous write register file with hardwired `x0 = 0` behavior.
- **Verification Testbenches (`tb_riscv_alu.sv`, `tb_riscv_regfile.sv`)**: Self-checking testbenches with randomized and targeted functional tests.

---

## 🏛️ Directory & Architecture Overview

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
- **Parameter**: `DATA_WIDTH` (Default: 32)
- **Ports**:
  - `input logic [`ALU_OP_W - 1:0] alu_op_i`: Operation select
  - `input logic [DATA_WIDTH - 1:0] operand_a_i`: First operand
  - `input logic [DATA_WIDTH - 1:0] operand_b_i`: Second operand
  - `output logic [DATA_WIDTH - 1:0] result_o`: Computed result
- **Features**:
  - Combinational operation via `always_comb` block with `unique case`.
  - Shift operations indexed using low `$clog2(DATA_WIDTH)` bits (5 bits for 32-bit width).
  - Explicit sign-extension for arithmetic right shifts (`ALU_SRA`).

---

### 3. Register File (`riscv_regfile.sv`)
- **Parameter**: `DATA_WIDTH` (Default: 32)
- **Ports**:
  - `clk_i`, `rst_i`: Clock and active-high asynchronous reset
  - `rd0_i`, `rd0_value_i`, `rd0_wren_i`: Write port address, data, enable
  - `ra0_i`, `ra0_value_o`: Read port 1 address and output data
  - `rb0_i`, `rb0_value_o`: Read port 2 address and output data
- **Features**:
  - Synchronous write on `posedge clk_i` with check for `rd0_i != 5'b00000`.
  - Asynchronous read ports for high-throughput single-cycle execution.
  - Zero-register enforcement: Reading address `5'b00000` hardwires output to `'0`.

---

## 🧪 Testbenches & Verification

### ALU Testbench (`tb_riscv_alu.sv`)
- **Directed Tests**: Tests `ADD`, `SUB`, `AND`, `OR`, `XOR`, `PASS_B`, signed/unsigned comparisons (`SLT`, `SLTU`), and shift variants (`SLL`, `SRL`, `SRA`).
- **Randomized Testing**: Performs 500 constraint-free random test vectors using `$urandom()` and `$urandom_range()` against an automatic reference model function (`get_expected`).

### Register File Testbench (`tb_riscv_regfile.sv`)
1. **Asynchronous Reset Check**: Ensures all 32 registers clear to zero on reset.
2. **`x0` Immutability Check**: Attempts to write `0xDEADBEEF` to `x0` and verifies it stays `0`.
3. **Read-During-Write (RAW Hazard)**: Verifies asynchronous read response timing during write cycles.
4. **Full Sweep & Dual Read**: Writes unique values across registers `x1`–`x31` and reads concurrently via `ra0` and `rb0`.
5. **Write Enable Protection**: Ensures register contents are unchanged when `rd0_wren_i` is disabled.

---


