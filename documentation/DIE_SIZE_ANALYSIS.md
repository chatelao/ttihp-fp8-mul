# Die Size Analysis & Refactoring: OCP MXFP8 MAC Unit

This document analyzes the die size (gate/area) of the OCP MXFP8 Streaming MAC Unit and details the refactoring strategy used to achieve a modular, scalable architecture that fits within a **1x1 Tiny Tapeout tile** (~167x108 µm).

## 1. Refactoring Strategy: Parameterized Architecture

To make the design modular and scalable, Verilog parameters were introduced. This allows the design to be reconfigured for different Tiny Tapeout tile sizes by enabling or disabling specific features.

### 1.1. Configurable Parameters

| Parameter | Default | Description | Estimated Gate Savings |
|---|---|---|---|
| `ENABLE_SHARED_SCALING` | `1` | Enables hardware-accelerated shared scaling in Cycle 36. | ~273 |
| `SUPPORT_MXFP6` | `1` | Enables decoding for E3M2 and E2M3 formats. | ~17 |
| `SUPPORT_MXFP4` | `1` | Enables decoding for E2M1 format. | ~13 (Incr.) |
| `SUPPORT_VECTOR_PACKING` | `1` | Enables dual-lane processing for FP4 (E2M1) inputs. | ~2595 |
| `SUPPORT_PACKED_SERIAL` | `0` | Enables serial processing of packed FP4 elements. | ~100 |
| `SUPPORT_MX_PLUS` | `0` | Enables MX+ outlier precision extensions. | +557 |
| `SUPPORT_ADV_ROUNDING` | `1` | Enables CEIL and FLOOR rounding modes. | ~30 |
| `SUPPORT_MIXED_PRECISION` | `1` | Allows independent format selection for A and B. | ~53 |
| `USE_LNS_MUL` | `0` | Toggles between standard and approximate LNS multiplier. | ~403 |
| `ALIGNER_WIDTH` | `40` | Internal datapath width for the product aligner. | ~259 (Ultra-Tiny) |
| `USE_LNS_MUL_PRECISE` | `0` | Uses a 64x4 LUT for more accurate LNS multiplication. | ~349 |
| `SUPPORT_SERIAL` | `1` | Enables bit-serial timing (Stretched Protocol). | +67 |
| `SERIAL_K_FACTOR` | `8` | Latency scaling factor for serial operation. | N/A |

### 1.2. Recommended Refactorings

#### Multiplier Core (`fp8_mul.v`)
- [x] **Conditional Decoding**: Use logic pruning based on `SUPPORT_MXFP6` and `SUPPORT_MXFP4`.
- [x] **Bias Simplification**: Bias logic is simplified based on supported formats.
- [x] **Shared Decoders**: (Optional) Use a single decoder set if `SUPPORT_MIXED_PRECISION` is `0`.

#### Product Aligner (`fp8_aligner.v`)
- [x] **Configurable Rounding**: Logic for `R_CEL` and `R_FLR` is pruned if `SUPPORT_ADV_ROUNDING` is disabled.
- [x] **Internal Bit-width**: Fully parameterize the internal registers using `ALIGNER_WIDTH`.

#### Top-Level Integration (`project.v`)
- [x] **FSM Guarding**: Shared scaling logic and absolute value logic (`acc_abs_val`) are conditionally enabled via `ENABLE_SHARED_SCALING`.
- [x] **Register Pruning**: (Optional) Conditionally instantiate registers for `format_b`, `scale_b`, and multiplier pipeline.
- [x] **Fast Start Logic**: Verified correctness with all parameter variants.
- [x] **FSM State Register Elimination**: The `state` register was removed and replaced with combinatorial logic derived from `cycle_count`.

## 2. Die Size Analysis (Optimized Architecture)

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

## 3. Implemented Optimizations for 1x1 Tile

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

### Optimization 10: Disable Vector Packing (Status: **COMPLETED**)
- **Change**: `SUPPORT_VECTOR_PACKING` parameter.
- **Impact**: Removes the second multiplier/aligner lane. Saves ~2908 gates at the cost of processing speed for FP4.

### Optimization 11: Serial Vector Packing (Status: **COMPLETED**)
- **Change**: `SUPPORT_PACKED_SERIAL` parameter.
- **Impact**: Provides a low-area alternative to dual-lane packing by reusing a single multiplier lane with an input buffer. Adds only ~100 gates while maintaining 4-bit input density.

### Optimization Summary for 1x1 Tile Support

