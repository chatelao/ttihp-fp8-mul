# OCP MX Floating Point Formats Summary

This page provides a summary of the numerical formats supported by the **OCP MXFP8 Streaming MAC Unit**, based on the OpenCompute (OCP) specifications.

## Core Specifications

Our implementation adheres to two primary OCP specifications:

1.  **[OCP 8-bit Floating Point Specification (OFP8) v1.0](OCP-OFP8-V1-0-SUMMARY.md)**: Defines the base E4M3 and E5M2 interchange formats and their conversion behaviors.
2.  **[OCP Microscaling Formats (MX) Specification v1.0](OCP-MX-V1-0-SUMMARY.md)**: Defines the block-based scaling approach (MXFP8, MXFP6, MXFP4) and the shared 8-bit scale factor (E8M0).

## Supported Element Formats

The following table summarizes the data formats for individual data elements ($P_i$) within a block. All formats share a common 8-bit scale factor ($X$).

| Format Name | Type | Bits | Sign | Exponent | Mantissa | Bias | Special Values | Detailed Table |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- | :--- |
| **E4M3** | MXFP8 | 8 | [7] | [6:3] | [2:0] | 7 | NaN (0x7F/0xFF) | [View Table](LOOKUP_TABLES.md#fp8-e4m3-table) |
| **E5M2** | MXFP8 | 8 | [7] | [6:2] | [1:0] | 15 | Inf, NaN | [View Table](LOOKUP_TABLES.md#fp8-e5m2-table) |
| **E3M2** | MXFP6 | 6 | [5] | [4:2] | [1:0] | 3 | Saturation | [View Table](LOOKUP_TABLES.md#fp6-e3m2-table) |
| **E2M3** | MXFP6 | 6 | [5] | [4:3] | [2:0] | 1 | Saturation | [View Table](LOOKUP_TABLES.md#fp6-e2m3-table) |
| **E2M1** | MXFP4 | 4 | [3] | [2:1] | [0] | 1 | Saturation | [View Table](LOOKUP_TABLES.md#fp4-e2m1-table) |
| **INT8** | MXINT8 | 8 | [7] | N/A | [6:0] | N/A | Two's Comp | N/A |
| **INT8_SYM**| MXINT8 | 8 | [7] | N/A | [6:0] | N/A | Symmetric | N/A |

### Numerical Semantics
- **FP Formats**: $V_i = (-1)^{S_i} \times 2^{E_i - \text{Bias}} \times (1 + M_i) \times 2^{X-127}$
- **INT Formats**: $V_i = (\text{Integer}_i \times 2^{-6}) \times 2^{X-127}$
- **Subnormals**: Supported across all floating-point formats when the exponent field is zero ($E_i = 0$).

---

## Shared Scale Format

The scale factor ($X$) is shared across a block of $k=32$ elements.

| Format Name | Type | Bits | Description | Bias | Range | Detailed Table |
| :--- | :--- | :---: | :--- | :---: | :--- | :--- |
| **UE8M0** | Scale | 8 | Unsigned Biased Exponent | 127 | $2^{-127}$ to $2^{127}$ | [View Table](LOOKUP_TABLES.md#shared-scale-ue8m0-table) |

---

## OCP MX+ Architectural Extensions

Our implementation includes several extensions to the base OCP MX specification to improve accuracy:

1.  **MX+ (Extended Mantissa)**: Identifies a "Block Max" element and repurposes its exponent bits as additional mantissa.
2.  **MX++ (Decoupled Shared Scaling)**: Applies an additional exponent offset to non-Block Max elements to reduce quantization noise.
3.  **Mitchell's Approximation (LNS Mode)**: An area-optimized multiplication mode using logarithmic approximation.

For more details on these extensions, see the [Architecture Documentation](../info.md#appendix-ocp-mx-mathematics) and the [MX+ Concept Paper](../architecture/MX_PLUS.md).
