# Gap Analysis: OCP MXFP8 Streaming MAC Unit vs. ebby-s/MX-for-FPGA

This document analyzes the architectural and functional differences between this implementation (the **OCP MXFP8 Streaming MAC Unit**) and the [ebby-s/MX-for-FPGA](https://github.com/ebby-s/MX-for-FPGA) repository.

## 1. High-Level Comparison

| Feature | OCP MXFP8 Streaming MAC (This Repo) | ebby-s/MX-for-FPGA |
|:---|:---|:---|
| **Primary Target** | ASIC (Tiny Tapeout / IHP SG13G2) | FPGA (General Purpose) |
| **Philosophy** | Integrated, Protocol-driven IP Block | Modular SystemVerilog Component Library |
| **Data Flow** | **Temporal (Streaming)** over 41 cycles | **Spatial (Parallel)** Combinatorial/Pipelined |
| **Implementation** | Verilog-2001 (Strict compatibility) | SystemVerilog |
| **Optimization** | Minimal Gate Count (1x2 Tile focus) | FPGA Resource (LUT/DSP) Mapping |

---

## 2. Architectural Differences

### 2.1. Streaming vs. Parallel Processing
The most significant gap is in the **data-processing strategy**:
- **This Implementation**: Uses a **Temporal Multiplexing** approach. Elements are streamed into a single MAC core over 32 cycles. This minimizes area by reusing one multiplier and one aligner, making it ideal for the extreme area constraints of Tiny Tapeout.
- **MX-for-FPGA**: Appears to implement **Parallel Dot Products** (e.g., `dot_fp8_32x32.sv`). These modules likely perform 32 multiplications in parallel in a single cycle or a short pipeline, requiring significantly more hardware resources (multipliers/adders) but achieving orders-of-magnitude higher throughput.

### 2.2. Protocol & FSM
- **This Implementation**: Built around a strict **41-cycle FSM protocol**. It handles scale loading, element streaming, and result serialization autonomously.
- **MX-for-FPGA**: Functions more as a standard logic library. Users must instantiate the modules and handle the timing/data-valid signals externally.

---

## 3. Numerical & Feature Gap

### 3.1. Rounding Modes
- **This Implementation**: Supports the four standard OCP MX rounding modes: **TRN** (Truncate), **CEL** (Ceil), **FLR** (Floor), and **RNE** (Round-to-Nearest-Ties-to-Even).
- **MX-for-FPGA**: Includes support for **Stochastic Rounding**, which is highly beneficial for deep learning training but more complex to implement in hardware (requires a PRNG).

### 3.2. Format Support & Conversion
- **This Implementation**: Focuses on **Compute**. It supports 7 formats (MXFP8/6/4 and MXINT8) but expects the input to be already in MX format.
- **MX-for-FPGA**: Includes **Format Converters** (e.g., `conv_bf16tomxfp8`). This makes it a more comprehensive tool for system integration where data starts in a standard format like BFloat16.

### 3.3. Shared Scaling
- **This Implementation**: Features **Hardware-Accelerated Shared Scaling**. It reuses the internal aligner path in Cycle 36 to apply the shared $2^{(X_A+X_B)}$ scale factor before outputting the result.
- **MX-for-FPGA**: While it supports shared exponents, the scaling logic is typically part of the wide dot-product reduction tree.

---

## 4. Resource & Platform Optimization

### 4.1. ASIC Gate Count vs. FPGA LUTs
- **This Implementation**: Optimized for **Gate Density** and **Timing Closure** on the IHP SG13G2 process. It uses specific optimizations like Prefix-OR sticky bit trees and parameterized internal widths (`WIDTH=40`) to fit within ~3500 gates.
- **MX-for-FPGA**: Designed for FPGAs, where the cost of a 32-bit adder or an 8-bit multiplier is handled differently (often mapped to specialized DSP slices or LUT-based carry chains).

### 4.2. Parameterization
- **This Implementation**: Features aggressive **Pruning Parameters** (`SUPPORT_MXFP6`, `SUPPORT_ADV_ROUNDING`, etc.) to allow the design to scale down to "Tiny" or "Ultra-Tiny" variants for smaller tiles.
- **MX-for-FPGA**: Uses SystemVerilog parameters primarily for width and block size configuration.

---

## 5. Conclusion

The two implementations serve different roles in the OCP MX ecosystem:
- **This project** is a highly-optimized **ASIC IP block** designed for low-area, low-pin-count integration (like Tiny Tapeout). It is an "end-to-end" unit with its own communication protocol.
- **ebby-s/MX-for-FPGA** is a powerful **development library** for FPGA-based acceleration, offering higher throughput via parallelism, advanced rounding (stochastic), and helpful conversion utilities.
