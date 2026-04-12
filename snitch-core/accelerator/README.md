# Snitch Accelerator Interface Implementations

This directory contains various accelerator implementations and interface logic for the Snitch core. Snitch utilizes a decoupled execution model, where complex or long-latency operations are offloaded to specialized hardware units via a standardized **Accelerator Interface**.

## Directory Contents

### Floating-Point Unit (FPU)
- `snitch_fpu.sv`: The core FPU wrapper.
- `snitch_fp_ss.sv`: Floating-point subsystem, integrating the FPU with the Snitch accelerator interface.

### Integer Processing Unit (IPU)
- `snitch_int_ss.sv`: Integer subsystem.
- `snitch_ipu_alu.sv`: ALU for the integer subsystem.
- `snitch_ipu_pkg.sv`: Package defining IPU-specific types and constants.

### Stream Semantic Registers (SSR)
- `snitch_ssr.sv`: Implementation of Stream Semantic Registers, which allow for efficient streaming of data from memory directly into functional units, bypassing explicit load/store instructions.
- `snitch_ssr_pkg.sv`: Package for SSR-related definitions.

### Direct Memory Access (DMA)
- `axi_dma_tc_snitch_fe.sv`: AXI DMA Tightly-Coupled front-end for Snitch, allowing the core to issue DMA transfers.
- `axi_dma_pkg.sv`: Package for DMA-related definitions.

### Shared Multiplier/Divider (MULDIV)
- `snitch_shared_muldiv.sv`: A shared unit for performing integer multiplication and division, offloaded from the main Snitch pipeline.

### Infrastructure
- `snitch_sequencer.sv`: Manages the sequencing of instructions to accelerators, ensuring correct retirement and scoreboard updates.
- `SOURCES.txt`: Tracks the upstream origin of these source files from the PULP Snitch project.

## The Accelerator Interface

The Snitch core offloads instructions using a request/response handshake:

1.  **Request (`acc_qreq_o`)**: When the core decodes an offloadable instruction, it sends the operation details (instruction word, operands from GPR) to the accelerator.
2.  **Execution**: The accelerator processes the request. The Snitch core can continue fetching and executing subsequent instructions that do not have a data dependency on the outstanding operation (tracked via the Scoreboard).
3.  **Response (`acc_prsp_i`)**: Once complete, the accelerator sends the result back to the core. The core then writes the result to the destination register and clears the corresponding scoreboard bit.

This architecture allows for high performance by overlapping computation and memory access while keeping the main integer core simple and area-efficient.
