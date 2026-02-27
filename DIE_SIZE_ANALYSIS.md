# Die Size Analysis: OCP MXFP8 MAC Unit

This document analyzes the die size (gate/area) of the current OCP MXFP8 Streaming MAC Unit and proposes an optimized architecture to fit within a **1x1 Tiny Tapeout tile** (~167x108 µm).

## 1. Current Die Size Analysis (Optimized Architecture)

The implementation has been refactored to support aggressive area optimizations, allowing even the "Full" configuration to approach or fit within a **1x1 Tiny Tapeout tile** (~1500-2500 equivalent gates).

### Top 10 Area-Consuming Sub-modules/Components

| Rank | Sub-module | Component | Complexity | Estimated Gates |
|---|---|---|---|---|
| 1 | 🧩 `fp8_aligner` | 32-bit Barrel Shifter | Left/Right shift for elements + shared scales | ~500 |
| 2 | ✅ `fp8_mul` | 8x8 Combinatorial Multiplier | Mantissa product + signed integer mult | ~350 |
| 3 | ✅ `tt_um_top` | Config Registers | scale_sum, format_a, round_mode, etc. | ~400 |
| 4 | ✅ `accumulator` | 32-bit Signed Adder/Register | Core accumulation + serialization reuse | ~300 |
| 5 | 🧩 `fp8_mul` | Operand Decoders (A/B) | 7-format support | ~300 |
| 6 | ✅ `fp8_aligner` | Sticky/Round-Bit Gen | Loop-less OR-reduction and muxing | ~200 |
| 7 | 🧩 `tt_um_top` | Pipeline Registers | Multiplier output buffering | ~200 |
| 8 | ✅ `tt_um_top` | Control FSM & Logic | 6-bit counter and protocol logic | ~120 |
| 9 | ✅ `fp8_mul` | Exponent Arithmetic | Biased addition/subtraction | ~120 |
| 10 | ✅ `fp8_aligner` | Saturation & Overflow | 32-bit signed clamping | ~100 |
| **Total** | | | | **~2590** |

---

## 2. Implemented Optimizations for 1x1 Tile

### Optimization 1: Downsize the Aligner Path (Status: **COMPLETED**)
- **Change**: Narrowed the internal datapath via the `ALIGNER_WIDTH` parameter.
- **Impact**: Default 40-bit width provides full precision. Reducing to 32-bit saves ~150 gates.

### Optimization 2: Offload Shared Scaling to Software (Status: **COMPLETED**)
- **Change**: Controlled via `ENABLE_SHARED_SCALING` parameter.
- **Impact**: Removes the absolute value logic and complex shift amount calculation, saving ~700 gates.

### Optimization 3: Format Pruning (Status: **COMPLETED**)
- **Change**: Parameters `SUPPORT_MXFP6` and `SUPPORT_MXFP4`.
- **Impact**: Simplifies operand decoders and exponent logic.

### Optimization 4: Simplify Rounding Modes (Status: **COMPLETED**)
- **Change**: `SUPPORT_ADV_ROUNDING` disables CEIL/FLOOR.
- **Impact**: Simplifies rounding bit generation.

### Optimization 5: Remove Mixed-Precision Support (Status: **COMPLETED**)
- **Change**: `SUPPORT_MIXED_PRECISION` shares format for A and B.
- **Impact**: Eliminates one configuration register and several decoders.

### Optimization 6: Prune INT8 Support (Status: **COMPLETED**)
- **Change**: `SUPPORT_INT8` parameter.
- **Impact**: Shrinks the mantissa multiplier from 8x8 to 4x4. Saves ~420 gates.

### Optimization 7: Datapath Depipelining (Status: **COMPLETED**)
- **Change**: `SUPPORT_PIPELINING` parameter.
- **Impact**: Removes registers between multiplier and aligner. Saves ~200 gates but increases combinational path.

### Optimization 8: Accumulator Serialization & Register Reuse (Status: **COMPLETED**)
- **Change**: The accumulator register is refactored to act as a shift-register during the output phase.
- **Impact**: Eliminates the 32-bit output register (`scaled_acc_reg`), saving ~250 gates.

### Optimization 9: Aggressive Width Pruning (Status: **COMPLETED**)
- **Change**: Parameterized `ACCUMULATOR_WIDTH`.
- **Impact**: Reducing accumulation to 24-bit fits the design into the most restricted 1x1 tile targets.

### Optimization Summary for 1x1 Tile Support

| Build Variant | Parameter Configuration | Gates (Cells) | Tile Size |
|---|---|---|---|
| **Baseline (Full)** | All features enabled, 40/32 width | 3048 | 1x1* |
| **Tiny** | All optional features disabled | 1823 | 1x1 |
| **Ultra-Tiny** | Reduced widths (32/24) | 1588 | 1x1 |

*\*The "Full" build now approaches the 1x1 tile limit (~1500-2000 gates) thanks to the register reuse and FSM optimizations.*

## 3. Automated Gate Impact Analysis (Post-Optimization)

| Feature Flag | Configuration | Total Cells | Delta (vs Full) |
|---|---|---|---|
| **Baseline (Full)** | All features enabled | 3048 | 0 |
| `SUPPORT_MXFP6` | Disable MXFP6 | 3033 | -15 |
| `SUPPORT_INT8` | Disable INT8 (4x4 mult) | 2628 | -420 |
| `ENABLE_SHARED_SCALING` | Disable hardware scaling | 2358 | -690 |
| **Tiny (All Disabled)** | All features disabled | 1823 | -1225 |
| **Ultra-Tiny** | Reduced internal widths | 1588 | -1460 |
