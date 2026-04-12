# Comparison: Snitch Accelerator vs. TT-IHP FP8 MAC

This document compares the architectural and functional differences between the **Snitch Core Accelerator** (from PULP Platform) and the **Tiny Tapeout IHP (TT-IHP) FP8 Streaming MAC** implementation.

## 1. Architectural Paradigms

| Feature | Snitch Accelerator | TT-IHP FP8 MAC |
|---------|--------------------|----------------|
| **Control Flow** | **Instruction-Driven**: Offloads RISC-V instructions (RV32F/D, Xfrep) via a decoupled AXI-like valid/ready interface. | **Protocol-Driven**: Operates on a fixed cycle-based protocol (Cycle 0: Config, Cycles 1-2: Scales, Cycles 3-34: Data). |
| **Execution Model** | **Asynchronous**: Instructions are queued and retired via a scoreboard; completion time varies by operation. | **Deterministic/Pipelined**: Fixed latency per block (23-40 cycles depending on protocol mode). |
| **Sequencing** | **Hardware Sequencer**: Uses `snitch_sequencer` to repeat instructions (`frep`) with register staggering. | **Implicit Streaming**: Processes a block of 32 elements automatically once started. |

## 2. Data Movement & Memory Interface

| Feature | Snitch Accelerator | TT-IHP FP8 MAC |
|---------|--------------------|----------------|
| **Interface** | **TCDM / Register File**: Uses Stream Semantic Registers (SSR) to map memory addresses to registers. | **IO Pins (Streaming)**: Direct element-by-element streaming via 8-bit ports (`ui_in`, `uio_in`). |
| **Buffering** | **FIFO-based**: Uses `fifo_v3` for credit-based flow control between memory and functional units. | **Register-based**: Minimal internal buffering; optionally supports a 16-deep input FIFO for FP4 vector modes. |
| **Output** | **Register Writeback**: Results are written back to a local register file or returned via the accelerator bus. | **Serialized Byte-Stream**: Final 32-bit accumulated result is shifted out byte-by-byte at the end of the block. |

## 3. Numerical Formats & Arithmetic

| Feature | Snitch Accelerator | TT-IHP FP8 MAC |
|---------|--------------------|----------------|
| **Standard Formats** | IEEE 754 (FP32, FP64), FP16, BFloat16, FP8 (E4M3/E5M2). | OCP MX Formats (E4M3, E5M2, MXFP6, MXFP4), INT8. |
| **Advanced Formats** | Standard float/integer formats via the `fpnew` library. | **OCP MX Microscaling**: Block-based scaling factors. **LNS**: Logarithmic Number System (Mitchell's approx). |
| **Special Features** | Vectorial operations (SIMD), Nan-boxing. | **MX+ Extension**: Per-element microscaling. **Hybrid LNS**: Combined linear/logarithmic modes. |

## 4. Hardware Implementation & Complexity

| Feature | Snitch Accelerator | TT-IHP FP8 MAC |
|---------|--------------------|----------------|
| **Complexity** | **High**: Designed for high-performance clusters; thousands of gates per lane. | **Ultra-Low**: Optimized for Tiny Tapeout (~1100-1400 gates total). |
| **Dependencies** | Requires a RISC-V core (Snitch) and a Tightly Coupled Data Memory (TCDM). | **Standalone**: Can be controlled by a simple GPIO-based state machine or a small MCU. |
| **Target Technology** | ASIC (GlobalFoundries 22nm, etc.) | IHP SG13G2 (Open-source PDK). |

## Summary

The **Snitch Accelerator** is a high-performance, instruction-set-driven unit designed for complex scientific computing where a full CPU core manages the workload. It excels in flexibility and integration with a standard software stack.

The **TT-IHP FP8 MAC** is a specialized, area-optimized streaming processor. It is designed for high-efficiency AI inference and quantization research, where data is pushed through a fixed pipeline with minimal control overhead. Its support for OCP MX and LNS formats makes it a unique platform for low-power numerical experimentation.
