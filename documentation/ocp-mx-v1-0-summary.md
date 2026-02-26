# OCP Microscaling Formats (MX) Specification v1.0 - Summary

## Overview
The OCP Microscaling Formats (MX) specification introduces a block-based scaling approach for numerical representations, primarily targeting AI training and inference. It aims to reduce memory bandwidth and hardware complexity by sharing a single scale factor across a block of elements.

## Key Components
An MX-compliant format is characterized by three components:
1.  **Scale ($X$):** A shared scaling factor for the entire block.
2.  **Private Elements ($P_i$):** Individual data elements within the block.
3.  **Scaling Block Size ($k$):** The number of elements sharing the same scale factor (standardized as $k=32$).

The value represented by an element $P_i$ with scale $X$ is generally $v_i = X \times P_i$.

---

## Requirement Levels

The specification defines the following requirement levels (Section 4.2):
*   **Must:** Indicates an action is absolutely required for compliance.
*   **Should:** Indicates an action is recommended but not required.
*   **May:** Indicates an action is optional.
*   **Can:** Used to describe possibilities or capabilities.

### **Must (Mandatory Features)**
*   **Compliance:** For each supported format, an implementation **must** support the parameters listed in the concrete formats table (e.g., block size 32, E8M0 scale).
*   **FP8 Adherence:** FP8 implementations **must** adhere to the OCP 8-bit Floating Point Specification.
*   **Overflow Handling:** Implementations **must** support the saturate (SAT) and overflow (OVF) methods for conversions to FP8.
*   **Rounding Mode:** Implementations **must** support the `roundTiesToEven` rounding mode for converting values to FP6, FP4, and INT8.
*   **Saturation:** During conversion to FP6/FP4/INT8, out-of-range values **must** be clamped (saturated) to the maximum representable magnitude, preserving the sign.
*   **Underflow to Zero:** If a value's magnitude is less than the minimum subnormal magnitude of FP6/FP4 after rounding, it **must** be converted to zero.
*   **Dot Product:** The dot product operation **must** minimally support the semantics: $C = X_A X_B \sum_{i=1}^{k} (P_{iA} \times P_{iB})$.
*   **Conversion Mechanism:** A mechanism **must** be provided for converting a $k$-length vector of scalar elements to an MX-compliant format.

### **Should (Recommended Features)**
*   **General Dot Product:** The result of a general dot product of two vectors **should** be a scalar Float32 number.
*   **Scale Selection:** During conversion, the scale $X$ **should** be set to the largest power-of-two $\le \max(|V_i|)$ divided by the largest power-of-two representable in the element type.
*   **Clamping:** Normal numbers exceeding the max normal representation **should** be clamped to the max normal during quantization.

### **May (Optional Features)**
*   **Implementation:** The standard **may** be realized entirely in software, hardware, or a combination.
*   **Format Support:** An implementation **may** choose to support any subset of the concrete MX formats.
*   **Additional Overflow Methods:** Other overflow methods beyond SAT/OVF **may** be supported via a configurable attribute.
*   **Additional Rounding Modes:** Rounding modes other than `roundTiesToEven` **may** be supported.
*   **INT8 Symmetry:** The maximum negative representation ($-128$ or $-2^7$) **may** be left unused in INT8 to maintain symmetry.
*   **Mixed Types:** Vectors A and B **may** use different data types for their scales or elements.

### **Can (Possibilities)**
*   **Compression:** If multiple blocks share the same scale, an implementation **can** compress or prune away repeated scale factors.
*   **Storage:** The scale factor $X$ **can** be stored contiguously with or separately from the elements.

---

## Concrete MX Formats
All concrete formats in v1.0 use a **Block Size ($k$) of 32** and an **E8M0 Scale (8 bits)**.

| Format Name | Element Type | Element Bits ($d$) | Scale Type | Scale Bits ($w$) |
| :--- | :--- | :---: | :--- | :---: |
| **MXFP8** | E5M2 or E4M3 | 8 | E8M0 | 8 |
| **MXFP6** | E3M2 or E2M3 | 6 | E8M0 | 8 |
| **MXFP4** | E2M1 | 4 | E8M0 | 8 |
| **MXINT8** | INT8 | 8 | E8M0 | 8 |

### Element Formats Detail
*   **FP8 (E4M3):** Bias 7, Max Normal 448.
*   **FP8 (E5M2):** Bias 15, Max Normal 57344. Includes Infinities and NaNs.
*   **FP6 (E3M2/E2M3):** No reserved encodings for Inf/NaN. Supports subnormals.
*   **FP4 (E2M1):** No reserved encodings for Inf/NaN. Supports subnormals.
*   **INT8:** 2's complement. Includes implicit scale of $2^{-6}$. Max symmetric value $\approx 1.98$.
*   **Scale (E8M0):** 8-bit unsigned biased exponent (Bias 127). Range: $2^{-127}$ to $2^{127}$. `11111111` is reserved for NaN.

---

## Numerical Semantics
*   **Subnormals:** Supported in all floating-point element types.
*   **NaN Handling:** If the shared scale $X$ is NaN, all values in the block are NaN.
*   **Special Values:** FP8 supports IEEE-style Inf/NaN (E5M2) or specialized NaN (E4M3). Smaller formats (FP6, FP4) do not reserve bits for Inf/NaN and instead rely on saturation.
