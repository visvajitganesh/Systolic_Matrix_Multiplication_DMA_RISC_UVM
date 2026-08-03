# Accelerator Buffer Interface 

This project implements a hardware buffering system that acts as a bridge between a system DMA (using AXI-Stream) and a high-speed Systolic Array accelerator[cite: 1, 5]. It manages independent clock domains and handles the packing/unpacking of data between flat streams and parallel vectors[cite: 1, 4, 6].

## Module Overview

The following table breaks down the individual components and their specific roles within the architecture:

| Module / Interface | Source Code | Description | Key Features |
| :--- | :--- | :--- | :--- |
| **`accel_buffer_top`** | `accel_buffer_top.sv` | The top-level wrapper combining the input and output buffer paths[cite: 1]. | Exposes flattened ports for testbenches without needing virtual interfaces[cite: 1]. |
| **`async_fifo`** | `async_fifo.sv` | A generic dual-clock asynchronous FIFO[cite: 2]. | Uses Gray code pointer conversion, 2-flop synchronizers, and FWFT read style[cite: 2]. |
| **`input_buffer`** | `input_buffer.sv` | The data path from the DMA to the Systolic Array[cite: 4]. | Unpacks flat AXI-Stream data into per-channel parallel vectors[cite: 4]. |
| **`input_buffer_if`** | `input_buffer_if.sv` | The SystemVerilog interface contract for the input path[cite: 5]. | Defines specific `modport` directional enforcements for DMA, Array, and Buffer[cite: 5]. |
| **`output_buffer`** | `output_buffer.sv` | The data path from the Systolic Array back to the DMA[cite: 6]. | Packs unpacked per-channel array data into a single flat bus for storage[cite: 6]. |
| **`output_buffer_if`** | `output_buffer_if.sv` | The SystemVerilog interface contract for the output path[cite: 7]. | Maps AXI-Stream (`tdata`, `tvalid`) to array signals (`array_data`, `array_valid`)[cite: 7]. |
| **`tb_accel_buffer_top`** | `tb_accel_buffer_top.sv` | A self-checking testbench to verify the top-level buffer system[cite: 8]. | Simulates independent, unrelated clocks to genuinely stress the CDC (Clock Domain Crossing) logic[cite: 8]. |

---

## Architecture Details

### Clock Domain Crossing (CDC)
* Both the input and output buffers rely on `async_fifo` to safely pass data between two independent, non-integer-related clocks: `clk_sys` and `clk_accel`[cite: 1, 8].
* The FIFO depth is parameterized but must strictly be a power of two[cite: 2].
* The asynchronous FIFO utilizes a standard Cliff-Cummings-style design, ensuring safe clock boundary crossings[cite: 2].

### Signal Handling Differences
* **Input Path (`tlast`):** The `tlast` signal from the DMA is not forwarded into the systolic array[cite: 4]. It is considered meaningful only to the DMA master itself and is not stored in the FIFO[cite: 4].
* **Output Path (`array_last`):** The `array_last` signal from the systolic array *is* forwarded through to become `tlast`[cite: 6]. It is packed alongside the data vector as the MSB to survive the clock domain crossing in lock-step with its corresponding word[cite: 6].

---

## Verification & Testing

The provided `tb_accel_buffer_top` is an automated, self-checking simulation[cite: 8]. It evaluates the buffer's robustness through three distinct testing phases:

* **Phase 1 (Basic Passthrough):** Transmits data through the system at full speed with no backpressure[cite: 8].
* **Phase 2 (Backpressure Stress):** Forces the consumers to stall, allowing the FIFO to fill completely before draining rapidly[cite: 8].
* **Phase 3 (Concurrent Stress):** Applies randomized drive stalls and consumer backpressure simultaneously across both buffers[cite: 8].
* **Automated Checking:** Monitors record every successful push on the sending side into a queue and automatically compare it against every successful pop on the receiving side to verify order, value, and `last` signals[cite: 8].
