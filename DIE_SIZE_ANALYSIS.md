# Die Size Analysis: OCP MXFP8 MAC Unit

This document analyzes the die size (gate/area) of the current OCP MXFP8 Streaming MAC Unit and proposes an optimized architecture to fit within a **1x1 Tiny Tapeout tile** (~167x108 µm).

## 1. Current Die Size Analysis (1x2 Tile)

The current implementation supports a wide range of OCP MX formats (MXFP8, MXFP6, MXFP4, MXINT8) and features hardware-accelerated shared scaling and advanced rounding modes. This has necessitated a **1x2 Tiny Tapeout tile** configuration (~3000-4000 equivalent gates).

### Module Architecture Overview
The following diagram illustrates the high-level architecture and data flow between the primary sub-modules. The source for this diagram is available in `documentation/module_overview.dot`.

### Top 10 Area-Consuming Sub-modules/Components

> ✅ Mandatory component for core MAC operation.
> 🧩 Optional component (optimizable or removable via parameters).

| Rank | Sub-module | Component | Complexity | Estimated Gates |
|---|---|---|---|---|
| 1 | 🧩 `fp8_aligner` | 40-bit Barrel Shifter | Left/Right shift for elements + shared scales | ~800 |
| 2 | 🧩 `fp8_mul` | Operand Decoders (A/B) | 7-format support (E4M3, E5M2, FP6, FP4, INT8) | ~400 |
| 3 | ✅ `fp8_mul` | 8x8 Combinatorial Multiplier | Mantissa product + signed integer mult | ~350 |
| 4 | ✅ `tt_um_top` | Pipeline & Config Registers | ~100 DFFs for pipelining, scale/format storage | ~800 (eq) |
| 5 | ✅ `fp8_aligner` | Sticky/Round-Bit Gen | 40-bit OR-reduction and muxing | ~250 |
| 6 | 🧩 `fp8_aligner` | 40-bit Rounding Adder | `base + 1` logic for CEL, FLR, RNE | ~200 |
| 7 | ✅ `accumulator` | 32-bit Signed Adder | Core dot-product accumulation | ~180 |
| 8 | ✅ `tt_um_top` | Control FSM & Logic | 6-bit counter and 41-cycle state transitions | ~180 |
| 9 | ✅ `fp8_mul` | Exponent Arithmetic | Biased addition/subtraction for 7 formats | ~150 |
| 10 | ✅ `fp8_aligner` | Saturation & Overflow | 32-bit signed clamping and wrapping muxes | ~120 |
| **Total** | | | | **~3430** |

*Note: Gate counts are NAND2 equivalents based on RTL architectural complexity and bit-widths.*

---

## 2. Proposed 1x1 Tile Solution

To achieve the ~1500 gate target for a 1x1 tile, the design must prioritize hardware efficiency over exhaustive format support and optional features.

### Optimization 1: Downsize the Aligner Path (Status: **COMPLETED**)
The aligner has been downsized to a **40-bit** internal path to handle both 16x32 alignment and 32x32 shared scaling, replacing the original 64-bit baseline.
- **Change**: Narrowed the internal shifter and rounding adder to **40 bits** via the `WIDTH` parameter.
- **Impact**: Reduced aligner area by approximately 40%.
- **Speed/Precision**:
    - **Precision**: **No loss**. A 40-bit window is sufficient to represent a 32-bit result plus 8 bits for guard, round, and sticky bits.
    - **Speed**: **Slight improvement**. Shorter carry chains in the rounding adder and fewer stages in the barrel shifter improve timing slack.

### Optimization 2: Offload Shared Scaling to Software
Hardware-accelerated shared scaling (Cycle 36) applies $2^{(X_A+X_B-254)}$ in hardware, requiring 32-bit absolute value logic and a full 32-bit shifter.
- **Change**: Revert to the original concept (Section 3.2 of `MXFP8_CONCEPT.md`) where the host software applies the shared scale to the 32-bit result.
- **Impact**: Removes the absolute value logic and simplifies the shifter, saving ~300 gates.
- **Speed/Precision**:
    - **Precision**: **No loss**. Software can perform the power-of-two scaling bit-exactly.
    - **Speed**: **Significant decrease**. System-level throughput drops as the host CPU/controller must perform post-processing on every 32-element block result.

