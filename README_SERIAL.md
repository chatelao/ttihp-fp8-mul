![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg) [![Documentation Status](https://readthedocs.org/projects/ttihp-fp8-mul/badge/?version=latest)](https://ttihp-fp8-mul.readthedocs.io/en/latest/?badge=latest)

# Tiny Tapeout IHP 26a - OCP MXFP8 Bit-Serial Streaming MAC Unit

This project implements an ultra-minimal, bit-serial Streaming Multiply-Accumulate (MAC) Unit compatible with the OCP Microscaling Formats (MX) Specification (v1.0). It is inspired by the **SERV** bit-serial RISC-V core and designed to achieve the smallest possible footprint (< 500 gates) within a Tiny Tapeout tile.

## Philosophy: The SERV Approach

The fundamental principle of this bit-serial variant is that any N-bit operation can be decomposed into N 1-bit operations over N clock cycles.
- **Registers as Shift Registers**: Operands and the accumulator are stored in shift registers.
- **1-Bit Datapath**: All arithmetic (multiplication, alignment, accumulation) is performed using 1-bit logic.
- **Latency-Area Tradeoff**: By processing one bit at a time, we significantly reduce gate count and routing congestion at the cost of increased cycle count.

## Attributions

This project incorporates logic and concepts from several open-source resources:
- [SERV](https://github.com/olofk/serv) by Olof Kindgren (Bit-serial design philosophy).
- [fp8_mul](https://github.com/cchan/fp8_mul) by Clive Chan (Arithmetic logic).
- [Tiny Tapeout Verilog Template](https://github.com/TinyTapeout/ttihp-verilog-template) (Project structure).
- [OCP Microscaling Formats (MX) Specification v1.0](https://www.opencompute.org/documents/ocp-microscaling-formats-mx-v1-0-spec-final-pdf) (Numerical and Protocol Specification).

## Functional Block Overview

| Block | Component | Detailed Function & Mathematics |
| :--- | :--- | :--- |
| **FSM & Control** | Stretched FSM, Cycle Counter | Orchestrates the protocol using a **Stretched Protocol**. Each standard cycle is expanded into $K$ internal cycles (`SERIAL_K_FACTOR`). |
| **Bit-Serial Multiplier** | Serial-Parallel Mul | Performs mantissa multiplication bit-by-bit. For MXFP8, a 4-bit multiplication is distributed over multiple internal cycles. |
| **Serial Aligner Stage** | Delay-Line Aligner | Aligns products by delaying the bit-stream. The delay is proportional to the required shift, replacing area-intensive barrel shifters. |
| **Serial Accumulator** | 1-bit Adder, Circulating Register | Performs summation using a 1-bit full adder and a carry flip-flop. The 40-bit accumulator circulates in a shift register. |
| **Output Serializer** | Shift Register | Extracts results bit-by-bit or byte-by-byte for transmission over `uo_out`. |

## Protocol Description (Stretched)

To maintain compatibility with the 8-bit streaming interface while using bit-serial internals, the unit uses a **Stretched Protocol**. 1 element is processed every $K$ clock cycles.

### Operational Sequence (Example K=8)

| Phase | Standard Cycles | Stretched Cycles (K=8) | Description |
|-------|-----------------|------------------------|-------------|
| **Metadata** | 3 | 24 | Load Shared scales, format, and MX+ metadata. |
| **Stream** | 32 | 256 | 32 pairs of elements streamed ($A_i, B_i$). |
| **Summation** | 2 | 16 | Pipeline flush and final alignment. |
| **Output** | 4 | 32 | 32-bit result output (1 byte every $K$ cycles). |

## OCP MX Feature Support

Despite its minimal size, the bit-serial unit aims for full OCP MX compliance:
- **Multiple Element Formats**: MXFP8, MXFP6, MXFP4, and MXINT8.
- **Shared Scaling**: Hardware-accelerated scaling using the UE8M0 format.
- **Rounding Modes**: Support for TRN and RNE (serialized).
- **Overflow Methods**: SAT (Saturation) and WRAP.

## Compilation Options

| Parameter | Description |
|-----------|-------------|
| `SUPPORT_SERIAL` | **Set to 1** to enable the bit-serial implementation. |
| `SERIAL_K_FACTOR` | The bit-serial period (typically 8 for 8-bit formats). |
| `ALIGNER_WIDTH` | Bit-width of the internal alignment (e.g., 40 bits). |
| `ACCUMULATOR_WIDTH`| Bit-width of the circulating accumulator. |

## Resources

- [Bit-Serial Concept Document](docs/architecture/OCP_MX_SERIAL.md)
- [Project Roadmap](ROADMAP.md)
- [OCP MX Specification](https://www.opencompute.org/documents/ocp-microscaling-formats-mx-v1-0-spec-final-pdf)
- [Tiny Tapeout FAQ](https://tinytapeout.com/faq/)

## Target Metrics
- **Area Goal**: < 500 gates (excluding shift registers).
- **Tile Target**: 1x1 Tiny Tapeout tile.
- **Frequency**: Designed for high-frequency operation (100MHz+) to offset serial latency.
