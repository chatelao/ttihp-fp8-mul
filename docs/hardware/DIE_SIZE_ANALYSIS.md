# Die Size Analysis & Refactoring: OCP MXFP8 MAC Unit

This document analyzes the die size (gate/area) of the OCP MXFP8 Streaming MAC Unit and details the refactoring strategy used to achieve a modular, scalable architecture that fits within a **1x1 Tiny Tapeout tile** (~167x108 µm).

## 1. Refactoring Strategy: Parameterized Architecture

To make the design modular and scalable, Verilog parameters were introduced. This allows the design to be reconfigured for different Tiny Tapeout tile sizes by enabling or disabling specific features.

### 1.1. Configurable Parameters

| Parameter | Default (src) | Description | Gate Impact (vs Full) |
|---|---|---|---|
| `SUPPORT_E4M3` | `1` | Enables E4M3 (OCP) format. | -122 |
| `SUPPORT_E5M2` | `1` | Enables E5M2 format. | -250 |
| `SUPPORT_MXFP6` | `1` | Enables E3M2/E2M3 formats. | -194 |
| `SUPPORT_MXFP4` | `1` | Enables E2M1 (FP4) format. | -64 |
| `SUPPORT_VECTOR_PACKING` | `1` | Enables dual-lane processing. | -2426 |
| `SUPPORT_INT8` | `1` | Enables INT8/INT8_SYM formats. | -258 |
| `SUPPORT_PIPELINING` | `1` | Inserts register stage in datapath. | -68 |
| `SUPPORT_ADV_ROUNDING` | `1` | Enables CEIL/FLOOR modes. | -27 |
| `SUPPORT_MIXED_PRECISION`| `1` | Allows independent A/B formats. | -115 |
| `SUPPORT_INPUT_BUFFERING`| `1` | Enables 16-entry input FIFO. | -3 |
| `SUPPORT_MX_PLUS` | `1` | Enables MX+ outlier extensions. | -593 |
| `ENABLE_SHARED_SCALING` | `1` | Enables HW shared scaling. | -296 |
| `USE_LNS_MUL` | `0` | Toggles Mitchell LNS multiplier. | +326 |
| `USE_LNS_MUL_PRECISE` | `0` | Precise LNS (64x4 LUT). | +445 |
| `SUPPORT_SERIAL` | `0` | Enables bit-serial infrastructure. | +24 |
| `SUPPORT_DEBUG` | `1` | Enables metadata/probe debug logic. | -247 |
| `ALIGNER_WIDTH` | `40` | Internal aligner width. | ~150 (32-bit) |
| `ACCUMULATOR_WIDTH` | `32` | Accumulator width. | ~100 (24-bit) |

## 2. Die Size Analysis (Optimized Architecture)

The implementation has been refactored to support aggressive area optimizations, allowing even the "Full" configuration to approach or fit within a **1x1 Tiny Tapeout tile** (~1500-2500 equivalent gates) when specific lanes are disabled.

### Top 10 Area-Consuming Sub-modules/Components (Baseline Full)

| Rank | Sub-module | Component | Complexity | Estimated Gates |
|---|---|---|---|---|
| 1 | 🧩 `fp8_aligner` | 40-bit Barrel Shifter (x2) | Left/Right shift for elements + shared scales | ~3038 |
| 2 | ✅ `fp8_mul` | 8x8 Multipliers (x2) | Mantissa product + signed integer mult | ~2086 |
| 3 | ✅ `tt_um_top` | Top-level Glue Logic | Metadata, FSM, Debug, MX+ control | ~1210 |
| 4 | ✅ `accumulator` | 32-bit Signed Adder/Register | Core accumulation + serialization reuse | ~451 |
| 5 | ✅ `fp8_aligner` | Sticky/Round-Bit Gen | Loop-less OR-reduction and muxing | Included in #1 |
| 6 | ✅ `fp8_aligner` | Saturation & Overflow | 32-bit signed clamping | Included in #1 |
| 7 | ✅ `fp8_mul` | Operand Decoders (A/B) | 7-format support | Included in #2 |
| 8 | ✅ `fp8_mul` | Exponent Arithmetic | Biased addition/subtraction | Included in #2 |
| 9 | ✅ `tt_um_top` | Control FSM & Logic | 6-bit counter and protocol logic | Included in #3 |
| 10 | ✅ `tt_um_top` | Debug Multiplexers | Probing and Metadata Echo | ~247 |
| **Total** | | | | **~6809** |

## 3. Optimization Summary for 1x1 Tile Support

