# Audit: Float32 Implementation & Numerical Precision

> **Status: Resolved (Historical Audit).** All remediation phases below (Steps 9–28: 40-bit S23.16 datapath, `lzc40`, `fixed_to_float`, and Cocotb verification) have been implemented and verified.

## 1. Executive Summary
This audit originally evaluated the early "Float32" implementation in the OCP MX Streaming MAC unit, when the RTL produced a **32-bit signed fixed-point** result without hardware normalization.

## 2. Implementation Gaps (Resolved)
The following gaps were identified between the architectural intent and the early RTL:

### 2.1. Missing Fixed-to-Float Conversion
*   **Original State**: The `accumulator` module stored results in a 32-bit signed fixed-point format, serialized directly.
*   **Resolution**: Implemented `src/fixed_to_float.v` and `src/lzc40.v` (selectable via `ui_in[5]` in Cycle 0, pruned optionally via `SUPPORT_FLOAT32`).

### 2.2. Accumulator Precision vs. Dynamic Range
*   **Original Format**: 32-bit signed fixed-point with 8 fractional bits (bit 8 = $2^0$).
*   **Resolution**: Upgraded default internal datapath to 40-bit S23.16 (`ALIGNER_WIDTH=40`, `ACCUMULATOR_WIDTH=40`) and added hardware shared-exponent scaling in `fixed_to_float.v`.

## 3. Remediation Plan (Completed)
Executed per [ROADMAP.md](../ROADMAP.md#completed-milestones):

1.  **Infrastructure & Datapath (Steps 9-10)**: Parameterized widths to 40-bit and shifted the binary point to bit 16 to preserve FP8 subnormal precision.
2.  **Hardware F2F Engine (Steps 11-24)**: Implemented a Fixed-to-Float converter including Leading Zero Count (`lzc40`), normalization, RNE rounding, and special value (NaN/Inf) muxing.
3.  **Integration & Verification (Steps 25-28)**: Hooked up Float32 mode (`ui_in[5]`) to the streaming protocol and validated compliance using a bit-accurate Cocotb reference model.
