# Multi-Tile Configurations: OCP MX-Vector Lite and Full

This document describes the multi-tile configurations for the OCP MXFP8 Streaming MAC Unit on Tiny Tapeout. Scaling beyond a single tile enables high-performance features like **Vector Packing** and **Shared Scaling** while ensuring reliable routing and timing closure on the IHP SG13G2 process.

## 1. Configuration Summary

| Feature | OCP MX-Vector Lite | OCP MX-Vector Full (Active) |
|---|---|---|
| **Tile Size** | **1x2** | **2x2** |
| **Gate Capacity** | ~4,000 - 6,000 | ~10,000 - 15,000 |
| `SUPPORT_VECTOR_PACKING` | `1` | **High Performance**: Enables 1.64x throughput for FP4. |
| `SUPPORT_E4M3` | `1` | Core OCP format support. |
| `SUPPORT_E5M2` | `1` | Standard FP8 format support. |
| `SUPPORT_MXFP4` | `1` | High-throughput 4-bit format support. |
| `ENABLE_SHARED_SCALING` | `1` | Hardware-accelerated block scaling. |
| `SUPPORT_PIPELINING` | `1` | Higher clock frequencies ($F_{max}$). |
| `SUPPORT_MIXED_PRECISION` | `1` | Independent A/B operand formats. |
| `ALIGNER_WIDTH` | `40` | Full precision alignment. |
| `ACCUMULATOR_WIDTH` | `32` | Full 32-bit accumulation. |

## 2. Area and Gate Analysis

The estimated gate count for this configuration is approximately **5,500 gates**.

| Feature | Gate Delta (vs Full) | Status |
|---|---|---|
| **Baseline (Full)** | 6,471 | - |
| Disable `SUPPORT_MX_PLUS` | -547 | Disabled |
| Disable `SUPPORT_INT8` | -233 | Disabled |
| Disable `SUPPORT_MXFP6` | -176 | Disabled |
| Disable `SUPPORT_ADV_ROUNDING` | -20 | Disabled |
| **Total Estimated Gates** | **~5,495** | **Target Met** |

## 3. Performance Benefits

### 3.1. Throughput (Elements per Clock Cycle)

By enabling `SUPPORT_VECTOR_PACKING`, this 2-tile configuration significantly outperforms the 1-tile "Tiny" or "Lite" variants when using FP4 operands.

| Configuration | Format | Cycles | Throughput (Elem/Cycle) |
|---|---|---|---|
| 1-Tile (Tiny/Lite) | FP4 | 41 | 0.78 |
| **2-Tile (Vector Lite)** | **FP4** | **25** | **1.28** |

### 3.2. Hardware-Accelerated Scaling

The inclusion of `ENABLE_SHARED_SCALING` allows the unit to perform 32-bit absolute value and shift operations in hardware (Cycle 36), offloading this computationally expensive task from the host processor and improving overall system efficiency.

## 4. Why 4 Tiles (2x2)?

While the "Lite" variant fits in 2 tiles (1x2), the **"Full" edition** (active for March 2025 shipping) requires a **2x2 footprint** due to its ~6,600 gate complexity.
1. **High Logic Density**: The combination of MX+, Vector Packing, and 40-bit datapaths creates high routing congestion.
2. **Timing Closure**: `SUPPORT_PIPELINING` is essential for 50MHz+ operation, and the extra area allows for buffer insertion to meet slack requirements.
3. **Physical Robustness**: A 2x2 tile ensures that the OpenROAD flow can achieve 100% routing completion with the IHP SG13G2 PDK.
