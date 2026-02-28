# Refactoring Concept: Parameterized MXFP8 MAC Unit

This document proposes a refactoring strategy to make the OCP MXFP8 Streaming MAC Unit modular and scalable. By introducing Verilog parameters, the design can be easily reconfigured to fit different Tiny Tapeout tile sizes (e.g., 1x1 vs 1x2) by enabling or disabling specific features.

## 1. Proposed Parameters

The following parameters will be introduced in the top-level module `tt_um_chatelao_fp8_multiplier` and propagated to the respective sub-modules.

| Parameter | Default | Description | Estimated Gate Savings |
|---|---|---|---|
| `ENABLE_SHARED_SCALING` | `1` | Enables hardware-accelerated shared scaling in Cycle 36. | ~300 |
| `SUPPORT_MXFP6` | `1` | Enables decoding for E3M2 and E2M3 formats. | ~170 |
| `SUPPORT_MXFP4` | `1` | Enables decoding for E2M1 format. | ~80 |
| `SUPPORT_ADV_ROUNDING` | `1` | Enables CEIL and FLOOR rounding modes. | ~100 |
| `SUPPORT_MIXED_PRECISION` | `1` | Allows independent format selection for A and B. | ~150 |
| `ALIGNER_WIDTH` | `40` | Internal datapath width for the product aligner. | ~200 (if 64->40) |

## 2. Recommended Refactorings

### 2.1. Multiplier Core (`fp8_mul.v`)
- [x] **Conditional Decoding**: Use logic pruning based on `SUPPORT_MXFP6` and `SUPPORT_MXFP4`.
- [x] **Bias Simplification**: Bias logic is simplified based on supported formats.
- [ ] **Shared Decoders**: (Optional) Use a single decoder set if `SUPPORT_MIXED_PRECISION` is `0`.

### 2.2. Product Aligner (`fp8_aligner.v`)
- [x] **Configurable Rounding**: Logic for `R_CEL` and `R_FLR` is pruned if `SUPPORT_ADV_ROUNDING` is disabled.
- [x] **Internal Bit-width**: Fully parameterize the internal registers using `ALIGNER_WIDTH`.

### 2.3. Top-Level Integration (`project.v`)
- [x] **FSM Guarding**: Shared scaling logic is conditionally enabled via `ENABLE_SHARED_SCALING`.
- [ ] **Register Pruning**: (Optional) Conditionally instantiate registers for `format_b` and `scale_b`.
- [x] **Fast Start Logic**: Verified correctness with all parameter variants.

## 3. Deployment Variants

| Variant | Tile Size | Parameters |
|---|---|---|
| **Full** | 1x2 | All features enabled. |
| **Lite** | 1x1 | `SUPPORT_MXFP6=0`, `SUPPORT_MXFP4=0`, `SUPPORT_ADV_ROUNDING=0`. |
| **Tiny** | 1x1 | `Lite` + `ENABLE_SHARED_SCALING=0`, `SUPPORT_MIXED_PRECISION=0`. |

## 4. CI/CD Proposal: Matrix Testing

To ensure the integrity of all variants, the CI/CD pipeline is updated to test multiple configurations on every build.

- [x] **4.1. Parameter Injection**: Support parameter overrides via `COMPILE_ARGS` in the CI pipeline.
- [x] **4.2. GitHub Actions Matrix**: Updated `.github/workflows/test.yaml` to include Full, Lite, and Tiny variants.
- [x] **4.3. Testbench Adaptations**: Updated `test/test.py` to dynamically detect and skip tests based on hardware parameters.

## 5. Refactoring Progress

- [x] Parameterize Multiplier Core (`SUPPORT_MXFP6`, `SUPPORT_MXFP4`)
- [x] Parameterize Product Aligner (`SUPPORT_ADV_ROUNDING`, `ALIGNER_WIDTH`)
- [x] Parameterize Top-Level (`ENABLE_SHARED_SCALING`, `SUPPORT_MIXED_PRECISION`)
- [x] Update CI pipeline for parameter injection
- [x] Update `test/test.py` for dynamic test skipping
- [x] Verify **Full** Variant
- [x] Verify **Lite** Variant
- [x] Verify **Tiny** Variant
