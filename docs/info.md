<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The project implements a **Streaming MXFP8 Multiply-Accumulate (MAC) Unit** based on the OCP Microscaling Formats (MX) Specification. It processes blocks of 32 elements using a shared 8-bit scale factor (UE8M0).

### Numerical Representation
The unit supports both **E4M3** and **E5M2** element formats:
- **E4M3**: 1-bit sign, 4-bit exponent (Bias 7), 3-bit mantissa.
- **E5M2**: 1-bit sign, 5-bit exponent (Bias 15), 2-bit mantissa.

### Operational Protocol (38-Cycle Sequence)
To minimize resource usage, operands are streamed into the unit over 38 clock cycles:
1. **Cycles 1-2**: Load shared scales $X_A$ (on `ui_in`) and $X_B$ (on `uio_in`).
2. **Cycles 3-34**: Stream 32 pairs of elements $A_i$ and $B_i$.
3. **Cycles 35-38**: The 32-bit accumulator result is shifted out 8 bits at a time on `uo_out`.

## How to test

The design uses a clocked FSM. To test:
1. Reset the unit (`rst_n` = 0) then enable it (`ena` = 1).
2. On Cycle 1, provide Scale A on `ui_in`.
3. On Cycle 2, provide Scale B on `uio_in`.
4. From Cycle 3 to 34, provide elements $A_i$ on `ui_in` and $B_i$ on `uio_in` at each clock edge.
5. From Cycle 35 to 38, read the 32-bit result from `uo_out` (Byte 3 to Byte 0).

A Cocotb testbench in `test/test.py` performs this protocol and verifies the results.
