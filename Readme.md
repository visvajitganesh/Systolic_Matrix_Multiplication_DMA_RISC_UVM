# Synopsys Design Constraints (SDC)

This directory contains the Synopsys Design Constraints (SDC) files used to define the timing, power, and area specifications for the synthesis and physical design phases of the project.

## Directory Contents

*   **`system_top.sdc`**: The top-level constraint file for the entire SoC. It defines the primary system clocks, external I/O delays, false paths, and clock domain crossing constraints for the integrated top-level design.
*   **`dma.sdc`**: Contains the specific timing constraints, clock definitions, and interface delays tailored for the Direct Memory Access (DMA) engine block.
*   **`systolic.sdc`**: Contains block-level constraints specifically for the hardware-accelerated systolic array subsystem to ensure it meets its specific frequency and performance targets.
