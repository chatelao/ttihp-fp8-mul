<!---
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.
-->

## How it works

The project implements a **Streaming MXFP8 Multiply-Accumulate (MAC) Unit** based on the OCP Microscaling Formats (MX) Specification. It processes blocks of 32 elements using shared 8-bit scale factors (UE8M0).

### Numerical Representation
The unit supports multiple element formats:
- **MXFP8**: E4M3 (Bias 7) and E5M2 (Bias 15).
- **MXFP6**: E3M2 (Bias 3) and E2M3 (Bias 1).
- **MXFP4**: E2M1 (Bias 1).
- **MXINT8**: Standard and Symmetric 8-bit signed integers.

### Operational Protocol (41-Cycle Sequence)
Operands are streamed into the unit over 41 clock cycles (0-40):
1. **Cycle 0**: IDLE. Start of operation or Fast Start (Scale Compression) trigger.
2. **Cycle 1**: Load Scale A and Configuration (Format A, Rounding Mode, Overflow Mode).
3. **Cycle 2**: Load Scale B and Format B.
4. **Cycles 3-34**: Stream 32 pairs of elements $A_i$ and $B_i$.
5. **Cycle 35**: Pipeline flush cycle.
6. **Cycle 36**: Final Shared Scaling calculation.
7. **Cycles 37-40**: The 32-bit result is shifted out 8 bits at a time on `uo_out` (MSB first).

### Fast Start (Scale Compression)
By setting `ui_in[7]` high during Cycle 0, the unit reuses the previously loaded scales and formats, jumping directly to the streaming phase (Cycle 3).

## How to test

The design uses a clocked FSM. To test:
1. Reset the unit (`rst_n` = 0) then enable it (`ena` = 1).
2. On Cycle 1, provide Scale A on `ui_in` and Config on `uio_in`.
3. On Cycle 2, provide Format B on `ui_in` and Scale B on `uio_in`.
4. From Cycle 3 to 34, provide elements $A_i$ on `ui_in` and $B_i$ on `uio_in` at each clock edge.
5. Cycle 35 is for pipeline flush.
6. Cycle 36 is for shared scale alignment.
7. From Cycle 37 to 40, read the 32-bit result from `uo_out` (MSB to LSB).

A Cocotb testbench in `test/test.py` performs this protocol and verifies the results across all supported formats and rounding modes.