| Build Variant | Parameter Configuration | Gates (Cells) | Tile Size |
|---|---|---|---|
| **Baseline (Full)** | All features enabled, 40/32 width | 6399 | 1x1* |
| **Lite** | Disable MXFP6/4/Adv/VP | 3378 | 1x1* |
| **Tiny** | All optional features disabled | 2302 | 1x1 |
| **Ultra-Tiny** | Tiny config + Reduced widths (32/24) | 2057 | 1x1 |
| **Tiny-Serial (GDS Default)** | Ultra-Tiny + Serial Infrastructure | 2124 | 1x1 |

*\*The "Full" and "Lite" builds now approach the 1x1 tile limit thanks to the register reuse and FSM optimizations.*

### Variant Feature Comparison Matrix

| Feature / Parameter | Full | Lite | Tiny | Ultra-Tiny | Tiny-Serial |
|---|:---:|:---:|:---:|:---:|:---:|
| `SUPPORT_E5M2` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `SUPPORT_MXFP6` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `SUPPORT_MXFP4` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `SUPPORT_VECTOR_PACKING` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `SUPPORT_INT8` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `SUPPORT_PIPELINING` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `SUPPORT_ADV_ROUNDING` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `SUPPORT_MIXED_PRECISION` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `ENABLE_SHARED_SCALING` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `USE_LNS_MUL` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `SUPPORT_SERIAL` | ❌ | ❌ | ❌ | ❌ | ✅ |
| `ALIGNER_WIDTH` | **40** | **40** | **40** | **32** | **32** |
| `ACCUMULATOR_WIDTH` | **32** | **32** | **32** | **24** | **24** |

## 4. Automated Gate Impact Analysis (Post-Optimization)

| Feature Flag | Configuration | Total Cells | Delta (vs Full) |
|---|---|---|---|
| **Baseline (Full)** | All features enabled | 6345 | 0 |
| `SUPPORT_E4M3` | Disable E4M3 | 6287 | -58 |
| `SUPPORT_E5M2` | Disable E5M2 | 6153 | -192 |
| `SUPPORT_MXFP6` | Disable MXFP6 | 6161 | -184 |
| `SUPPORT_MXFP4` | Disable MXFP4 | 6308 | -37 |
| `SUPPORT_VECTOR_PACKING` | Disable Vector Packing | 3464 | -2881 |
| `SUPPORT_INT8` | Disable INT8 (4x4 mult) | 6101 | -244 |
| `SUPPORT_PIPELINING` | Disable Pipelining | 6328 | -17 |
| `SUPPORT_ADV_ROUNDING` | Disable Adv. Rounding | 6322 | -23 |
| `SUPPORT_MIXED_PRECISION`| Disable Mixed Precision| 6238 | -107 |
| `SUPPORT_MX_PLUS` | Disable MX+ outlier extensions | 5788 | -557 |
| `ENABLE_SHARED_SCALING` | Disable hardware scaling | 6093 | -252 |
| **Tiny (All Disabled)** | All features disabled | 2170 | -4175 |
| **Ultra-Tiny** | Tiny config + Reduced widths (32/24) | 1924 | -4421 |
| **Tiny-Serial** | Ultra-Tiny + Serial Infra | 1995 | -4350 |
| **1x1 Tile Target (Min)**| Min. widths (24/20) | 1653 | -4692 |
| **LNS Multiplier (Mitchell)** | Mitchell multiplier | 6510 | +165 |
| **LNS Multiplier (Precise)** | Precise LNS multiplier | 6629 | +284 |

## 5. Deployment & CI/CD Progress

### Deployment Variants

| Variant | Tile Size | Parameters |
|---|---|---|
| **Tiny-Serial (GDS Default)** | 1x1 | `SUPPORT_SERIAL=1`, `SERIAL_K_FACTOR=8`, Ultra-Tiny widths. |
| **Ultra-Tiny** | 1x1 | All features disabled, 32/24 bit widths. |
| **Tiny** | 1x1 | All features disabled, 40/32 bit widths. |
| **Lite** | 1x1 | `SUPPORT_MXFP6=0`, `SUPPORT_ADV_ROUNDING=0`. |
| **Full** | 1x1 | All features enabled. |

### CI/CD Progress: Matrix Testing

To ensure the integrity of all variants, the CI/CD pipeline is updated to test multiple configurations on every build.

