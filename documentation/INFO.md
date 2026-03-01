<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The project implements a **Streaming MXFP8 Multiply-Accumulate (MAC) Unit** based on the OCP Microscaling Formats (MX) Specification. It processes blocks of 32 elements using a shared 8-bit scale factor (UE8M0).

### Numerical Representation
The unit supports multiple element formats (depending on build configuration). The default **Ultra-Tiny** build supports:
- **E4M3**: 1-bit sign, 4-bit exponent (Bias 7), 3-bit mantissa.
- **MXINT8**: 8-bit signed integers (Standard and Symmetric).

### Operational Protocol (40-Cycle Sequence)
To minimize resource usage, operands are streamed into the unit over 40 clock cycles (0-39):
1. **Cycle 1**: Load Scale A ($X_A$ on `ui_in`) and Configuration (on `uio_in`).
2. **Cycle 2**: Load Scale B ($X_B$ on `ui_in`) and Format B (on `uio_in`).
3. **Cycles 3-34**: Stream 32 pairs of elements $A_i$ and $B_i$.
4. **Cycle 35**: Pipeline flush cycle.
5. **Cycles 36-39**: The 32-bit accumulator result is shifted out 8 bits at a time on `uo_out`.

## How to test

The design uses a clocked FSM. To test:
1. Reset the unit (`rst_n` = 0) then enable it (`ena` = 1).
2. On Cycle 1, provide Scale A on `ui_in`.
3. On Cycle 2, provide Scale B on `ui_in` and Format B on `uio_in`.
4. From Cycle 3 to 34, provide elements $A_i$ on `ui_in` and $B_i$ on `uio_in` at each clock edge.
5. Cycle 35 is used for internal pipeline synchronization.
6. From Cycle 36 to 39, read the 32-bit result from `uo_out` (Byte 3 to Byte 0).

A Cocotb testbench in `test/test.py` performs this protocol and verifies the results.
