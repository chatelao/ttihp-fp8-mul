<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The project implements a purely combinational 8-bit floating point multiplier following the E4M3 (1 sign, 4 exponent, 3 mantissa) format.

### FP8 (E4M3) Format Details:
- **Sign bit (bit 7):** Indicates the sign of the number.
- **Exponent (bits 6:3):** 4-bit exponent with a bias of 7.
- **Mantissa (bits 2:0):** 3-bit mantissa with an implicit leading bit (1.xxx) for normal numbers.

The value is calculated as:
`(-1)^sign * 2^(exponent - 7) * 1.mantissa`

### Implementation Details:
- **Combinational Design:** The multiplier is purely combinational, providing results with minimal latency.
- **NaN Handling:** Follows a standard-like definition where Exponent = 15 and Mantissa != 0 is NaN.
- **Overflow:** Multiplications resulting in values larger than the maximum representable range saturate to the maximum value or NaN.
- **Underflow:** Results smaller than the representable range are flushed to zero.
- **Rounding:** Implements Round-to-Nearest-Even (RTNE) rounding logic.
- **Inputs:** Operand 1 is provided on `ui_in[7:0]`, Operand 2 on `uio_in[7:0]`.
- **Output:** The 8-bit result is output on `uo_out[7:0]`.

## How to test

To run the functional RTL simulation:
```bash
cd test
make
```

For more details on local environment setup and prerequisites, refer to [COMPLIE.md](../COMPLIE.md).

## External hardware
None.
