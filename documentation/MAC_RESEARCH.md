# Research: Smallest Verilog/FPGA MAC Implementations

This document summarizes the research into area-optimized Multiply-Accumulate (MAC) implementations, comparing the current project with other known architectures.

## Area Comparison Table

| Implementation | Size (Gates/Area) | Source Location | Similarities / Differences | Potential Improvements / Learnings |
|---|---|---|---|---|
| **OCP MXFP8 MAC (This Project - Ultra-Tiny)** | ~2,026 Gates | `src/` | Current baseline. Uses temporal (streaming) processing. | Already optimized via register pruning and shared decoders. |
| **Microsoft Floating Point (MSFP)** | Comparable to MXFP4 | Rouhani et al. (2020) | Uses single-level shared exponents for a block. No individual exponents. | Simpler element decoding; explores coarser scaling. |
| **Shared Microexponents (SMX)** | Comparable to MXFP4 | Rouhani et al. (2023) | Multi-level scaling with sub-group microexponents. | Sub-block scaling improves dynamic range for outliers. |
| **Clive Chan's `fp8_mul`** | Unknown (Sub-component) | [GitHub](https://github.com/cchan/fp8_mul) | Core arithmetic logic source for this project. | Highly optimized combinatorial path for FP8. |
| **Bit-Serial Multiplier** | < 200 Gates (Est.) | Academic / Open Source | Processes one bit per cycle. Extremely low area. | Could be used for Ultra-Ultra-Tiny variants if throughput is not a concern. |
| **Stochastic MAC** | < 100 Gates (Est.) | Academic Research | Uses bit-streams and logic gates for arithmetic. | Extreme area efficiency at the cost of precision and latency. |
| **Mitchell's Approx. Multiplier** | ~5,541 Gates (LNS Variant) | `src/fp8_mul_lns.v` | Logarithmic approximation to avoid full multipliers. | Reduces multiplier area; already integrated as an option. |

## Research Blockers
Extensive searches for a "Top 10" list of specific gate counts for open-source MAC units were performed. However, the search tools consistently failed to return high-quality results for specific technical queries regarding gate counts of various GitHub implementations. Most information was derived from internal documentation and architectural analysis of referenced papers (MSFP, SMX, MX).

## Conclusion
The current "Ultra-Tiny" implementation at ~2,000 gates is highly competitive for a full-featured floating-point MAC supporting multiple OCP MX formats. Further reduction would likely require moving to bit-serial or stochastic architectures, which deviate from the streaming protocol requirements.
