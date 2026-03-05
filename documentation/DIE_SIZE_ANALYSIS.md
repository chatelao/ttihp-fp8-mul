# Die Size Analysis & Refactoring: OCP MXFP8 MAC Unit

This document analyzes the die size (gate/area) of the OCP MXFP8 Streaming MAC Unit and details the refactoring strategy used to achieve a modular, scalable architecture that fits within a **1x1 Tiny Tapeout tile** (~167x108 µm).

## 1. Refactoring Strategy: Parameterized Architecture

To make the design modular and scalable, Verilog parameters were introduced. This allows the design to be reconfigured for different Tiny Tapeout tile sizes by enabling or disabling specific features.

### 1.1. Configurable Parameters

| Parameter | Default (src) | Description | Gate Impact (vs Full) |
|---|---|---|---|
| `SUPPORT_E4M3` | `1` | Enables E4M3 (OCP) format. | -72 |
| `SUPPORT_E5M2` | `0` | Enables E5M2 format. | -192 |
| `SUPPORT_MXFP6` | `0` | Enables E3M2/E2M3 formats. | -183 |
| `SUPPORT_MXFP4` | `1` | Enables E2M1 (FP4) format. | -50 |
| `SUPPORT_VECTOR_PACKING` | `0` | Enables dual-lane FP4 processing. | -2309 |
| `SUPPORT_INT8` | `0` | Enables INT8/INT8_SYM formats. | -242 |
| `SUPPORT_PIPELINING` | `0` | Inserts register stage in datapath. | -65 |
| `SUPPORT_ADV_ROUNDING` | `0` | Enables CEIL/FLOOR modes. | -21 |
| `SUPPORT_MIXED_PRECISION`| `0` | Allows independent A/B formats. | -107 |
| `SUPPORT_INPUT_BUFFERING`| `0` | Enables 16-entry input FIFO. | +7 |
| `SUPPORT_MX_PLUS` | `0` | Enables MX+ outlier extensions. | -567 |
| `ENABLE_SHARED_SCALING` | `0` | Enables HW shared scaling. | -264 |
| `USE_LNS_MUL` | `0` | Toggles Mitchell LNS multiplier. | +162 |
| `USE_LNS_MUL_PRECISE` | `0` | Precise LNS (64x4 LUT). | +278 |
| `SUPPORT_SERIAL` | `1` | Enables bit-serial infrastructure. | +69 |
| `ALIGNER_WIDTH` | `32` | Internal aligner width. | ~150 (32-bit) |
| `ACCUMULATOR_WIDTH` | `24` | Accumulator width. | ~100 (24-bit) |
| `SERIAL_K_FACTOR` | `8` | Latency scaling factor for serial operation. | N/A |

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

## 3. Optimization Summary for 1x1 Tile Support

| Build Variant | Parameter Configuration | Gates (Cells) | Tile Size |
|---|---|---|---|
| **Baseline (Full)** | All features enabled, 40/32 width | 6499 | 1x1* |
| **Lite** | Disable MXFP6/4/Adv/VP | 3777 | 1x1* |
| **Tiny** | All optional features disabled | 2116 | 1x1 |
| **Ultra-Tiny** | Tiny config + Reduced widths (32/24) | 1862 | 1x1 |
| **Tiny-Serial (GDS Default)** | Ultra-Tiny + Serial Infrastructure | 1859 | 1x1 |

*\*The "Full" and "Lite" builds now approach the 1x1 tile limit thanks to the register reuse and FSM optimizations.*

### Variant Feature Comparison Matrix

| Feature / Parameter | Full | Lite | Tiny | Ultra-Tiny | Tiny-Serial |
|---|:---:|:---:|:---:|:---:|:---:|
| `SUPPORT_E4M3` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `SUPPORT_E5M2` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `SUPPORT_MXFP6` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `SUPPORT_MXFP4` | ✅ | ✅ | ❌ | ❌ | ✅ |
| `SUPPORT_VECTOR_PACKING` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `SUPPORT_INT8` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `SUPPORT_PIPELINING` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `SUPPORT_ADV_ROUNDING` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `SUPPORT_MIXED_PRECISION` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `SUPPORT_MX_PLUS` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `SUPPORT_INPUT_BUFFERING` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `ENABLE_SHARED_SCALING` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `USE_LNS_MUL` | ❌ | ❌ | ❌ | ❌ | ❌ |
| `SUPPORT_SERIAL` | ❌ | ❌ | ❌ | ❌ | ✅ |
| `ALIGNER_WIDTH` | **40** | **40** | **40** | **32** | **32** |
| `ACCUMULATOR_WIDTH` | **32** | **32** | **32** | **24** | **24** |

## 4. Automated Gate Impact Analysis (Post-Optimization)

| Feature Flag | Configuration | Total Cells | Delta (vs Full) |
|---|---|---|---|
| **Baseline (Full)** | All features enabled | 6499 | 0 |
| `SUPPORT_E4M3` | Disable E4M3 | 6382 | -117 |
| `SUPPORT_E5M2` | Disable E5M2 | 6250 | -249 |
| `SUPPORT_MXFP6` | Disable MXFP6 | 6303 | -196 |
| `SUPPORT_MXFP4` | Disable MXFP4 | 6434 | -65 |
| `SUPPORT_VECTOR_PACKING` | Disable Vector Packing | 4148 | -2351 |
| `SUPPORT_INT8` | Disable INT8 (4x4 mult) | 6244 | -255 |
| `SUPPORT_PIPELINING` | Disable Pipelining | 6446 | -53 |
| `SUPPORT_ADV_ROUNDING` | Disable Adv. Rounding | 6467 | -32 |
| `SUPPORT_MIXED_PRECISION`| Disable Mixed Precision| 6375 | -124 |
| `SUPPORT_INPUT_BUFFERING`| Disable Input Buffering | 6479 | -20 |
| `SUPPORT_MX_PLUS` | Disable MX+ outlier extensions | 5931 | -568 |
| `ENABLE_SHARED_SCALING` | Disable hardware scaling | 6216 | -283 |
| **Tiny (All Disabled)** | All features disabled | 2116 | -4383 |
| **Ultra-Tiny** | Tiny config + Reduced widths (32/24) | 1862 | -4637 |
| **Tiny-Serial** | Ultra-Tiny + Serial Infra | 1859 | -4640 |
| **1x1 Tile Target (Min)**| Min. widths (24/20) | 1591 | -4908 |
| **LNS Multiplier (Mitchell)** | Mitchell multiplier | 6647 | +148 |
| **LNS Multiplier (Precise)** | Precise LNS multiplier | 6773 | +274 |

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

- **Parameter Injection**: Support parameter overrides via `COMPILE_ARGS` in the CI pipeline.
- **GitHub Actions Matrix**: Updated `.github/workflows/test.yaml` to include Full, Lite, Tiny, and Ultra-Tiny variants.
- **Testbench Adaptations**: Updated `test/test.py` to dynamically detect and skip tests based on hardware parameters.

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
