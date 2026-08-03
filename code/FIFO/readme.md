# Accelerator Buffer Interface 

This project implements a hardware buffering system that acts as a bridge between a system DMA (using AXI-Stream) and a high-speed Systolic Array accelerator. It manages independent clock domains and handles the packing/unpacking of data between flat streams and parallel vectors.

## Module Overview

The following table breaks down the individual components and their specific roles within the architecture:

| Module / Interface | Source Code | Description | Key Features |
| :--- | :--- | :--- | :--- |
| **`accel_buffer_top`** | `accel_buffer_top.sv` | The top-level wrapper combining the input and output buffer paths. | Exposes flattened ports for testbenches without needing virtual interfaces. |
| **`async_fifo`** | `async_fifo.sv` | A generic dual-clock asynchronous FIFO. | Uses Gray code pointer conversion, 2-flop synchronizers, and FWFT read style. |
| **`input_buffer`** | `input_buffer.sv` | The data path from the DMA to the Systolic Array. | Unpacks flat AXI-Stream data into per-channel parallel vectors. |
| **`input_buffer_if`** | `input_buffer_if.sv` | The SystemVerilog interface contract for the input path. | Defines specific `modport` directional enforcements for DMA, Array, and Buffer. |
| **`output_buffer`** | `output_buffer.sv` | The data path from the Systolic Array back to the DMA. | Packs unpacked per-channel array data into a single flat bus for storage. |
| **`output_buffer_if`** | `output_buffer_if.sv` | The SystemVerilog interface contract for the output path. | Maps AXI-Stream (`tdata`, `tvalid`) to array signals (`array_data`, `array_valid`). |
| **`tb_accel_buffer_top`** | `tb_accel_buffer_top.sv` | A self-checking testbench to verify the top-level buffer system[cite: 8]. | Simulates independent, unrelated clocks to genuinely stress the CDC (Clock Domain Crossing) logic. |

---

## Architecture Details

### Clock Domain Crossing (CDC)
* Both the input and output buffers rely on `async_fifo` to safely pass data between two independent, non-integer-related clocks: `clk_sys` and `clk_accel`.
* The FIFO depth is parameterized but must strictly be a power of two.
* The asynchronous FIFO utilizes a standard Cliff-Cummings-style design, ensuring safe clock boundary crossings.

### Signal Handling Differences
* **Input Path (`tlast`):** The `tlast` signal from the DMA is not forwarded into the systolic array. It is considered meaningful only to the DMA master itself and is not stored in the FIFO.
* **Output Path (`array_last`):** The `array_last` signal from the systolic array *is* forwarded through to become `tlast`. It is packed alongside the data vector as the MSB to survive the clock domain crossing in lock-step with its corresponding word.

---

## Verification & Testing

The provided `tb_accel_buffer_top` is an automated, self-checking simulation[cite: 8]. It evaluates the buffer's robustness through three distinct testing phases:

* **Phase 1 (Basic Passthrough):** Transmits data through the system at full speed with no backpressure.
* **Phase 2 (Backpressure Stress):** Forces the consumers to stall, allowing the FIFO to fill completely before draining rapidly.
* **Phase 3 (Concurrent Stress):** Applies randomized drive stalls and consumer backpressure simultaneously across both buffers.
* **Automated Checking:** Monitors record every successful push on the sending side into a queue and automatically compare it against every successful pop on the receiving side to verify order, value, and `last` signals.
