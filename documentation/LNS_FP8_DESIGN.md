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

### 3.2. LNS Adder & Precise LUT
Instead of a $4 \times 4$ or $8 \times 8$ mantissa multiplier, the design employs a logarithmic sum.

#### 3.2.1. Mitchell Approximation (Default)
The fractional bits (mantissa) are added directly. For two mantissas $M_A$ and $M_B$:
$$M_{res} = M_A + M_B$$
If $M_A + M_B \ge 1$, the overflow (carry) is propagated to the exponent sum, effectively performing the $\log_2(1+M) \approx M$ approximation.

#### 3.2.2. Precise LNS LUT (`USE_LNS_MUL_PRECISE=1`)
To reduce the $11.1\%$ error, a 64-entry Look-Up Table (LUT) is used. The LUT is indexed by the most significant bits of both mantissas:
`index = {ma[2:0], mb[2:0]}`
The LUT returns a 4-bit value `{carry, m_sum[2:0]}`. This provides a more accurate approximation of $\log_2((1+M_A)(1+M_B))$ than simple addition, particularly in the middle of the mantissa range where Mitchell's error is highest.

### 3.3. MX+ Hybrid Datapath
When `SUPPORT_MX_PLUS=1` is enabled, the unit must handle "Block Max" (BM) elements which require full precision for scaling. The LNS multiplier implements a hybrid path:
1. **BM Path**: If either operand is a BM element (indicated by `is_bm_a` or `is_bm_b`), a standard $4 \times 4$ or $8 \times 8$ significand multiplier is used.
2. **LNS Path**: For all other elements, the LNS log-adder is used.
This ensures that the critical scaling factors in the MX block maintain bit-exactness, while the bulk of the element-wise multiplications benefit from LNS area savings.

### 3.4. Antilog-Conversion (Identity Mapping)
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
    input  wire       is_bm_a,
    input  wire       is_bm_b,
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

## 8. Implementation Review (Added March 2025)
This section summarizes the final verification and physical impact analysis of the LNS implementation within the OCP MX MAC unit.

### 8.1. Functional Parity
The LNS multiplier was verified using the comprehensive Cocotb test suite across all supported OCP MX formats (E4M3, E5M2, E3M2, E2M3, E2M1).
*   **Mitchell Mode (`USE_LNS_MUL_PRECISE=0`)**: Achieved 100% functional parity with the Python-based Mitchell approximation model. The deterministic 11.1% maximum relative error was confirmed to be correctly modeled and matched in hardware.
*   **Precise Mode (`USE_LNS_MUL_PRECISE=1`)**: The 64-entry LUT-based approach successfully reduced the approximation error while maintaining functional consistency between the RTL and the verification model.
*   **MX+ Compatibility**: The hybrid path, which uses standard multiplication for Block Max (BM) elements to preserve precision, was verified to work correctly in conjunction with LNS for non-BM elements.

### 8.2. Physical Impact Analysis
Synthesis results (using Yosys) for the isolated multiplier core (`fp8_mul` vs `fp8_mul_lns`) demonstrate significant silicon area savings for non-MX+ configurations.

| Multiplier Variant | Gates (Cells) | Area Reduction (vs Std) |
|--------------------|---------------|-------------------------|
| Standard (Exact)   | 850           | -                       |
| Mitchell LNS       | 402           | ~52.7%                  |
| Precise LNS        | 463           | ~45.5%                  |

### 8.3. Conclusion
The LNS-based multiplier provides a highly effective area-optimization knob for the OCP MX MAC unit. For applications where the approximation error is tolerable (e.g., specific deep learning inference tasks), the Mitchell variant offers a >50% reduction in multiplier core area, making it an ideal choice for the most area-constrained Tiny Tapeout configurations.

## 9. Analysis: Bit-Serial LNS Implementation
This section analyzes the feasibility and impact of combining Logarithmic Number System (LNS) principles with Bit-Serial architectural techniques.

### 9.1. Conceptual Overview
In a standard bit-serial implementation (e.g., `OCP_MX_SERIAL.md`), multiplication is usually the most complex operation, requiring a shift-and-add structure (like a Braun or Booth multiplier) that takes $O(N^2)$ or $O(N \times K)$ cycles and significant control logic.

By applying LNS, the bit-serial multiplication ($M_A \times M_B$) is transformed into a **bit-serial addition** of the logarithms.

#### 9.1.1. 1-Bit Log-Adder Datapath
The bit-serial LNS multiplier core consists of:
- **1-bit Full Adder**: Processes the incoming bits of $\log_2(A)$ and $\log_2(B)$ starting from the LSB.
- **Carry Flip-Flop**: Stores the carry-out from the current bit addition to be fed back into the next cycle.
- **Carry-Save Synchronization**: Since the exponent and mantissa are concatenated, the carry-out from the MSB of the mantissa naturally propagates into the LSB of the exponent, exactly matching the behavior of the parallel LNS adder.

