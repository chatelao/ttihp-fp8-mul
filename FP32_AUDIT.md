# Audit: Float32 Implementation & Numerical Precision

## 1. Executive Summary
This audit evaluates the current implementation of "Float32" results in the OCP MX Streaming MAC unit. While the documentation (`docs/info.md`) and web-based Digital Twin (`docs/web/mac.js`) treat the 32-bit output as an IEEE 754 Binary32 (Float32) value, the RTL implementation (`src/project.v` and `src/accumulator.v`) actually produces a **32-bit signed fixed-point** result.

## 2. Implementation Gaps
The following major gaps have been identified between the architectural intent and the current RTL:

### 2.1. Missing Fixed-to-Float Conversion
*   **Current State**: The `accumulator` module stores results in a 32-bit signed fixed-point format. These 32 bits are serialized and shifted out directly.
*   **Discrepancy**: The web interface uses `DataView.getFloat32()` to interpret these bits. Because the bits represent a fixed-point integer rather than a Float32 bit pattern, the decimal values displayed in the demo are mathematically incorrect.
*   **Missing Hardware**: A hardware normalization stage (Leading Zero Count, Barrel Shifter, and Exponent Adjustment) is required to convert the internal fixed-point total into a valid IEEE 754 bit pattern.

### 2.2. Accumulator Precision vs. Dynamic Range
*   **Current Format**: 32-bit signed fixed-point with 8 fractional bits (bit 8 = $2^0$).
*   **Resolution**: $2^{-8} \approx 0.0039$.
*   **FP8 Subnormal Underflow**:
    *   E4M3 subnormals reach $2^{-9}$.
    *   E5M2 subnormals reach $2^{-14}$.
    *   Products involving these values are currently truncated to zero by the `fp8_aligner` because they fall below the $2^{-8}$ threshold of the fixed-point accumulator.
*   **Dynamic Range**: The OCP MX spec allows shared scales up to $2^{127}$. A 32-bit fixed-point accumulator cannot represent the results of such large scales without immediate saturation.

## 3. Precision Gaps in FP8 Min/Max Cases

### 3.1. Underflow (Min Cases)
The `fp8_aligner.v` calculates `shift_amt = exp_sum - 5`. This assumes bit 5 of the product is aligned to the 2^0 position of the accumulator (which is inconsistent with the "bit 8 = 2^0" comment in some docs, but matches the LSB-heavy truncation seen in tests).
Regardless of the specific bit alignment, the **finite window of the accumulator (32 bits)** is significantly smaller than the **dynamic range of FP8/MX formats (hundreds of orders of magnitude)**.
*   **Impact**: Blocks containing only very small values (subnormals) yield a result of exactly `0.0` even when the mathematical sum is non-zero.

### 3.2. Saturation (Max Cases)
*   **Shared Scale Impact**: If $X_A + X_B - 254$ is large (e.g., > 30), any normal product will immediately saturate the 32-bit fixed-point accumulator.
*   **Overflow Handling**: While the unit supports a "Wrap" mode, standard AI inference requires saturation or high-dynamic range (Float32).

## 4. Remediation Plan (Technical)
To align the hardware with the OCP MX and Float32 requirements, the project follows a granular 20-step roadmap detailed in [ROADMAP.md](ROADMAP.md#5-numerical-precision--fp32-compliance).

### Key Execution Phases:
1.  **Infrastructure & Datapath (Steps 9-10)**: Parameterize widths to 40-bit and shift the binary point to bit 16 to preserve FP8 subnormal precision.
2.  **Hardware F2F Engine (Steps 11-24)**: Implement a pipelined Fixed-to-Float converter including Leading Zero Count (LZC), normalization, RNE rounding, and special value (NaN/Inf) muxing.
3.  **Integration & Verification (Steps 25-28)**: Hook up the Float32 mode to the streaming protocol and validate compliance using a bit-accurate Cocotb reference model.
