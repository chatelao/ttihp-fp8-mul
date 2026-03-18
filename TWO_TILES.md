# Active 2-Tile Configuration: OCP MX-Vector Full

This document describes the active **4-tile (2x2)** configuration for the OCP MXFP8 Streaming MAC Unit on Tiny Tapeout, known as the **"Full" edition**. This configuration provides the maximum feature set and numerical precision supported by the architecture.

## 1. Configuration Summary: "OCP MX-Vector Full"

The "OCP MX-Vector Full" variant is designed for maximum throughput, precision, and research flexibility. It includes all major architectural features, including dual-lane vector packing and MX+ research extensions.

| Parameter | Value | Reason |
|---|---|---|
| **Tile Size** | **2x2** | Accommodates high logic density (~6,609 gates). |
| `SUPPORT_VECTOR_PACKING` | `1` | **High Performance**: Enables 1.28x - 1.64x throughput for FP4. |
| `SUPPORT_E4M3` | `1` | Core OCP format support. |
| `SUPPORT_E5M2` | `1` | Standard FP8 format support. |
| `SUPPORT_MXFP4` | `1` | High-throughput 4-bit format support. |
| `ENABLE_SHARED_SCALING` | `1` | Hardware-accelerated block scaling. |
| `SUPPORT_MX_PLUS` | `1` | Research extension for outlier precision. |
| `SUPPORT_PIPELINING` | `1` | Higher clock frequencies ($F_{max}$). |
| `ALIGNER_WIDTH` | 40 | Full precision alignment. |
| `ACCUMULATOR_WIDTH` | 32 | Full 32-bit accumulation. |

## 2. Area and Gate Analysis

The measured gate count for this configuration is approximately **6,609 gates** (IHP SG13G2).

| Feature | Status |
|---|---|
| **Baseline (Full)** | Enabled |
| `SUPPORT_MX_PLUS` | Enabled |
| `SUPPORT_INT8` | Enabled |
| `SUPPORT_MXFP6` | Enabled |
| `SUPPORT_ADV_ROUNDING` | Enabled |
| **Total Measured Gates** | **6,609** |

## 3. Performance Benefits

### 3.1. Throughput (Elements per Clock Cycle)

By enabling `SUPPORT_VECTOR_PACKING`, this configuration significantly outperforms 1-lane variants when using FP4 operands.

| Configuration | Format | Cycles | Throughput (Elem/Cycle) |
|---|---|---|---|
| 1-Tile (Tiny/Lite) | FP4 | 41 | 0.78 |
| **4-Tile (Full Edition)** | **FP4** | **25** | **1.28** |

### 3.2. Hardware-Accelerated Scaling

The inclusion of `ENABLE_SHARED_SCALING` allows the unit to perform 32-bit absolute value and shift operations in hardware (Cycle 36 or 20), offloading this computationally expensive task from the host processor.

## 4. Why 4 Tiles?

A 4-tile (2x2) footprint is required for the "Full" edition to ensure:
1. **Feature Completeness**: All OCP-MX and research features (MX+) fit comfortably.
2. **Timing Closure**: `SUPPORT_PIPELINING` and wide datapaths (40-bit aligner, 32-bit accumulator) meet timing on IHP SG13G2 at target frequencies.
3. **Routing Reliability**: Prevents congestion failures (GPL/DPL errors) during OpenROAD physical implementation.
