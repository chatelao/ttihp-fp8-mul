# OCP 8-bit Floating Point Specification (OFP8) - Summary

**Revision 1.0 (June 20, 2023)**

## Overview
This specification defines two binary interchange formats for 8-bit floating point (FP8) encodings: **E4M3** and **E5M2**. It also specifies conversion behaviors from wider formats (IEEE binary32, binary16, and bfloat16).

## OFP8 Binary Interchange Formats
The formats consist of a sign bit, a biased exponent, and mantissa (trailing significand) bits.

| Format | Sign | Exponent Bits | Mantissa Bits | Bias |
| :--- | :---: | :---: | :---: | :---: |
| **E4M3** | 1 | 4 | 3 | 7 |
| **E5M2** | 1 | 5 | 2 | 15 |

### Numerical Representation
- **Normal Number:** $v = (-1)^S \times 2^{E-\text{bias}} \times (1 + 2^{-m} \times M)$
- **Subnormal Number:** $v = (-1)^S \times 2^{1-\text{bias}} \times (0 + 2^{-m} \times M)$ (where $E = 0, M > 0$)

---

## Exponent Parameters and Value Encodings

### Exponent Parameters
| Parameter | E4M3 | E5M2 |
| :--- | :---: | :---: |
| Exponent Bias | 7 | 15 |
| $e_{max}$ (unbiased) | 8 | 15 |
| $e_{min}$ (unbiased) | -6 | -14 |

### Value Encoding Details
| Feature | E4M3 Encoding | E5M2 Encoding |
| :--- | :--- | :--- |
| **Infinities** | N/A | $S.11111.00_2$ |
| **NaN** | $S.1111.111_2$ | $S.11111.\{01, 10, 11\}_2$ |
| **Zeros** | $S.0000.000_2$ | $S.00000.00_2$ |
| **Max Normal** | $\pm 448$ | $\pm 57,344$ |
| **Min Normal** | $\pm 2^{-6}$ | $\pm 2^{-14}$ |
| **Max Subnormal** | $\pm 0.875 \times 2^{-6}$ | $\pm 0.75 \times 2^{-14}$ |
| **Min Subnormal** | $\pm 2^{-9}$ | $\pm 2^{-16}$ |
| **Dynamic Range** | 18 binades | 32 binades |

---

## Conversion Behavior
Conversion from wider formats (FP32, FP16, bfloat16) to OFP8 requires specific handling of saturation and rounding.

### Requirements
*   **Rounding:** `roundTiesToEven` MUST be implemented.
*   **Saturation:** Both saturating (SAT) and non-saturating (NONSAT) modes MUST be implemented.

### Summary of Conversion Cases
| Source Value (after rounding) | E5M2 (SAT) | E5M2 (NONSAT) | E4M3 (SAT) | E4M3 (NONSAT) |
| :--- | :--- | :--- | :--- | :--- |
| **NaN** | NaN | NaN | NaN | NaN |
| **$\pm$Inf** | $\pm max\_E5M2$ | $\pm$Inf | $\pm max\_E4M3$ | NaN |
| **Greater than max OFP8** | $\pm max\_E5M2$ | $\pm$Inf | $\pm max\_E4M3$ | NaN |
| **In OFP8 range** | Rounded | Rounded | Rounded | Rounded |
| **Smaller than min subnormal** | $\pm 0$ | $\pm 0$ | $\pm 0$ | $\pm 0$ |
| **Zero** | $\pm 0$ | $\pm 0$ | $\pm 0$ | $\pm 0$ |

---

## Scope and Limitations
*   Scaling factor selection and maintenance are **not** in scope for OFP8 (these are handled by the OCP MX specification).
*   Arithmetic operations on OFP8 are **not** defined in this specification.
*   The E4M3 format sacrifices infinity support to gain an extra binade of dynamic range.
