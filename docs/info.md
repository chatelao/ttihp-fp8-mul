<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

    The 8 bits in each of the two inputs are 8-bit floating point numbers (E4M3).
    
    From MSB to LSB:
    - sign bit
    - exponent[3:0]
    - mantissa[2:0]
    
    These are interpreted according to an approximation of IEEE 754
    
    The output 8 bits will always display the results of the multiplication
    of the two FP8's in the buffers, regardless of the clock.

    The module has been verified over all possible pairs of 8-bit inputs.
