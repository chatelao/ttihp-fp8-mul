<!---
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The **OCP MXFP8 Streaming MAC Unit** is a high-performance, area-optimized arithmetic core designed for AI inference acceleration. It implements the **OpenCompute (OCP) Microscaling Formats (MX) Specification v1.0**, supporting a wide range of sub-8-bit floating-point and integer formats with hardware-accelerated shared scaling.

### Architectural Overview
The unit is configured in its "Full" edition (2x2 tiles), featuring:
- **Dual-Lane Multiplier**: Parallel processing of operands with support for Vector Packing (FP4).
- **40-bit Aligner & 32-bit Accumulator**: High-precision internal datapath to prevent overflow during long dot-product sequences.
- **Shared Scaling (UE8M0)**: Automatic application of 8-bit exponents ($2^{E-127}$) to element blocks.
- **Flexible Rounding**: Support for Truncate (TRN), Ceil (CEL), Floor (FLR), and Round-to-Nearest-Even (RNE).
- **Mixed Precision**: Independent format control for Operand A and Operand B within a single MAC block.

### Streaming Protocol
To maintain a minimal IO footprint (8-bit ports), the unit uses a **41-cycle streaming protocol** to process a block of 32 elements ($k=32$).

| Cycle | Input `ui_in[7:0]` | Input `uio_in[7:0]` | Output `uo_out[7:0]` | Description |
|-------|--------------------|---------------------|----------------------|-------------|
| 0     | **Metadata 0**     | **Metadata 1**      | 0x00                 | **IDLE**: Load MX+ / Debug or Start Fast Protocol. |
| 1     | **Scale A**        | **Format A / BM A** | 0x00                 | Load Scale A, Format A, and BM Index A. |
| 2     | **Scale B**        | **Format B / BM B** | 0x00                 | Load Scale B, Format B, and BM Index B. |
| 3-34  | **Element $A_i$**  | **Element $B_i$**   | 0x00                 | Stream 32 pairs of elements.* |
| 35-36 | -                  | -                   | 0x00                 | Pipeline flush & final scaling. |
| 37-40 | -                  | -                   | **Result [31:0]**    | Serialized 32-bit result (MSB first). |

*\*Note: In Packed Mode (`uio_in[6]=1` in Cycle 0), the STREAM phase is reduced to 16 cycles (Cycles 3-18).*

### Register Layouts

#### Cycle 0: UI_IN (Metadata 0)
![Metadata 0](https://svg.wavedrom.com/%7B%22reg%22%3A%20%5B%7B%22name%22%3A%20%22NBM%20Offset%20A%22%2C%20%22bits%22%3A%203%7D%2C%20%7B%22name%22%3A%20%22LNS%20Mode%22%2C%20%22bits%22%3A%202%7D%2C%20%7B%22name%22%3A%20%22Loopback%20En%22%2C%20%22bits%22%3A%201%7D%2C%20%7B%22name%22%3A%20%22Debug%20En%22%2C%20%22bits%22%3A%201%7D%2C%20%7B%22name%22%3A%20%22Short%20Protocol%22%2C%20%22bits%22%3A%201%7D%5D%2C%20%22config%22%3A%20%7B%22bits%22%3A%208%7D%7D)

- **Short Protocol (`[7]`)**: Reuse previous scales/formats; jump to Cycle 3.
- **LNS Mode (`[4:3]`)**: 0: Normal, 1: LNS, 2: Hybrid.

#### Cycle 0: UIO_IN (Metadata 1)
![Metadata 1](https://svg.wavedrom.com/%7B%20%22reg%22%3A%20%5B%20%7B%22name%22%3A%20%22NBM%20Offset%20B%22%2C%20%22bits%22%3A%203%7D%2C%20%7B%22name%22%3A%20%22Rounding%20Mode%22%2C%20%22bits%22%3A%202%7D%2C%20%7B%22name%22%3A%20%22Overflow%20Mode%22%2C%20%22bits%22%3A%201%7D%2C%20%7B%22name%22%3A%20%22Packed%20Mode%22%2C%20%22bits%22%3A%201%7D%2C%20%7B%22name%22%3A%20%22MX%2B%20Enable%22%2C%20%22bits%22%3A%201%7D%20%5D%2C%20%22config%22%3A%20%7B%22bits%22%3A%208%7D%7D)

- **Rounding Mode (`[4:3]`)**: 0: TRN, 1: CEL, 2: FLR, 3: RNE.
- **Packed Mode (`[6]`)**: Enable 2-elements-per-byte for FP4 formats.

#### Cycle 1: UIO_IN (Config A)
![Config A](https://svg.wavedrom.com/%7B%20%22reg%22%3A%20%5B%20%7B%22name%22%3A%20%22Format%20A%22%2C%20%22bits%22%3A%203%7D%2C%20%7B%22name%22%3A%20%22BM%20Index%20A%22%2C%20%22bits%22%3A%205%7D%20%5D%2C%20%22config%22%3A%20%7B%22bits%22%3A%208%7D%7D)

- **Format A (`[2:0]`)**: 0: E4M3, 1: E5M2, 2: E3M2, 3: E2M3, 4: E2M1, 5: INT8, 6: INT8_SYM.

## How to test

### Basic Verification
1.  **Reset**: Pulse `rst_n` low, then set `ena` high.
2.  **Configuration**:
    - Cycle 0: Provide `0x00` on both `ui_in` and `uio_in` for standard E4M3 mode.
    - Cycle 1: Provide `0x7F` (1.0 scale) on `ui_in` and `0x00` (E4M3) on `uio_in`.
    - Cycle 2: Provide `0x7F` (1.0 scale) on `ui_in` and `0x00` (E4M3) on `uio_in`.
3.  **Data Streaming**:
    - Cycles 3-34: Provide 32 pairs of values. E.g., `0x38` (1.0 in E4M3) on both ports.
4.  **Result**:
    - Cycles 35-36: Wait for internal processing.
    - Cycles 37-40: Read the 32-bit signed fixed-point result on `uo_out`.
    - For 32 pairs of $1.0 \times 1.0$, the result should be `0x00002000` (representing 32.0 in the system's 8-bit fractional format).

### Advanced Modes
- **Short Protocol**: Set `ui_in[7]=1` in Cycle 0 to bypass scale loading. Useful for weight-stationary kernels where scales and formats remain constant across blocks.
- **Vector Packing**: Set `uio_in[6]=1` in Cycle 0. Stream two 4-bit elements per byte (High nibble = Element $i+1$, Low nibble = Element $i$).

## External hardware

- **Tiny Tapeout DevKit**: The easiest way to interface with the chip. Use the provided MicroPython driver (`test/TT_MAC_RUN.PY`) for quick prototyping.
- **Sipeed Tang Nano 4K**: For high-speed testing, a dedicated FPGA bitstream and Cortex-M3 testbench are provided in the repository.

## IO

| Port | Name | Description |
|---|---|---|
| `ui_in[7:0]` | Operand A / Scale A | Elements $A_i$ or Scale $X_A$. |
| `uio_in[7:0]` | Operand B / Scale B | Elements $B_i$ or Scale $X_B$. |
| `uo_out[7:0]` | Result Out | Serialized 32-bit dot product result. |
| `clk` | Clock | System clock (Target: 20MHz). |
| `rst_n` | Reset | Active-low asynchronous reset. |
| `ena` | Enable | Clock enable. |

## Thank you!

A massive thank you to **Matt Venn**, **Uri Shaked**, **Sophie**, and the entire **Tiny Tapeout / Efabless** community for making open-source silicon a reality. This project was built on the foundation of your incredible tools and dedication.
