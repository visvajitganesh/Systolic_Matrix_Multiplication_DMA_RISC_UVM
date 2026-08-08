# AXI-Integrated Systolic Acceleration Engine

A hardware-accelerated **4×4 Output-Stationary Systolic Array** for matrix multiplication, integrated into an **AMBA AXI4 System-on-Chip (SoC) subsystem** with a custom DMA engine and dual-clock asynchronous CDC FIFOs. Built in SystemVerilog, verified with both a directed testbench and a full **UVM (IEEE 1800.2)** coverage-driven environment, and validated end-to-end in Xilinx Vivado.

> Project Report: *AXI-Integrated Systolic Acceleration Engine* — C-DAC ACTS, Pune (PG-DVLSI)
> Guided by: Mr. Sajish Chandrababu
> Team: Ganisetti Gunadham · Partha Pratim Mishra · Shashwat Kanth · Shraddha Sahoo · Visvajit Ganesh

---

## Table of Contents

- [Overview](#overview)
- [Why This Exists](#why-this-exists)
- [Architecture](#architecture)
- [Key Results](#key-results)
- [Register Map](#register-map)
- [Repository Structure](#repository-structure)
- [Theory in Brief](#theory-in-brief)
- [Getting Started](#getting-started)
- [Verification](#verification)
- [Hardware / Resource Utilization](#hardware--resource-utilization)
- [Roadmap](#roadmap)
- [References](#references)
- [License](#license)

---

## Overview

General-purpose RISC processors are inefficient at dense linear algebra: every multiply-accumulate (MAC) in a nested-loop `C = A × B` costs an instruction fetch/decode/memory-access cycle, and matrix multiplication is inherently `O(N³)`. This project offloads that workload to a dedicated **spatial hardware accelerator** — a systolic array — fully integrated into an AXI4-based SoC so any standard RISC host (RISC-V, ARM, MicroBlaze) can drive it through memory-mapped I/O.

**Core building blocks:**

| Block | File | Role |
|---|---|---|
| AXI4-Lite register slave + AXI4 Master DMA | `dma.sv` | Host-programmable control registers; autonomous MM2S/S2MM burst engine |
| Async CDC FIFOs | `accel_fifo.sv` | Gray-coded dual-clock bridge (100 MHz ↔ 200 MHz) |
| Stream FSM Adapter | `stream_adapter.sv` | Serializes/deserializes 4-bit nibble stream ↔ 128-bit parallel matrix vector |
| Input skew / output un-skew chains | `d_ff_chain.sv` | Aligns wave-front data timing into/out of the array |
| Processing Element | `processing_element.sv` | 4-bit × 4-bit MAC cell, output-stationary accumulation |
| 4×4 Systolic Array top | `systolic.sv` | Interconnects 16 PEs into the compute grid |
| SoC top | `soc_top.sv` | Wires DMA, CDC FIFOs, adapter, and array together |

---

## Why This Exists

- **Memory wall**: CPUs stall repeatedly fetching operands for `O(N³)` MACs.
- **Bus translation**: A compute engine can't talk to a CPU/memory directly — needs AXI4-Lite (control) and AXI4 Master (bulk transfer).
- **Clock domain mismatch**: The compute-dense array wants to run faster (200 MHz) than the system bus (100 MHz) — this needs safe, metastability-free clock domain crossing (CDC).

This project solves all three with a modular, reusable, protocol-compliant subsystem — see [`Chapter 1` / `Chapter 9`](#references) of the full report for the detailed gap analysis versus existing literature.

---

## Architecture

```
 SYSTEM CLOCK DOMAIN (clk_sys = 100 MHz)
 ┌─────────────────────┐        AXI4-Lite        ┌──────────────────────────────┐
 │   RISC Host CPU      │◄───────(32-bit regs)───►│      Custom AXI4 DMA Engine   │
 │  (Control / MMIO)    │                          │  MM2S Reader  │ S2MM Writer  │
 └─────────────────────┘                          └───────┬───────┴──────┬───────┘
 ┌─────────────────────┐        AXI4 Master               │ 4-bit nibble │ 4-bit nibble
 │  System BRAM / RAM   │◄─────(burst read/write)──────────┘ stream       │ stream
 └─────────────────────┘                                   ▼              ▲
 ───────────────────────────────── CDC BOUNDARY ──── In CDC FIFO ── Out CDC FIFO ───
 ACCELERATOR CLOCK DOMAIN (clk_accel = 200 MHz)              │              ▲
                                                              ▼              │
                                              ┌───────────────────────────────────┐
                                              │      Stream FSM Adapter           │
                                              │  (COLLECT → COMPUTE → STREAM)     │
                                              └───────────────┬───────────────────┘
                                             128-bit vector (A‖B)
                                                              ▼
                                    ┌──────────────────────────────────────────┐
                                    │  Input Skewing Chain → 4×4 Output-        │
                                    │  Stationary Systolic PE Array →           │
                                    │  Output Un-skewing Chain                  │
                                    └──────────────────────────────────────────┘
```

### Data flow, step by step

1. **Configure** — host writes `SRC_ADDR`, `DEST_ADDR`, `LENGTH` over AXI4-Lite, then pulses `CONTROL[0]` (START).
2. **MM2S read** — DMA reads matrices `A`/`B` from BRAM via AXI4 Master bursts, unpacks 32-bit words into 4-bit nibbles, pushes into the **input CDC FIFO**.
3. **CDC crossing** — Gray-coded write/read pointers with 2-FF synchronizers safely move data from 100 MHz → 200 MHz.
4. **Collect & compute** — the Stream Adapter FSM reconstructs a 128-bit vector (64-bit `A` ‖ 64-bit `B`), skews it into the systolic array, and runs the wave-front MAC computation (`3N − 2 = 10` cycles for `N = 4`).
5. **Stream out** — results are un-skewed, serialized into nibbles, and pushed into the **output CDC FIFO**.
6. **S2MM write-back** — DMA reassembles 32-bit words and bursts the result matrix `C` back to BRAM, then raises `STATUS[1]` (DONE) / `dma_irq`.

### Why Output-Stationary?

The accumulator (`c[i][j]`) stays fixed inside each PE for the full dot-product; only 4-bit operands stream through the grid. This avoids routing wide, high-switching accumulator buses across the array — lower dynamic power, less routing congestion — versus Weight-Stationary or Input-Stationary designs (see [`Section 9.1`](#references)).

### Why Gray-coded async FIFOs for CDC?

Binary write/read pointers can change multiple bits at once across a clock boundary, causing multi-bit convergence hazards. Gray code guarantees only **one bit changes per increment**, so a 2-FF synchronizer can only ever sample a valid old or new pointer value — never a corrupted intermediate one.

```
FULL  (write domain):  wptr_g == {~rptr_g_sync[N:N-1], rptr_g_sync[N-2:0]}
EMPTY (read domain):   rptr_g == wptr_g_sync
```

---

## Key Results

Simulated end-to-end in Xilinx Vivado (behavioral simulation), self-checked against a software golden model:

| Metric | Software (RISC CPU @ 100 MHz) | Hardware Accelerator | Gain |
|---|---|---|---|
| Clock cycles | ~480 (nested loops) | 68 (end-to-end) | **7.05× fewer** |
| Execution latency | 4,800 ns | 340 ns | **14.1× reduction** |
| Host CPU utilization | 100% (stalled) | < 2% (5 MMIO writes only) | **98% offloaded** |

**Functional correctness:** `16/16` matrix elements matched the golden reference with 0 mismatches.

**UVM verification suite:** 100% functional coverage (12/12 coverbins), 14,200/14,200 SVA assertions passed, 0 errors/fatals.

---

## Register Map

AXI4-Lite slave, 32-bit registers, programmed by the host:

| Offset | Register | R/W | Description |
|---|---|---|---|
| `0x00` | `SRC_ADDR` | R/W | Base address of input matrices `A`, `B` in BRAM/RAM |
| `0x02` | `DEST_ADDR` | R/W | Base address for output matrix `C` |
| `0x04` | `LENGTH` | R/W | Transfer length in bytes |
| `0x06` | `CONTROL` | R/W | `[0]` START pulse · `[1]` CLEAR pulse (reset accumulators) |
| `0x08` | `STATUS` | R | `[0]` BUSY · `[1]` DONE |

**Typical driver sequence:**
```c
write(SRC_ADDR,  0xC0000000);
write(DEST_ADDR, 0xC0000100);
write(LENGTH,    0x00000010);
write(CONTROL,   0x00000001);   // START
while (!(read(STATUS) & 0x2));  // poll DONE (or use dma_irq)
```

---

## Repository Structure

```
.
├── rtl/
│   ├── soc_top.sv               # Top-level SoC integration
│   ├── dma.sv                   # AXI4-Lite slave + AXI4 Master DMA (MM2S/S2MM FSMs)
│   ├── accel_fifo.sv            # Async Gray-coded CDC FIFO
│   ├── stream_adapter.sv        # Nibble ↔ 128-bit vector FSM adapter
│   ├── d_ff_chain.sv            # Parametric input-skew / output-unskew delay chains
│   ├── processing_element.sv    # Single PE (MAC, output-stationary)
│   └── systolic.sv              # 4×4 PE array structural top
├── tb/
│   ├── tb_system_top.sv         # Self-checking directed testbench
│   └── uvm/
│       ├── axi_lite_transaction.sv
│       ├── matrix_transaction.sv
│       ├── matrix_accel_if.sv
│       ├── axi_config_sequence.sv
│       ├── matrix_virtual_sequence.sv
│       ├── matrix_virtual_sequencer.sv
│       ├── axi_lite_driver.sv
│       ├── axi_lite_monitor.sv
│       ├── systolic_monitor.sv
│       ├── axi_lite_agent.sv
│       ├── matrix_accel_scoreboard.sv
│       ├── matrix_accel_env.sv
│       ├── matrix_accel_test.sv
│       ├── matrix_coverage.sv    # Functional coverage groups
│       └── tb_uvm_top.sv         # UVM top-level module
├── bd/
│   └── system_top.bd / .tcl     # Vivado IP Integrator block design + automation script
├── docs/
│   └── PROJECT_REPORT.pdf       # Full project report (this README summarizes it)
└── README.md
```

> Adjust paths above to match your actual repo layout — this mirrors the module names referenced throughout the project report.

---

## Theory in Brief

<details>
<summary><strong>AXI4 handshake rule</strong></summary>

A transfer occurs iff `VALID` and `READY` are both sampled HIGH on the same rising clock edge:

```
Transfer(t) = VALID(t) · READY(t) · ↑CLK
```

AXI4-Lite is used for control (fixed burst length = 1, no out-of-order execution) since it minimizes logic overhead for MMIO register access.
</details>

<details>
<summary><strong>Wave-front skewing</strong></summary>

To let `a[i][k]` and `b[k][j]` arrive at `PE(i,j)` on the correct cycle:

```
Delay(a[i][k]) = i cycles      Delay(b[k][j]) = j cycles
```

Row 0 of `A` enters with 0 delay, row 1 with 1 D-flip-flop, row 2 with 2, row 3 with 3 — same pattern for columns of `B`. Outputs are un-skewed with `Unskew_Delay(c[i][j]) = (N-1) - j` so all 16 results emerge in spatial alignment.
</details>

<details>
<summary><strong>PE datapath</strong></summary>

```
psum_out = psum_in + (A_in × B_in)
```
Each PE forwards `A_in` right and `B_in` down every clock, accumulates locally, and clears on `clr` at the start of a new frame.
</details>

Full derivations, timing diagrams, and Gray-code math are in `docs/PROJECT_REPORT.pdf` (Chapter 4).

---

## Getting Started

### Prerequisites
- AMD Xilinx Vivado Design Suite (v2023.2 / v2024.1) — for synthesis, IP Integrator, and XSim
- SystemVerilog-2017 compatible simulator (XSim / Questa / VCS)
- Target device used in this project: `xc7z020clg400-1` (Zynq-7000, ZedBoard/PYNQ-Z1 class)

### Simulate the directed testbench
```tcl
# In Vivado Tcl console, from the project root
vivado -mode batch -source scripts/run_sim.tcl
# or, inside Vivado GUI:
# 1. Add all rtl/*.sv and tb/tb_system_top.sv as simulation sources
# 2. Set tb_system_top as the top module
# 3. Run Behavioral Simulation
```

Expected console tail:
```
*** TEST PASSED: 16/16 Matrix Elements Calculated Correctly with 0 Mismatches! ***
```

### Run the UVM suite
```tcl
# Set tb_uvm_top as the simulation top, ensure UVM library is enabled
run_test("matrix_accel_test")
```

Expected summary:
```
Functional Coverage : 100.0% (12/12 Coverbins Covered)
*** UVM TEST PASSED: ALL HARDWARE RESULTS MATCH GOLDEN MODEL ***
```

### Build the block design
Use `bd/system_top.tcl` to regenerate the Vivado IP Integrator block design (custom SoC IP + AXI BRAM Controller + Clocking Wizard) automatically.

---

## Verification

Two complementary verification approaches are included:

1. **Directed SystemVerilog testbench** (`tb_system_top.sv`) — emulates a RISC host driving AXI-Lite writes, checks the computed matrix against an expected result computed in the testbench.
2. **UVM environment** (IEEE 1800.2) — constrained-random stimulus, TLM-connected agents for the AXI4-Lite control path and the systolic output path, a scoreboard with an embedded golden reference model, functional coverage groups, and SystemVerilog Assertions (SVA) for:
   - AXI4-Lite `VALID` stability under back-pressure
   - CDC FIFO overflow/underflow safety

```
UVM_INFO ... [SCOREBOARD] Total Test Frames Checked : 1
UVM_INFO ... [SCOREBOARD] Total Successful Matches   : 1
UVM_INFO ... [SCOREBOARD] Total Mismatches / Errors  : 0
```

---

## Hardware / Resource Utilization

Post-synthesis, targeting `xc7z020clg400-1`:

| Resource | Used | Available | % | Allocation |
|---|---|---|---|---|
| LUTs | 1,420 | 53,200 | 2.67% | DMA FSMs, stream adapter, async FIFO logic |
| FFs | 1,850 | 106,400 | 1.74% | PEs, 2-FF CDC synchronizers, skew chains |
| BRAM (36k) | 0.5 | 140 | 0.36% | CDC FIFO data buffers |
| DSP48E1 | 16 | 220 | 7.27% | 4×4 PE grid MAC units |

**Power (est. @ 25 °C):** 156 mW total (122 mW static, 28 mW clocking/logic, 6 mW DSP/BRAM).

---

## Roadmap

- [ ] **Dynamic matrix tiling** for arbitrary `N × N` via block-matrix decomposition and 2D stride DMA addressing
- [ ] **Reconfigurable precision** — runtime-selectable INT4/INT8, BF16, and FP32 PE modes
- [ ] **Scatter-Gather DMA + AXI4-Stream** ring interconnect for chaining multiple systolic tiles into an NPU cluster
- [ ] **ASIC tape-out path** — OpenROAD/Synopsys synthesis, RISC-V SoC integration (Chipyard/Rocket Chip/SweRV)

---

## References

Selected sources (full bibliography in the project report):

1. Kung, H. T., & Leiserson, C. E. (1978). *Systolic Arrays (for VLSI)*. SIAM Sparse Matrix Proceedings.
2. ARM Limited. (2021). *AMBA AXI and ACE Protocol Specification*. ARM IHI 0022E.
3. Cummings, C. E. (2002). *Simulation and Synthesis Techniques for Asynchronous FIFO Design*. SNUG San Jose.
4. IEEE Std 1800.2-2020 — *Universal Verification Methodology (UVM) Language Reference Manual*.
5. Waterman, A., & Asanović, K. (2019). *The RISC-V Instruction Set Manual, Volume I*. RISC-V International.
6. AMD Xilinx. *Zynq-7000 SoC Technical Reference Manual*, UG585.

---

## License

Add a license of your choice (e.g., MIT/Apache-2.0) before publishing — none is currently specified in the source report.

---

*Developed as part of the Post Graduate Diploma in VLSI Design (PG-DVLSI), C-DAC ACTS, Pune.*
