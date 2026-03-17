# Shipped Features Configuration: "Full" Edition

This document describes the active hardware configuration for the OCP MXFP8 Streaming MAC Unit as of March 2025.

## 1. Overview
The design is currently configured for the **"Full" edition**, targeting a **2x2 tile** footprint on Tiny Tapeout. This edition provides the maximum feature set and numerical precision supported by the architecture.

## 2. Key Features
- **OCP MX Compliance**: Full support for E4M3 and E5M2 formats.
- **High Throughput**: `SUPPORT_VECTOR_PACKING` enabled, allowing dual-lane FP4 processing (1.28 elements/cycle).
- **Research Extensions**: `SUPPORT_MX_PLUS` enabled for outlier precision research.
- **Shared Scaling**: `ENABLE_SHARED_SCALING` enabled for hardware-accelerated block scaling.
- **Mixed Precision**: Independent format control for A and B operands.
- **Advanced Rounding**: Support for TRN, CEL, FLR, and RNE rounding modes.
- **Input Buffering**: 16-entry FIFO for efficient FP4 burst loading.

## 3. Hardware Parameters
| Parameter | Value | Description |
|---|---|---|
| `ALIGNER_WIDTH` | 40 | 40-bit internal alignment path. |
| `ACCUMULATOR_WIDTH` | 32 | 32-bit signed accumulator. |
| `SUPPORT_PIPELINING` | 1 | Enabled for timing closure. |
| `SUPPORT_SERIAL` | 0 | Parallel execution (1 cycle per element). |
| `USE_LNS_MUL` | 0 | Standard combinatorial multiplier. |
| `SUPPORT_DEBUG` | 1 | Real-time metadata and internal probe support. |

## 4. Physical Metrics
- **Gate Count**: ~6,609 cells (IHP SG13G2).
- **Area**: 2x2 Tiles.
- **Throughput**: up to 1.28 MAC ops/cycle (FP4).
