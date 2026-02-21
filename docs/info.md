<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

    A small mux in front to fill up two 8-bit buffers in halves,
    which feed the actual 8-bit multiplier.

    When ctrl0 is 0, you can clock in 4 bits from data[3:0] into the upper or lower
    halves of two buffers according to the values of ctrl[1] and ctrl[2]:
    - 00 STORE 1 LOWER
    - 01 STORE 1 UPPER
    - 10 STORE 2 LOWER
    - 11 STORE 2 UPPER
    The clock is intended for manual use instead of actually being driven by a clock,
    but it probably can work.

    The 8 bits in each of the two buffers are interpreted as an 8-bit floating point number.
    From MSB to LSB:
    - sign bit
    - exponent[3:0]
    - mantissa[2:0]
    These are interpreted according to an approximation of IEEE 754, i.e.
      (-1)**sign * 2**(exponent - EXP_BIAS) * 1.mantissa
    with the following implementation details / differences:
    - EXP_BIAS = 7, analogous to 2**(exp-1) - 1 for all IEEE-defined formats
    - Denormals (i.e. exponent == 0) are flushed to zero on input and output
    - exponent = 0b1111 is interpreted as more normal numbers instead of NaN/inf,
        and overflows saturate to the largest representable number (0bx1111111 = +/- 480.0)
    - Negative zero is interpreted as NaN instead.
    - Round to nearest even is implemented.

    The output 8 bits will always display the results of the multiplication
    of the two FP8's in the buffers, regardless of the clock.

    The module has been verified over all possible pairs of 8-bit inputs.

## How to test

    cd src && make

## External hardware
none
