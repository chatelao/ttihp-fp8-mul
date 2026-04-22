# Flip-Flop Usage Analysis

This document provides a detailed breakdown of the Flip-Flop (FF) resources used in the OCP MXFP8 Streaming MAC Unit. The design is optimized for both ASIC (Tiny Tapeout) and FPGA (Tang Nano 4K) deployments.

## 1. Breakdown by Sub-module (Full Configuration)

The "Full" configuration utilizes approximately **416 FFs** to support the complete OCP MX feature set, including dual-lane processing, input buffering, and pipeline staging.

| Category | Component | Detail | FFs |
| :--- | :--- | :--- | :---: |
| **Control & FSM** | Cycle Counter | 6-bit counter for protocol timing | 6 |
| | Config Registers | Scales (16), Formats (6), Modes (5), MX+ (10), Debug (6), Misc (8) | 51 |
| **Datapath** | Input FIFOs | 16x8-bit buffers for Lane A and Lane B (Input Buffering) | 256 |
| | FIFO Pointers | Read/Write pointers for input buffers | 4 |
| | Packed Buffers | Temp storage for FP4 vector packing | 8 |
| | Pipeline Regs | 2x28-bit staging for Multiplier-to-Aligner path | 56 |
| | Accumulator | 32-bit signed fixed-point register | 32 |
| **Exceptions** | Sticky Regs | Latches for NaN, Inf+, Inf- flags | 3 |
| **Total** | | | **416** |

## 2. Usage Comparison Across Variants

The modular architecture allows significant reduction in FF usage for area-constrained tiles.

| Variant | Key Parameters | Total FFs (Est.) | TT Tile Size |
| :--- | :--- | :---: | :---: |
| **Full** | All features, 40-bit datapath, Input Buffers | 416 | 2x2 |
| **Lite** | Single-lane, No Input Buffers, No MX+ | 110 | 1x1 |
| **Tiny** | Minimal FP8, No Pipelining, No Buffers | 54 | 1x1 |
| **Ultra-Tiny** | Tiny config + 24-bit Accumulator | 46 | 1x1 |

## 3. FPGA Implementation Notes (Tang Nano 4K)

When synthesized for the Gowin GW1NSR-4C (Tang Nano 4K), the FF usage may vary due to tool optimizations and resource mapping:

- **FIFO Inference**: The 256-bit input FIFO may be inferred as Distributed RAM or Block RAM if the tool determines it is more efficient, reducing the DFF count in the logic fabric.
- **Clock Enables**: The `ena` signal is mapped to the hardware Clock Enable (CE) port of the DFFs, ensuring low-power operation when the unit is idle.
- **Synthesis Results**: Actual synthesis of the "Full" variant on Tang Nano 4K typically shows ~144-160 DFFs when the FIFO is optimized or mapped to RAM.

## 4. Power Considerations

Flip-Flops are the primary consumers of dynamic power in this design. To minimize energy consumption:
1. **Clock Gating**: The `ena` signal should be held low when no computation is required.
2. **Short Protocol**: Reusing scale factors via the Short Protocol reduces the number of register transitions in the configuration block.
3. **Variant Selection**: Choose the "Tiny" variant for applications where low leakage and minimal dynamic power are prioritized over throughput.
