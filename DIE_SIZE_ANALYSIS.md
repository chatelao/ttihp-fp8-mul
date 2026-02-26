# Die Size Analysis: OCP MXFP8 MAC Unit

This document analyzes the die size (gate/area) of the current OCP MXFP8 Streaming MAC Unit and proposes an optimized architecture to fit within a **1x1 Tiny Tapeout tile** (~167x108 µm).

## 1. Current Die Size Analysis (1x2 Tile)

The current implementation supports a wide range of OCP MX formats (MXFP8, MXFP6, MXFP4, MXINT8) and features hardware-accelerated shared scaling and advanced rounding modes. This has necessitated a **1x2 Tiny Tapeout tile** configuration (~3000-4000 equivalent gates).

### Top 10 Area-Consuming Sub-modules/Components

| Rank | Sub-module | Component | Complexity | Estimated Gates |
|---|---|---|---|---|
| 1 | `fp8_aligner` | 64-bit Barrel Shifter | Left/Right shift for elements + shared scales | ~800 |
| 2 | `fp8_mul` | Operand Decoders (A/B) | 7-format support (E4M3, E5M2, FP6, FP4, INT8) | ~400 |
| 3 | `fp8_mul` | 8x8 Combinatorial Multiplier | Mantissa product + signed integer mult | ~350 |
| 4 | `tt_um_top` | Pipeline & Config Registers | ~100 DFFs for pipelining, scale/format storage | ~800 (eq) |
| 5 | `fp8_aligner` | Sticky/Round-Bit Gen | 64-bit OR-reduction and muxing | ~250 |
| 6 | `fp8_aligner` | 64-bit Rounding Adder | `base + 1` logic for CEL, FLR, RNE | ~200 |
| 7 | `accumulator` | 32-bit Signed Adder | Core dot-product accumulation | ~180 |
| 8 | `tt_um_top` | Control FSM & Logic | 6-bit counter and 41-cycle state transitions | ~180 |
| 9 | `fp8_mul` | Exponent Arithmetic | Biased addition/subtraction for 7 formats | ~150 |
| 10 | `fp8_aligner` | Saturation & Overflow | 32-bit signed clamping and wrapping muxes | ~120 |
| **Total** | | | | **~3430** |

*Note: Gate counts are NAND2 equivalents based on RTL architectural complexity and bit-widths.*

---

## 2. Proposed 1x1 Tile Solution

To achieve the ~1500 gate target for a 1x1 tile, the design must prioritize hardware efficiency over exhaustive format support and optional features.

### Optimization 1: Downsize the Aligner Path
The current aligner uses a **64-bit** internal path to handle both 16x32 alignment and 32x32 shared scaling.
- **Change**: Narrow the internal shifter and rounding adder to **40 bits**.
- **Impact**: Since element products are 16-bit and the accumulator is 32-bit, a 40-bit window (32 bits + 8 bits for rounding/sticky) is sufficient. This reduces aligner area by ~40%.

### Optimization 2: Offload Shared Scaling to Software
Hardware-accelerated shared scaling (Cycle 36) applies $2^{(X_A+X_B-254)}$ in hardware, requiring 32-bit absolute value logic and a full 32-bit shifter.
- **Change**: Revert to the original concept (Section 3.2 of `MXFP8_CONCEPT.md`) where the host software applies the shared scale to the 32-bit result.
- **Impact**: Removes the absolute value logic and simplifies the shifter, saving ~300 gates.

### Optimization 3: Prune Optional Formats (FP6/FP4)
The OCP MX specification includes many formats, but the primary ones are MXFP8 and MXINT8.
- **Change**: Prune support for MXFP6 (E3M2, E2M3) and MXFP4 (E2M1).
- **Impact**: Significantly simplifies the `fp8_mul` decoders and exponent bias arithmetic, saving ~250 gates.

### Optimization 4: Simplify Rounding Modes
- **Change**: Support only **Round-to-Nearest-Ties-to-Even (RNE)** and **Truncate (TRN)**.
- **Impact**: Eliminates the CEIL and FLOOR muxing logic and simplifies the rounding bit generation, saving ~100 gates.

### Optimization Summary for 1x1 Tile

| Component | Current Gates | Optimized Gates | Reduction |
|---|---|---|---|
| Aligner (Shifter/Adder) | ~1250 | ~650 | 48% |
| Multiplier (Decoders/Mult) | ~750 | ~500 | 33% |
| Registers (DFFs) | ~800 | ~250* | 68% |
| Control & Misc | ~630 | ~150** | 76% |
| **Total** | **~3430** | **~1550** | **~55%** |

*\*Reducing the number of supported formats and removing shared scaling registers saves significant DFF count.*
*\*\*Simplifying the FSM by removing cycles and config registers.*

By implementing these optimizations, the OCP MXFP8 MAC unit can fit comfortably into a **1x1 Tiny Tapeout tile** while maintaining its core functionality for the most important MX formats.
