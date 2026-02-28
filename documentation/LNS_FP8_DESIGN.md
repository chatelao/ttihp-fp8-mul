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
1. Implement `src/fp8_mul_lns.v`.
2. Create a test bench to compare LNS results with the exact Python model.
3. Add a Verilog parameter `USE_LNS_MUL` to `src/project.v` to allow switching between exact and approximate multiplication.
