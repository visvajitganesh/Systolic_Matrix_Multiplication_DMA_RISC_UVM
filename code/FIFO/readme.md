# Accelerator Buffer Interface (FIFO)

## Overview
This repository contains the RTL implementation of a dual-clock asynchronous buffer interface designed to bridge an AXI-Stream Direct Memory Access (DMA) engine and a parallel Systolic Array accelerator[cite: 24, 27, 29]. 

The design safely handles Clock Domain Crossing (CDC) between the system interconnect clock (`clk_sys`) and a dedicated high-speed accelerator clock (`clk_accel`) using Gray-code synchronized asynchronous FIFOs[cite: 24, 25, 27, 29]. It features independent input (DMA $\rightarrow$ Array) and output (Array $\rightarrow$ DMA) buffering paths[cite: 24].

## Module Instantiation Hierarchy
The system is structured with strict interface contracts isolating the core FIFO logic from the top-level routing[cite: 24, 27, 29].

* **`tb_accel_buffer_top.sv`**: Self-checking testbench driving randomized traffic across dual asynchronous clocks[cite: 30].
  * **`accel_buffer_top.sv`**: Flattened top-level wrapper combining input and output paths[cite: 24].
    * **`input_buffer_if.sv`**: Interface contract for the MM2S path[cite: 27].
    * **`input_buffer.sv`**: Adapts packed DMA streams into unpacked parallel array vectors[cite: 26].
      * **`async_fifo.sv`**: Generic First-Word Fall-Through (FWFT) asynchronous FIFO[cite: 25, 26].
    * **`output_buffer_if.sv`**: Interface contract for the S2MM path[cite: 29].
    * **`output_buffer.sv`**: Adapts parallel array outputs into a packed DMA stream[cite: 28].
      * **`async_fifo.sv`**: Generic FWFT asynchronous FIFO (carries `array_last` flag in MSB)[cite: 25, 28].

## Interface Signals
### 1. Input Buffer Path (DMA $\rightarrow$ Array)
Responsible for accepting AXI-Stream data and feeding it to the systolic array[cite: 26, 27].
* **DMA Side (System Clock Domain)**[cite: 27]:
  * `in_tdata`: Packed stream input from DMA.
  * `in_tvalid` / `in_tready`: Standard AXI-Stream push/backpressure handshake.
  * `in_tlast`: Packet boundary marker (consumed by buffer, not forwarded).
* **Array Side (Accelerator Clock Domain)**[cite: 27]:
  * `in_array_data`: Unpacked 2D array feeding parallel processing elements.
  * `in_array_valid`: Asserts when the FIFO is not empty.
  * `in_array_ready`: Accelerator asserts to pop the next vector.

### 2. Output Buffer Path (Array $\rightarrow$ DMA)
Responsible for capturing systolic results and pushing them to the system memory[cite: 28, 29].
* **Array Side (Accelerator Clock Domain)**[cite: 29]:
  * `out_array_data`: Unpacked 2D array of computed accumulator results.
  * `out_array_valid` / `out_array_ready`: Array push and FIFO backpressure handshake.
  * `out_array_last`: Signals the final resulting matrix block.
* **DMA Side (System Clock Domain)**[cite: 29]:
  * `out_tdata`: Packed stream output to DMA.
  * `out_tvalid` / `out_tready`: Standard AXI-Stream handshake.
  * `out_tlast`: Propagated packet completion token (derived from `array_last`).

## Data Widths & Configurations
The module utilizes configurable parameters to manage the data width disparity between the 8-bit inputs and the 32-bit accumulated outputs[cite: 24].

**Default Input Configuration (DMA $\rightarrow$ Array):**
* `IN_DATA_WIDTH` = 8 bits[cite: 24]
* `IN_NUM_CHANNELS` = 8 channels[cite: 24]
* `IN_DEPTH` = 16 entries[cite: 24]
* **Total Packed Input Bus Width** = 64 bits[cite: 24, 26]

**Default Output Configuration (Array $\rightarrow$ DMA):**
* `OUT_DATA_WIDTH` = 32 bits[cite: 24]
* `OUT_NUM_CHANNELS` = 8 channels[cite: 24]
* `OUT_DEPTH` = 16 entries[cite: 24]
* **Total Packed Output Bus Width** = 256 bits[cite: 24, 28]

## Testbench & Verification
The provided `tb_accel_buffer_top.sv` is a fully automated, self-checking testbench[cite: 30]. It utilizes two free-running, non-integer-related clocks (`clk_sys` at 100 MHz and `clk_accel` at ~142 MHz) to genuinely stress the CDC logic[cite: 30]. 

The verification sequence executes in three phases[cite: 30]:
1. **Basic Passthrough:** Full-speed pushing and popping without backpressure[cite: 30].
2. **Backpressure Stress:** Deliberately stalls consumers to fill FIFOs to capacity, then drains them rapidly[cite: 30].
3. **Concurrent Stress:** Highly randomized driver stalls and consumer backpressure running simultaneously on both paths[cite: 30].
