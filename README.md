# Team_7_CDAC_VLSI
The Master Project Repository
# AXI-Lite DMA Engine for Systolic Array Accelerator
A lightweight, high-performance Direct Memory Access (DMA) engine designed to offload data transfer between system memory (BRAM) and a 4 X 4 Systolic Array Matrix Multiplication Accelerator.By handling memory fetching and stream generation in hardware, this DMA module frees the host RISC core from manually feeding matrix operands into the accelerator.
# 📌 Features
AXI-Lite Slave Interface: Handles register configuration (start/stop, source address, destination address, transfer length) from the RISC CPU.
Auto-Streaming Engine: Automatically reads matrix operands from BRAM and formats/streams them to the Systolic Array edges with proper skew delays.
Dual-Buffer Support: Manages separate memory spaces for input matrices (A and B) and output results (C).
Interrupt / Status Signaling: Generates done and busy status signals/interrupts to notify the RISC CPU upon matrix multiplication completion.
Lightweight Hardware Footprint: Optimized for low gate-count and easy synthesis in ASIC/FPGA physical design flows.
