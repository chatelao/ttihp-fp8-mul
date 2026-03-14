# Proposed 2-Tile Configuration: OCP MX-Vector Lite

This document proposes a **2-tile (1x2)** configuration for the OCP MXFP8 Streaming MAC Unit on Tiny Tapeout. By doubling the available area, we can enable high-performance features like **Vector Packing** and **Shared Scaling** that are difficult to fit into a single 1x1 tile.

## 1. Configuration Summary: "OCP MX-Vector Lite"

The "OCP MX-Vector Lite" variant is designed for maximum throughput and precision in OCP-standard workloads (E4M3/FP4) while omitting more specialized research features (like MX+ or LNS) to ensure comfortable routing and timing closure within two tiles.

| Parameter | Value | Reason |
|---|---|---|
| **Tile Size** | **1x2** | Provides ~4,000 - 6,000 gate capacity. |
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

## 4. Why 2 Tiles?

While a single 1x1 tile can fit the "Lite" variant (~3,800 gates), it requires aggressive pruning of features and often leads to congestion during physical implementation. A 2-tile (1x2) footprint allows for:
1. **Vector Packing**: The ~2,300 gate cost of dual-lane processing is easily absorbed.
2. **Timing Closure**: `SUPPORT_PIPELINING` and wider datapaths can be implemented without sacrificing area.
3. **Routing Ease**: Reduced cell density improves the likelihood of successful GDS generation at higher clock speeds.