- [x] **Parameter Injection**: Support parameter overrides via `COMPILE_ARGS` in the CI pipeline.
- [x] **GitHub Actions Matrix**: Updated `.github/workflows/test.yaml` to include Full, Lite, Tiny, and Ultra-Tiny variants.
- [x] **Testbench Adaptations**: Updated `test/test.py` to dynamically detect and skip tests based on hardware parameters.

### Refactoring Progress Checklist

- [x] Parameterize Multiplier Core (`SUPPORT_MXFP6`, `SUPPORT_MXFP4`)
- [x] Parameterize Product Aligner (`SUPPORT_ADV_ROUNDING`, `ALIGNER_WIDTH`)
- [x] Parameterize Top-Level (`ENABLE_SHARED_SCALING`, `SUPPORT_MIXED_PRECISION`)
- [x] Update CI pipeline for parameter injection
- [x] Update `test/test.py` for dynamic test skipping
- [x] Verify **Full** Variant
- [x] Verify **Lite** Variant
- [x] Verify **Tiny** Variant
- [x] Verify **Tiny-Serial** Variant

## 6. Speed and Throughput Analysis

The architectural variants not only differ in area (gate count) but also in their processing speed and data throughput.

### 6.1. Protocol Latency and Cycle Counts

The MAC unit operates using a fixed-cycle protocol. The total number of cycles required for a single 32-element block operation depends on the enabled features:

| Mode | Parameter | Cycles | Description |
|---|---|---|---|
| **Standard** | Default | 41 | 32 cycles of streaming + 9 overhead (Setup, Scale, Output) |
| **Packed Lane** | `SUPPORT_VECTOR_PACKING=1` | 25 | 16 cycles of streaming (2 elements/cycle) + 9 overhead |
| **Packed Serial** | `SUPPORT_PACKED_SERIAL=1` | 41 | 32 cycles of streaming (packed byte every 2 cycles) |

### 6.2. Throughput (Elements per Clock Cycle)

The throughput is measured as the number of elements processed per clock cycle ($k / \text{Total Cycles}$).

| Configuration | Format | Total Cycles | Throughput (Elem/Cycle) | Speedup (vs Std) |
|---|---|---|---|---|
| Standard | All | 41 | 0.78 | 1.00x |
| Packed Serial | FP4 | 41 | 0.78 | 1.00x |
| **Packed Lane** | **FP4** | **25** | **1.28** | **1.64x** |

### 6.3. Maximum Frequency ($F_{max}$) and Pipelining

The `SUPPORT_PIPELINING` parameter significantly impacts the timing closure of the design:

- **Pipelining ENABLED**: Inserts a register stage between the multiplier and the aligner. This reduces the longest combinatorial path (the "Critical Path"), allowing the unit to run at higher clock frequencies (e.g., targeting >50 MHz on IHP SG13G2).
- **Pipelining DISABLED**: Reduces area by ~30-50 gates but forces the design into a single-cycle combinatorial path from operand input to accumulator update. This lowers the $F_{max}$, suitable for low-power or area-constrained designs running at <10 MHz.

### 6.4. Hardware-Accelerated Scaling

- **`ENABLE_SHARED_SCALING=1`**: The hardware performs the 32-bit absolute value and shift in a single cycle (Cycle 36).
- **`ENABLE_SHARED_SCALING=0`**: The hardware outputs the unscaled 32-bit accumulator. The host processor must perform the scaling in software. While this saves ~250 gates, it may significantly reduce the *effective system throughput* if the host CPU is a simple bit-serial core like SERV.

### 6.5. Tiny-Serial: Bit-Serial Infrastructure

The "Tiny-Serial" variant (inspired by the SERV bit-serial RISC-V core) provides a bit-serial execution framework within the OCP MX MAC unit.

- **Stretched Protocol**: To maintain the 8-bit streaming interface while allowing for internal bit-serial processing, the protocol is "stretched" by a factor $K$ (`SERIAL_K_FACTOR`). Each cycle in the standard protocol corresponds to $K$ clock cycles in the serial variant.
- **Area Impact**: The serialization logic (primarily the `k_counter` and additional FSM control) adds approximately **67 gates** to the Ultra-Tiny baseline.
- **Throughput Trade-off**: Total cycles for a standard operation increase from 41 to $41 \times K$. For $K=8$, a block requires 328 cycles.
- **Latency Decoupling**: This mode is essential for configurations where internal timing closure is difficult at the target 8-bit IO interface frequency, allowing the core to operate at higher internal frequencies relative to the data stream.
