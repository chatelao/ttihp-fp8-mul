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
- **Conditional Decoding**: Use `generate` blocks or logic pruning based on `SUPPORT_MXFP6` and `SUPPORT_MXFP4`.
- **Bias Simplification**: If narrow formats are disabled, the bias ROM/mux logic can be simplified to support only E4M3, E5M2, and INT8.
- **Shared Decoders**: If `SUPPORT_MIXED_PRECISION` is `0`, only one set of format decoders is instantiated, and both operands share the same format configuration.

### 2.2. Product Aligner (`fp8_aligner.v`)
- **Configurable Rounding**: Use parameters to prune the logic for `R_CEL` and `R_FLR` if `SUPPORT_ADV_ROUNDING` is disabled.
- **Internal Bit-width**: Fully parameterize the internal registers (`shifted`, `base`, `rounded`) using `ALIGNER_WIDTH`.

### 2.3. Top-Level Integration (`project.v`)
- **FSM Pruning**: If `ENABLE_SHARED_SCALING` is `0`, the FSM can be shortened, and the logic to feed the accumulator back into the aligner can be removed.
- **Register Pruning**: Conditionally instantiate registers for `format_b` and `scale_b` based on `SUPPORT_MIXED_PRECISION` and `ENABLE_SHARED_SCALING`.
- **Fast Start Logic**: If features are pruned, the "Fast Start" jump target might need adjustment.

## 3. Deployment Variants

| Variant | Tile Size | Parameters |
|---|---|---|
| **Full** | 1x2 | All features enabled. |
| **Lite** | 1x1 | `SUPPORT_MXFP6=0`, `SUPPORT_MXFP4=0`, `SUPPORT_ADV_ROUNDING=0`. |
| **Tiny** | 1x1 | `Lite` + `ENABLE_SHARED_SCALING=0`, `SUPPORT_MIXED_PRECISION=0`. |

## 4. CI/CD Proposal: Matrix Testing

To ensure the integrity of all variants, the CI/CD pipeline should be updated to test multiple configurations on every build.

### 4.1. Updated `test/Makefile`
The Makefile should be modified to accept parameter overrides via `COMPILE_ARGS`:
```makefile
# Example usage: make EXTRA_ARGS="-Ptt_um_chatelao_fp8_multiplier.SUPPORT_MXFP6=0"
COMPILE_ARGS += $(EXTRA_ARGS)
```

### 4.2. GitHub Actions Matrix
Update `.github/workflows/test.yaml` to include a test matrix:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        variant: [full, lite, tiny]
        include:
          - variant: full
            args: ""
          - variant: lite
            args: "-Ptt_um_chatelao_fp8_multiplier.SUPPORT_MXFP6=0 -Ptt_um_chatelao_fp8_multiplier.SUPPORT_MXFP4=0"
          - variant: tiny
            args: "-Ptt_um_chatelao_fp8_multiplier.SUPPORT_MXFP6=0 -Ptt_um_chatelao_fp8_multiplier.SUPPORT_MXFP4=0 -Ptt_um_chatelao_fp8_multiplier.ENABLE_SHARED_SCALING=0"
    steps:
      - name: Run tests
        run: |
          cd test
          make EXTRA_ARGS="${{ matrix.args }}"
```

### 4.3. Testbench Adaptations
The cocotb testbench (`test/test.py`) should be updated to:
1. Detect enabled features (e.g., via a register read or a dedicated `VERSION` parameter).
2. Dynamically skip test cases that rely on disabled formats or rounding modes.

## 5. Refactoring Progress

- [x] Parameterize Multiplier Core (`SUPPORT_MXFP6`, `SUPPORT_MXFP4`)
- [x] Parameterize Product Aligner (`SUPPORT_ADV_ROUNDING`, `ALIGNER_WIDTH`)
- [x] Parameterize Top-Level (`ENABLE_SHARED_SCALING`, `SUPPORT_MIXED_PRECISION`)
- [x] Update `test/Makefile` for parameter injection
- [x] Update `test/test.py` for dynamic test skipping
- [x] Verify **Full** Variant
- [x] Verify **Lite** Variant
- [x] Verify **Tiny** Variant