#### 9.1.2. Control & Gating
A small bit-counter (3-4 bits) tracks the field boundaries. This allows the logic to:
- Reset the carry flip-flop at the start of each new element.
- Apply bias correction by injecting a constant bit-stream into a second 1-bit subtractor stage.

### 9.2. Comparison: Parallel vs. Bit-Serial LNS

| Metric | Parallel LNS | Bit-Serial LNS |
|-----------|------------------|-------------------|
| **Datapath** | N-bit Parallel Adder | 1-bit Full Adder |
| **Area (Multiplier Core)** | ~60-100 Gates | ~15-25 Gates |
| **Latency** | 1 Cycle | $N$ Cycles (where $N$ is field width) |
| **Throughput** | 1 Element/Cycle | 1 Element / $K$ Cycles |
| **Routing** | N-bit Bus | 1-bit Signal |

### 9.3. Space Savings Estimation
The transition from a parallel LNS adder to a bit-serial LNS adder yields significant savings in the multiplier core itself, though the total unit savings are moderated by the need for shift registers.

*   **Multiplier Core Reduction**: Switching from a parallel 8-bit log-adder (~80 gates) to a bit-serial 1-bit adder (~20 gates including carry-flop and local control) results in a **~75% reduction** in the multiplier's logical area.
*   **Total Unit Impact**: When integrated into a "Tiny-Serial" variant (which already uses bit-serial alignment and accumulation), the LNS approach removes the need for the bit-serial shift-and-add multiplier control logic. This is estimated to save an additional **40-60 gates** per lane compared to a standard bit-serial multiplier.

### 9.4. Bit-Serial FP4-LNS (E2M1)
For the FP4 format, the advantages are even more pronounced:
*   **Extreme Minimalist**: An FP4 (E2M1) log-addition is only 3 bits wide.
*   **Cycle Efficiency**: If $K=8$, the bit-serial LNS operation completes in 3 cycles, leaving 5 cycles of "idle" time that can be used for power-gating or processing additional packed elements.
*   **Gate Count**: A dedicated Bit-Serial FP4-LNS multiplier could potentially be implemented in **under 15 gates**, making it the smallest possible floating-point multiplier architecture.

### 9.5. Conclusion
A bit-serial LNS implementation represents the "logical floor" of OCP MX hardware. It provides the absolute minimum area footprint by reducing the multiplier—traditionally the largest component—to a single bit-serial addition stage. This configuration is highly recommended for ultra-dense systolic arrays where individual node area is the primary constraint.

## 10. Implementation Roadmap: LNS Evolution & Bit-Serial Integration
This roadmap outlines the future development phases for LNS-based optimizations in the OCP MX MAC unit.

### 10.1. Phase A: Robustness & Special Value Handling
*   **NaN/Infinity Propagation**: Currently, LNS log-addition may produce valid-looking results for special values. This phase involves adding element-wise detection for IEEE-754 NaNs and Infinities.
*   **Sticky Registers**: Implement sticky status registers that latch NaN/Overflow flags during the 32-element block processing.
*   **Subnormal Support**: Refine the LNS adder to handle subnormal inputs by detecting leading zeros and adjusting the log-base accordingly, or by flushing to zero (FTZ) for area-constrained variants.

### 10.2. Phase B: Bit-Serial LNS Core (Step 4 Extension)
*   **Module Development**: Implement `src/fp8_mul_serial_lns.v` using the 1-bit full adder and carry-save synchronization described in Section 9.
*   **Bias Subtractor**: Integrate a bit-serial bias subtraction stage using a second full-adder/carry-flop pair or a specialized serial subtractor.
*   **Verification**: Create a dedicated Cocotb testbench for the bit-serial LNS core, validating it against the parallel Mitchell model.

### 10.3. Phase C: Serial Integration & Stretched Protocol
*   **Tiny-Serial Integration**: Swap the existing bit-serial multiplier (if any) or parallel multiplier in the Tiny-Serial variant with the new `fp8_mul_serial_lns`.
*   **Timing Alignment**: Ensure that the bit-serial log-sum is available in synchronization with the serial aligner and accumulator stages.
*   **Resource Pruning**: Remove the redundant shift registers required by traditional bit-serial multipliers, reclaiming ~30-50 gates.

### 10.4. Phase D: Benchmarking & Physical Analysis
*   **Gate Count Comparison**: Perform a side-by-side synthesis comparison between:
    1.  Standard Parallel Multiplier
    2.  Parallel Mitchell LNS
    3.  Bit-Serial Mitchell LNS
*   **Power Profiling**: Utilize gate-level simulation (GLS) with switching activity (VCD) to quantify the power reduction achieved by the minimal switching of the 1-bit LNS adder.
*   **Final Report**: Document the results in `documentation/DIE_SIZE_ANALYSIS.md`.
