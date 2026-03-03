# Design Document: LNS-based FP8 Multiplier (Mitchell's Approximation)

## 1. Overview
This document describes a hardware-efficient FP8 multiplier that utilizes the Logarithmic Number System (LNS) principle, specifically **Mitchell's Approximation**, to replace power-intensive integer multipliers with simple additions. This design is intended as a drop-in replacement for the standard `fp8_mul` module in the OCP MX MAC Unit.

## 2. Mathematical Basis
The standard floating-point representation for a value $V$ is:
$$V = (-1)^S \times 2^{E - \text{Bias}} \times (1 + M)$$

Taking the base-2 logarithm:
$$\log_2(|V|) = (E - \text{Bias}) + \log_2(1 + M)$$

### Mitchell's Approximation
Mitchell's approximation simplifies the logarithmic term:
$$\log_2(1 + M) \approx M, \quad \text{for } M \in [0, 1)$$

Thus:
$$\log_2(|V|) \approx E - \text{Bias} + M$$

In hardware, if $E$ and $M$ are concatenated (with $M$ as the fractional part), the resulting bit string is a fixed-point representation of the logarithm.

### Multiplication via Addition
To multiply two numbers $A$ and $B$:
$$\log_2(|A \times B|) = \log_2(|A|) + \log_2(|B|)$$
$$\log_2(|A \times B|) \approx (E_A + M_A) + (E_B + M_B) - 2 \times \text{Bias}$$

The result of the addition can be directly interpreted as the exponent and mantissa of the product (Antilog-conversion).

## 3. Hardware Architecture

### 3.1. Log-Conversion (Identity Mapping)
Since the FP8 format already stores $E$ and $M$ in a concatenated format, the "conversion" to LNS is a zero-cost identity mapping. We simply treat the bits $[E, M]$ as a fixed-point number.

### 3.2. LNS Adder
Instead of a $4 \times 4$ or $8 \times 8$ mantissa multiplier, we use a single adder:
1. **Exponent Sum**: Add the biased exponents and subtract the bias.
2. **Mantissa "Multiplication"**: The fractional bits of the LNS sum become the new mantissa.
3. **Carry Handling**: A carry out from the mantissa addition automatically increments the exponent sum, which correctly handles the $1+M \ge 2$ case in floating-point normalization.

### 3.3. Antilog-Conversion (Identity Mapping)
The sum is already in the $[E, M]$ format. No complex circuitry is required to convert back to the standard floating-point representation.

## 4. Implementation Details

### Drop-in Interface
The module maintains the exact interface as the current `fp8_mul.v`:
```verilog
module fp8_mul_lns (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire [2:0] format_a,
    input  wire [2:0] format_b,
    output wire [15:0] prod,    // Interpreted as (1 + M_res) << shift
    output wire signed [6:0] exp_sum,
    output wire       sign
);
```

### Resource Savings
| Component | Standard (Exact) | LNS (Approximate) |
|-----------|------------------|-------------------|
| Multiplier| 4x4 or 8x8 Multiplier | None |
| Adder     | Exponent Adder   | Combined Log-Adder |
| Gates     | ~200-400 Gates   | ~50-80 Gates |

## 5. Error Analysis
Mitchell's approximation introduces a deterministic error. The maximum relative error occurs when $M \approx 0.5$ and is approximately $11.1\%$.
However, for many Deep Learning applications (e.g., LLM inference), this approximation error is often acceptable or can be compensated for during quantization-aware training (QAT).

## 6. Integration Roadmap

### 6.1. FSM & Control
- **Parameterization**: Propagate the `USE_LNS_MUL` parameter from `src/project.v` to the top-level configuration.
- **Protocol Stability**: Ensure that the 41-cycle FSM correctly manages the pipeline stages when the LNS multiplier is selected, maintaining cycle-accurate synchronization with `ui_in` and `uio_in`.
- **Mode Switching**: Validate that the configuration byte (Cycle 1) remains compatible with the LNS logic path.

### 6.2. FP8 Multiplier
- **Core Implementation**: Develop `src/fp8_mul_lns.v` implementing the combined log-adder logic.
- **Sign Logic**: Implement the XOR-based sign bit determination for the product.
- **Format Support**: Ensure that the LNS core correctly handles the multiple OCP MX formats (E4M3, E5M2, etc.) by adjusting the "Log-Adder" bias based on `format_a` and `format_b`.

### 6.3. Aligner & Scaler
- **Interface Verification**: Verify that the 16-bit `prod` and 7-bit `exp_sum` outputs from the LNS core are correctly interpreted by the `fp8_aligner.v`.
- **Precision Check**: Ensure the barrel shifter handles the approximate LNS mantissa without additional bit-loss, maintaining the bit-accurate alignment required for the 40-bit internal datapath.

### 6.4. Accumulator
- **Dynamic Range**: Confirm that the 32-bit signed accumulator provides sufficient headroom for the LNS-approximated products across all 32 elements in a block.
- **Saturation Logic**: Verify that the SAT/WRAP overflow modes behave correctly with the modified multiplier output range.

### 6.5. Output Serializer
- **Data Integrity**: Ensure the 32-bit result is correctly captured and serialized over Cycles 37-40.
- **Verification**: Utilize cocotb tests to compare the serialized LNS result against the expected approximate values derived from the Python model.

## 7. FP4-LNS Integration
This section explores the extension of LNS principles to the ultra-low-precision FP4 (E2M1) format.

### 7.1. Integration Variants
1.  **Unified Log-Adder**: A single parameterized adder that handles both FP8 and FP4 formats. In FP4 mode, the lower bits of the adder are gated or ignored, and the bias is statically set to 1. This minimizes area by sharing the same physical logic between formats.
2.  **SIMD Dual-FP4 LNS**: Since an FP4 log-addition is significantly narrower (3-bit) than an FP8 one (6-8 bit), a 1x8-bit adder can be reconfigured as a Dual 3-bit SIMD adder. This allows processing two FP4 multiplications in a single cycle using the same silicon footprint as one FP8 multiplication.
3.  **Hard-Wired LNS Lookup**: For FP4 (E2M1), there are only 8 possible non-zero positive values. Instead of an adder, a tiny combinatorial logic block (or a 16-entry LUT) can pre-compute all possible LNS product results. This is the most area-efficient for FP4-only configurations.

### 7.2. Pros and Cons
**Pros:**
*   **Silicon Uniformity**: Using LNS for both FP8 and FP4 allows for a highly regular datapath where "multiplication" is always an "addition," simplifying the control logic and reducing the number of specialized multiplier circuits.
*   **Extreme Power Efficiency**: FP4 LNS operations involve only 3-bit additions. This reduces switching activity to a bare minimum, making it ideal for battery-powered edge AI applications where power is more critical than absolute precision.

**Cons:**
*   **Precision Floor**: Mitchell's approximation error is more pronounced in narrow formats like FP4 (E2M1). With only 1 bit of mantissa, the relative error of the approximation can significantly impact the convergence of small neural networks.
*   **Diminishing Area Returns**: A 2x2 significand multiplier for FP4 is already extremely small (~20 gates). The area savings from switching that to a 3-bit LNS adder are minimal compared to the savings seen at the FP8/INT8 level.
