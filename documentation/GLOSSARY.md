# Project Glossary

This document provides definitions for terms, acronyms, and concepts used throughout the OCP MX Streaming MAC Unit project.

## OCP MX Specification & Formats

- **OCP MX**: Open Compute Project Microscaling Formats, a specification for block-based scaling in deep learning.
- **MXFP8 / MXFP6 / MXFP4**: 8-bit, 6-bit, and 4-bit floating-point formats defined under the OCP MX specification.
- **MXINT8**: 8-bit integer formats (standard and symmetric) supported by OCP MX.
- **E4M3**: An 8-bit float format with 1 sign bit, 4 exponent bits (Bias 7), and 3 mantissa bits.
- **E5M2**: An 8-bit float format with 1 sign bit, 5 exponent bits (Bias 15), and 2 mantissa bits.
- **UE8M0**: An 8-bit unsigned biased exponent format (Bias 127) used for shared scaling factors.
- **Block Size (k)**: The number of elements that share a single scaling factor (fixed at 32 in this design).
- **Shared Scale**: A single scaling factor applied to a block of elements to reduce memory bandwidth.

## Numerical Logic & Arithmetic

- **BM (Block Max)**: The element with the largest magnitude in a block, whose exponent determines the shared scale.
- **NBM (Non-Block Max)**: Any element in a block that is not the Block Max.
- **MX+**: An extension to OCP MX that repurposes the exponent bits of the Block Max element for additional mantissa precision.
- **MX++**: A further extension allowing Non-Block Max elements to use a finer quantization grid via a shared exponent offset.
- **SEZ (Shared Exponent Zero)**: A flushing rule where the entire block is treated as zero if the shared scale is zero.
- **RNE (Round-to-Nearest-Ties-to-Even)**: A rounding mode that rounds to the nearest value, breaking ties by rounding to the nearest even number.
- **TRN (Truncate)**: A rounding mode that rounds towards zero.
- **CEL (Ceil)**: A rounding mode that rounds towards positive infinity.
- **FLR (Floor)**: A rounding mode that rounds towards negative infinity.
- **SAT (Saturation)**: An overflow handling method that clamps out-of-range values to the maximum or minimum representable values.
- **WRAP (Wrapping)**: An overflow handling method that uses modulo arithmetic (ignoring overflow bits).

## Protocol & Hardware Architecture

- **Streaming MAC**: A Multiply-Accumulate unit that processes elements sequentially over a timed protocol.
- **Fast Start (Scale Compression)**: A protocol optimization that allows the reuse of previously loaded scales and formats to increase throughput.
- **Vector Packing**: A potential optimization for 4-bit formats (like MXFP4) where two elements are packed into a single 8-bit input cycle to reduce the transmission phase.
- **Aligner**: Hardware logic that shifts the product of a multiplication to align its binary point with the accumulator.
- **Accumulator**: A high-precision register (32-bit in this design) that stores the running sum of products.
- **FSM (Finite State Machine)**: The control logic that manages the 41-cycle operational sequence.

## Tooling & Technology

- **Tiny Tapeout**: An educational project that facilitates low-cost ASIC manufacturing.
- **IHP SG13G2**: A 130nm BiCMOS Open Source Process Design Kit (PDK) from IHP Microelectronics.
- **PDK (Process Design Kit)**: A set of files used to describe a semiconductor process for EDA tools.
- **GDS (Graphic Data System)**: The standard file format for exchanging integrated circuit layout data.
- **Cocotb**: A coroutine-based cosimulation framework for writing VHDL and Verilog testbenches in Python.
- **Icarus Verilog**: An open-source Verilog simulation and synthesis tool.
- **Yosys**: An open-source framework for Verilog RTL synthesis.

## RISC-V Integration

- **ZvfofpXmin**: A proposed RISC-V extension name for minimal vector floating-point support.
- **vmxfmt**: A custom CSR (Control and Status Register) proposed to configure OCP MX formats.
- **vxsat**: The standard RISC-V Vector Fixed-Point Saturation Flag.
- **frm**: The standard RISC-V Floating-point Rounding Mode field.
