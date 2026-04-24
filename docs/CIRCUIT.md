# System Circuit Diagram

The **OCP MXFP8 Streaming MAC Unit** is implemented as a 32-element streaming Multiply-Accumulate unit. It processes 8-bit inputs (`ui_in` and `uio_in`) to compute a 32-bit dot product, which is then serialized to the 8-bit output (`uo_out`).

## Circuitikz Representation

The following diagram illustrates the top-level module interface and the primary internal functional blocks.

![System Circuit Diagram](circuit.svg)

## Architectural Components

1.  **FSM & Control Logic**: Orchestrates the 41-cycle protocol, captures metadata in Cycle 0, and manages scale loading in Cycles 1-2.
2.  **Dual Multiplier Lanes**: Parallel 8-bit multipliers supporting OCP MX formats (E4M3, E5M2, etc.) and Mitchell's LNS approximation.
3.  **Dual Aligner Stage**: Performs per-element scaling and aligns products to a common 40-bit fixed-point grid.
4.  **32-bit Accumulator & Serializer**: Sums 32 products and serializes the final result for transmission over the 8-bit output port.