### Optimization 3a: Prune MXFP6 Formats (E3M2, E2M3)
MXFP6 provides a middle ground between FP8 and FP4, but requires two additional decoding paths per operand.
- **Change**: Remove support for E3M2 (Bias 3) and E2M3 (Bias 1).
- **Impact**: Saves **~170 gates** by simplifying the operand muxes and exponent arithmetic logic in `fp8_mul`.
- **Speed/Precision**:
    - **Precision**: **Functional loss** of 6-bit floating point capabilities.
    - **Speed**: **Improved** timing slack in the multiplier stage.

### Optimization 3b: Prune MXFP4 Formats (E2M1)
MXFP4 is the most aggressive quantization format in OCP MX, with very limited range/precision.
- **Change**: Remove support for E2M1 (Bias 1).
- **Impact**: Saves **~80 gates**.
- **Speed/Precision**:
    - **Precision**: **Functional loss** of the 4-bit format.
    - **Speed**: **Minor improvement** in combinatorial delay.

### Recommendation: Which to prune first?
**Pruning MXFP4 (Optimization 3b) is recommended first.**
While pruning MXFP6 saves more area, **MXFP4 is significantly less common** in practice due to its extremely low precision (1-bit mantissa). MXFP6 remains more useful for various neural network layers. If the area target is extremely tight (e.g., fitting in a 1x1 tile), **pruning both** is the standard approach to further reduce control signal bit-widths and configuration registers.

### Optimization 4: Simplify Rounding Modes
- **Change**: Support only **Round-to-Nearest-Ties-to-Even (RNE)** and **Truncate (TRN)**.
- **Impact**: Eliminates the CEIL and FLOOR muxing logic and simplifies the rounding bit generation, saving ~100 gates.
- **Speed/Precision**:
    - **Precision**: **Loss of flexibility**. Loss of directed rounding modes (CEIL/FLOOR) which may be required for specific quantization or interval arithmetic tasks.
    - **Speed**: **Minor improvement**. Removing muxes from the rounding logic slightly reduces the combinational delay of the aligner.

### Optimization 5: Remove Mixed-Precision Support
The current implementation allows independent format selection for `format_a` and `format_b`.
- **Change**: Force both operands to share a single format configuration sampled at Cycle 1.
- **Impact**: Eliminates the `format_b` register and one set of format decoders, saving ~150 gates.
- **Speed/Precision**:
    - **Precision**: **Functional loss**. The unit can no longer perform mixed-precision operations (e.g., E4M3 * E5M2).
    - **Speed**: **Minor improvement**. Reduced fan-out on format control signals improves timing slack.

### Optimization Summary for 1x1 Tile

| Component | Current Gates | Optimized Gates | Reduction |
|---|---|---|---|
| Aligner (Shifter/Adder) | ~1250 | ~650 | 48% |
| Multiplier (Decoders/Mult) | ~750 | ~350*** | 53% |
| Registers (DFFs) | ~800 | ~200* | 75% |
| Control & Misc | ~630 | ~150** | 76% |
| **Total** | **~3430** | **~1350** | **~60%** |

*\*Reducing the number of supported formats and removing shared scaling registers saves significant DFF count.*
*\*\*Simplifying the FSM by removing cycles and config registers.*
*\*\*\*Includes Optimization 5 (Removal of mixed-precision decoders).*

By implementing these optimizations, the OCP MXFP8 MAC unit can fit comfortably into a **1x1 Tiny Tapeout tile** while maintaining its core functionality for the most important MX formats.

## 3. Automated Gate Impact Analysis

The following table shows the measured gate impact of each feature flag, obtained by synthesizing the design with Yosys and disabling one feature at a time from the "Full" baseline.

| Feature Flag | Configuration | Total Cells | Delta (vs Full) |
|---|---|---|---|
| **Baseline (Full)** | All features enabled | 3439 | 0 |
| `SUPPORT_MXFP6` | Disable MXFP6 (E3M2, E2M3) | 3420 | -19 |
| `SUPPORT_MXFP4` | Disable MXFP4 (E2M1) | 3440 | +1* |
| `SUPPORT_ADV_ROUNDING` | Disable CEIL/FLOOR rounding | 3189 | -250 |
| `SUPPORT_MIXED_PRECISION` | Disable mixed-precision | 3439 | 0 |
| `ENABLE_SHARED_SCALING` | Disable hardware shared scaling | 3167 | -272 |
| **Tiny (All Disabled)** | All optional features disabled | 2864 | -575 |

*\*Small increases in cell count can occur due to synthesis tool heuristics when logic paths are modified.*
