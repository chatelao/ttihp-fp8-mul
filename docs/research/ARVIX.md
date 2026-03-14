# Insights from ArXiv Papers on MX Formats

This document summarizes key insights and architectural ideas extracted from relevant research papers regarding OCP Microscaling (MX) formats and their hardware implementations.

## 1. Exploring FPGA designs for MX and beyond
**Source:** [arXiv:2407.01475](https://arxiv.org/abs/2407.01475) (Samson et al., 2024)

### Hardware Architecture & Implementation
- **Binary Tree Summation:** For the `Dot` operation (within a block), adders are arranged in a binary tree structure to perform pairwise summation, which minimizes latency.
- **Error-Free Accumulation:** The paper utilizes Kulisch accumulation (error-free integer accumulation) for dot products within the boundaries of a shared scale. This is viable because shared scales are factored out, leaving a small dynamic range.
- **DotGeneral Operation:** For dot products across block boundaries, the implementation replicates the `Dot` operation and accumulates outputs using adders with normalization (similar to floating-point adders).
- **Adder with Normalization:** This specialized adder uses guard, round, and sticky bits (e.g., $b+3$ bits) to implement "Round to Nearest Even" (RNE) logic when precision is lost.
- **Comparator Trees for Scale:** Scaling factors are computed using a tree of comparators. The depth of the tree is $\lceil \log_2(k) \rceil$. Pipelining is added to keep the critical path only two comparators long.
- **Signal Widths:**
    - MXFP Multiplier Output: $2(1 + 2^E + (M-1))$
    - MXINT Multiplier Output: $2B$
    - Accumulator Width: Incorporates $\log_2(k)$ additional bits to prevent overflow during block summation.

### Numerical Insights
- **Rounding Modes:** RNE is preferred for both conversion and normalization stages to maintain accuracy.
- **Sub-8-bit Efficacy:** MX formats are particularly effective for formats like INT5 or FP6 which aren't natively supported on standard GPUs but offer significant area savings on FPGAs/ASICs.

---

## 2. Microscaling Data Formats for Deep Learning
**Source:** [arXiv:2310.10537](https://arxiv.org/abs/2310.10537) (Rouhani et al., 2023)

### Numerical Representation & Stability
- **Direct-Cast Inference:** 8-bit MX formats (MXINT8, MXFP8) can often be used for inference directly on FP32-pretrained models with minimal accuracy loss, often removing the need for calibration or finetuning.
- **Sub-8-bit Training:** The paper demonstrates the first instance of training generative language models with 6-bit weights, activations, and gradients to FP32 parity without modifying the training recipe.
- **Mixed Precision:** Successful training was also shown using MXFP4 weights and MXFP6 activations/gradients.

### Special Value Handling
- **Two-Level NaN Encoding:**
    1. If the shared scale is NaN (0xFF), all elements in the block are NaN.
    2. If the scale is normal, individual elements can still encode NaN if the element format supports it.
- **Infinity Handling:** Shared scales do not encode Infinity. Infinities are represented at the element level.
- **Subnormal Flushing:** To simplify hardware and software algorithms, subnormal numbers are often flushed to zero during conversion.

### Computational Considerations
- **Non-Commutativity:** Transposing a matrix and quantizing it into MX format are NOT commutative. The "principal dimension" (axis of the shared scale) must be chosen carefully, typically the reduction dimension in matrix multiplication.
- **Weight Storage:** Due to non-commutativity, training may require storing quantized weights $W$ and their transpose $W^T$ as separate tensors if the principal dimensions differ between forward and backward passes.
- **Implicit Scaling:** As per OCP MX v1.0, INT8 has an implicit $2^{-6}$ scale in addition to the shared exponent.

---

## Summary of Design Ideas for Our Implementation
1. **Pipelined Comparator Trees:** If we implement hardware-side scale detection, use a pipelined binary tree of comparators.
2. **Binary Adder Trees:** For the accumulator, consider pairwise binary trees to improve timing/latency if throughput requirements increase.
3. **Enhanced Rounding:** Implement full RNE logic with guard/round/sticky bits for normalization if we extend `fp8_aligner` for more complex cross-block operations.
4. **Saturation vs. NaN:** Prioritize saturation for out-of-range finite numbers while maintaining the two-level NaN propagation strategy.