| Build Variant | Parameter Configuration | Gates (Cells) | Tile Size |
|---|---|---|---|
| **Baseline (Full)** | All features enabled, 40/32 width | 6809 | 2x2* |
| **Lite** | Disable MXFP6/VP/MX+/Adv | 4033 | 1x1 |
| **Tiny** | All optional features disabled | 2193 | 1x1 |
| **Ultra-Tiny** | Tiny config + Reduced widths (32/24) | 1937 | 1x1 |
| **Tiny-Serial** | Ultra-Tiny + Serial Infrastructure | 1964 | 1x1 |

*\*The "Full" variant is deployed in a 2x2 tile configuration to ensure routing success at ~6,800 gates.*

## 4. Automated Gate Impact Analysis (Individual Features)

| Feature Flag | Configuration | Total Cells | Delta (vs Full) |
|---|---|---|---|
| **Baseline (Full)** | All features enabled | 6809 | 0 |
| `SUPPORT_E4M3` | Disable E4M3 | 6687 | -122 |
| `SUPPORT_E5M2` | Disable E5M2 | 6559 | -250 |
| `SUPPORT_MXFP6` | Disable MXFP6 | 6615 | -194 |
| `SUPPORT_MXFP4` | Disable MXFP4 | 6745 | -64 |
| `SUPPORT_VECTOR_PACKING` | Disable Vector Packing | 4383 | -2426 |
| `SUPPORT_INT8` | Disable INT8 | 6551 | -258 |
| `SUPPORT_PIPELINING` | Disable Pipelining | 6741 | -68 |
| `SUPPORT_ADV_ROUNDING` | Disable Adv. Rounding | 6782 | -27 |
| `SUPPORT_MIXED_PRECISION`| Disable Mixed Precision| 6694 | -115 |
| `SUPPORT_INPUT_BUFFERING`| Disable Input Buffering | 6806 | -3 |
| `SUPPORT_MX_PLUS` | Disable MX+ extensions | 6216 | -593 |
| `ENABLE_SHARED_SCALING` | Disable hardware scaling | 6513 | -296 |
| `SUPPORT_DEBUG` | Disable debug logic | 6562 | -247 |
| **LNS Multiplier (Mitchell)** | Mitchell multiplier | 7135 | +326 |
| **LNS Multiplier (Precise)** | Precise LNS multiplier | 7254 | +445 |
| **1x1 Tile Target (Min)**| Min. widths (24/20) | 1657 | -5152 |

## 5. Resource Usage Detailed Breakdown

For more granular analysis of hardware resources, refer to the following documents:

- **[Flip-Flop Usage Analysis](FLIP_FLOP_USAGE.md)**: Detailed breakdown of register usage per sub-module and design variant.
- **[LUT and Gate Usage Analysis](LUT_USAGE.md)**: Breakdown of combinatorial logic complexity for ASIC (gates) and FPGA (LUTs).

## 6. JTAG Integration Area Impact

Based on the [JTAG Integration Concept](../../JTAG_CONCEPT.md), the following estimated area impacts are expected for adding JTAG debugging:

| Complexity Level | Description | Estimated Gates | Impact on 1x1 Tile |
|---|---|---|---|
| **Level 1** | Basic Compliance (IDCODE/BYPASS) | ~150 | Minimal |
| **Level 2** | Boundary Scan (EXTEST) | ~250 | Manageable |
| **Level 3** | Data Retrieval (Accumulator Read) | ~400 | Fits in Lite/Tiny |
| **Level 4** | Advanced Probing (Internal Scan) | 600+ | Requires 2x2 Full |

## 6. Speed and Throughput Analysis

### 6.1. Maximum Frequency ($F_{max}$) and Pipelining

The `SUPPORT_PIPELINING` parameter significantly impacts the timing closure of the design:

- **Pipelining ENABLED**: Inserts a register stage between the multiplier and the aligner. This reduces the longest combinatorial path (the "Critical Path"), allowing the unit to run at higher clock frequencies (e.g., targeting >50 MHz on IHP SG13G2).
- **Pipelining DISABLED**: Reduces area by ~68 gates but forces the design into a single-cycle combinatorial path from operand input to accumulator update. This lowers the $F_{max}$, suitable for low-power or area-constrained designs running at <10 MHz.

### 6.2. Hardware-Accelerated Scaling

- **`ENABLE_SHARED_SCALING=1`**: The hardware performs the 32-bit absolute value and shift in a single cycle (Cycle 36).
- **`ENABLE_SHARED_SCALING=0`**: The hardware outputs the unscaled 32-bit accumulator. This saves ~296 gates.
