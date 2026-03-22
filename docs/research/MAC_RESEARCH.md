# Research: Smallest Verilog/FPGA MAC Implementations

This document summarizes the research into area-optimized Multiply-Accumulate (MAC) implementations, comparing the current project with other known architectures.

## Area Comparison Table

| Implementation | Size (Gates/Area) | Source Location | Similarities / Differences | Potential Improvements / Learnings |
|---|---|---|---|---|
| **OCP MXFP8 MAC (This Project - Ultra-Tiny)** | ~2,026 Gates | `src/` | Current baseline. Uses temporal (streaming) processing. Uses individual exponents ($E_i$) and a shared scale ($X$): $V_i = (-1)^{S_i} \times 2^{E_i - \text{Bias}} \times (1 + M_i) \times 2^{X-127}$. | Already optimized via register pruning and shared decoders. |
| **Microsoft Floating Point (MSFP)** | Comparable to MXFP4 | Rouhani et al. (2020) | Uses single-level shared exponents for a block. No individual exponents. | Simpler element decoding; explores coarser scaling. |
| **Shared Microexponents (SMX)** | Comparable to MXFP4 | Rouhani et al. (2023) | Multi-level scaling with sub-group microexponents. | Sub-block scaling improves dynamic range for outliers. |
| **Clive Chan's `fp8_mul`** | Unknown (Sub-component) | [GitHub](https://github.com/cchan/fp8_mul) | Core arithmetic logic source for this project. | Highly optimized combinatorial path for FP8. |
| **Bit-Serial Multiplier** | < 200 Gates (Est.) | Academic / Open Source | Processes one bit per cycle. Extremely low area. | Could be used for Ultra-Ultra-Tiny variants if throughput is not a concern. |
| **Stochastic MAC** | < 100 Gates (Est.) | Academic Research | Uses bit-streams and logic gates for arithmetic. | Extreme area efficiency at the cost of precision and latency. |
| **Mitchell's Approx. Multiplier** | ~5,541 Gates (LNS Variant) | `src/fp8_mul_lns.v` | Logarithmic approximation to avoid full multipliers. | Reduces multiplier area; already integrated as an option. |
| **Samson et al. FPGA MX** | Unknown | [arXiv:2407.01475](https://arxiv.org/abs/2407.01475) | Uses binary tree summation and Kulisch accumulation. | Optimized for FPGA DSP and LUT structures. |
| **PULP FPNew (ETH Zurich)** | Variable (Multi-format) | [GitHub](https://github.com/pulp-platform/fpnew) | Support for FP8 (E4M3/E5M2) in CVFPU/FPNew. | Highly configurable; significantly larger than streaming units. |
| **RISC-V ZvfofpXmin (Est.)** | ~15,000 Gates | [Gap Analysis](ZVFOFPXMIN_GAP.md) | Proposed minimal vector extension for OCP MX. | Includes VRF and ISA decoding overhead. |
| **Berkeley Hardfloat** | Variable | [GitHub](https://github.com/ucb-bar/berkeley-hardfloat) | Parameterized FPU generators (RISC-V compatible). | Industry standard for open-source IEEE-754 logic. |
| **UCB Gemmini** | Variable | [GitHub](https://github.com/ucb-bar/gemmini) | Full-stack systolic array generator. | Supports quantization and various low-bit formats. |
| **Vortex GPU** | Variable | [GitHub](https://github.com/vortexgpgpu/vortex) | Open source RISC-V GPGPU. | Focuses on SIMT scalability and GPU-style FP units. |
| **Seyviour Log-FP8** | Unknown | [GitHub](https://github.com/Seyviour/log-fp8) | Log-based FP8 (E4M3) adder/multiplier. | Uses LUT-6 for significand multiplication. |
| **Rejunity 4-bit MatMul** | ~6 Slices | [GitHub](https://github.com/rejunity/tiny-asic-4bit-matrix-mul) | 4-bit matrix multiplication for Tiny Tapeout. | Uses ternary weights and compact case-based decoding. |
| **fpu-wrappers suite** | Variable | [GitHub](https://github.com/jiegec/fpu-wrappers) | Wrappers for `fudian`, `vfloat`, `flopoco`, `CNRV-FPU`. | Comparison of open-source FPU area/freq/power. |
| **Taner Oksuz FPU** | Low Resource | [GitHub](https://github.com/taneroksuz/fpu) | IEEE-754 Single/Double precision. | Pseudo-extended precision avoids complex subnormal handling. |
| **AMD TensorCast** | Software Ref | [GitHub](https://github.com/amd/tensorcast) | Quantization library for OCP MX and AMD datatypes. | Useful for hardware verification and reference models. |

## Industry-Driven BFP Variants (Microsoft / Rouhani et al.)

This section explores the Block Floating-Point (BFP) variants developed by Microsoft Research (Rouhani et al.) and evaluates their architectural trade-offs compared to the OCP MX and MX+ implementations used in this project.

### Microsoft Floating Point (MSFP)
*   **Source**: Rouhani et al. (2020), deployed in Project Brainwave.
*   **Architecture**:
    *   **Block Size**: Typically 16 elements.
    *   **Scaling**: Single-level 8-bit shared exponent ($e_{shared}$) per block, set to the exponent of the largest absolute value.
    *   **Element Format**: Elements consist only of a sign bit and mantissa bits. Individual exponents are eliminated.
    *   **Decoding**: Elements are obtained by right-shifting the original values by the difference between $e_{shared}$ and the original exponent. There are no implicit leading bits.
*   **Usefulness for our Product**:
    *   **Pros**: Simplest element decoding logic; ideal for extremely area-constrained FPGA/ASIC targets where silicon budget for individual decoders is non-existent.
    *   **Cons**: Lower numerical accuracy than OCP MX at similar bit-widths because it lacks the dynamic range provided by per-element exponents.

### Shared Microexponents (SMX)
*   **Source**: Rouhani et al. (2023).
*   **Architecture**:
    *   **Scaling**: Multi-level scaling approach.
    *   **Structure**: A group of 16 elements ($k_1=16$) shares a first-level 8-bit exponent. Within that group, pairs of elements ($k_2=2$) share a 1-bit "sub-scale" or microexponent.
    *   **Dynamic Range**: The microexponent provides an additional shift, allowing sub-blocks to adapt to local outliers.
*   **Usefulness for our Product**:
    *   **Pros**: Significantly improves dynamic range compared to MSFP; effectively handles local outliers within a larger block.
    *   **Cons**: Introduces multi-level shifting complexity in the datapath and requires more complex metadata management than the OCP MX streaming protocol.

### Comparative Analysis: Why OCP MX + MX+?
The current project implements OCP MX (and the MX+ extension) rather than MSFP or SMX for several strategic reasons:
1.  **Standardization**: OCP MX is an industry-standard (AMD, Arm, Intel, Meta, Microsoft, NVIDIA, Qualcomm), ensuring broader compatibility.
2.  **Granularity**: Unlike MSFP/SMX, OCP MX elements retain their own (narrow) exponent bits. This "per-element" exponent allows for much finer-grained scaling and better accuracy for LLM activations.
3.  **Outlier Handling (MX+)**: Our implementation of MX+ (repurposing the BM exponent as mantissa) provides the outlier accuracy of much wider formats (like FP6 or FP8) while maintaining the 4-bit footprint of MXFP4, outperforming the accuracy-per-bit of both MSFP and SMX.

## Research Blockers
Extensive searches for a "Top 10" list of specific gate counts for open-source MAC units were performed. However, the search tools consistently failed to return high-quality results for specific technical queries regarding gate counts of various GitHub implementations. Most information was derived from internal documentation and architectural analysis of referenced papers (MSFP, SMX, MX).

## Conclusion
The current "Ultra-Tiny" implementation at ~2,000 gates is highly competitive for a full-featured floating-point MAC supporting multiple OCP MX formats. Further reduction would likely require moving to bit-serial or stochastic architectures, which deviate from the streaming protocol requirements.
