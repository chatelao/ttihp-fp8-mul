# Flip-Flop Usage Analysis

This document provides a detailed breakdown of the Flip-Flop (FF) resources used in the OCP MXFP8 Streaming MAC Unit. The design is optimized for both ASIC (Tiny Tapeout) and FPGA (Tang Nano 4K) deployments.

## 1. Breakdown by Sub-module (Full Configuration)

The "Full" configuration utilizes approximately **416 FFs** to support the complete OCP MX feature set, including dual-lane processing, input buffering, and pipeline staging.

| Category | Component | Type | Essentiality | Purpose | FFs |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **Control & FSM** | Cycle Counter | DFFR | **Critical** | Tracks the 41-cycle OCP protocol phase (Idle, Scales, Stream, Output). | 6 |
| | Config Registers | DFFE | **Critical** | Stores block-level metadata: formats, scales, rounding modes, and MX+ offsets. | 51 |
| **Datapath** | Input FIFOs | DFFE | Performance | Buffers elements for high-throughput FP4/Packed modes; allows async streaming. | 256 |
| | FIFO Pointers | DFFR | Performance | Manages read/write access to the input buffers during streaming. | 4 |
| | Packed Buffers | DFFE | Feature-Specific | Temporary storage for bit-serial packed vector processing (FP4/FP6). | 8 |
| | Pipeline Regs | DFFR | Performance | Improves timing ($F_{max}$) by breaking long paths between Multiplier and Aligner. | 56 |
| | Accumulator | DFFR/E | **Critical** | Main register for summing products; also used as a shift register for output. | 32 |
| **Exceptions** | Sticky Regs | DFFR | Compliance | Latches block-level exceptions (NaN, Inf+, Inf-) for OCP/IEEE 754 reporting. | 3 |
| **Total** | | | | | **416** |

## 2. Functional Essentiality

To optimize the design for area-constrained tiles (e.g., 1x1 Tiny Tapeout tiles), the Flip-Flops are categorized by their impact on functionality:

### 2.1. Critical Registers (Essential)
These registers are required for the unit to function at all. Removing them would break the communication protocol or the basic MAC operation.
- **Cycle Counter**: Necessary to drive the FSM.
- **Config Registers**: Necessary to know how to interpret input data (formats/scales).
- **Accumulator**: The core storage for the computation result.

### 2.2. Performance & Throughput (Optional)
These registers can be removed to save area (approx. 316 FFs) at the cost of lower clock speed or reduced feature support.
- **Input FIFOs**: Can be bypassed if the external controller can guarantee perfectly timed data arrival.
- **Pipeline Registers**: Removing these reduces the $F_{max}$ as the combinatorial path from input to accumulator becomes significantly longer.

### 2.3. Compliance & Features (Context-Dependent)
- **Sticky Registers**: Required for OCP MX and IEEE 754 compliance. Can be removed for "Lite" versions where exception reporting is handled by software or ignored.
- **Packed Buffers**: Only required if `SUPPORT_VECTOR_PACKING` or `SUPPORT_PACKED_SERIAL` is enabled for sub-8-bit formats.

## 3. Usage Comparison Across Variants

The modular architecture allows significant reduction in FF usage for area-constrained tiles.

| Variant | Key Parameters | Total FFs (Est.) | TT Tile Size |
| :--- | :--- | :---: | :---: |
| **Full** | All features, 32-bit datapath, Input Buffers | 416 | 2x2 |
| **Lite** | Single-lane, No Input Buffers, No MX+ | 110 | 1x1 |
| **Tiny** | Minimal FP8, No Pipelining, No Buffers | 54 | 1x1 |
| **Ultra-Tiny** | Tiny config + 24-bit Accumulator | 46 | 1x1 |

## 4. FPGA Implementation Notes (Tang Nano 4K)

When synthesized for the Gowin GW1NSR-4C (Tang Nano 4K), the FF usage may vary due to tool optimizations and resource mapping:

- **FIFO Inference**: The 256-bit input FIFO may be inferred as Distributed RAM or Block RAM if the tool determines it is more efficient, reducing the DFF count in the logic fabric.
- **Clock Enables**: The `ena` signal is mapped to the hardware Clock Enable (CE) port of the DFFs, ensuring low-power operation when the unit is idle.
- **Synthesis Results**: Actual synthesis of the "Full" variant on Tang Nano 4K typically shows ~144-160 DFFs when the FIFO is optimized or mapped to RAM.

## 5. Power Considerations

Flip-Flops are the primary consumers of dynamic power in this design. To minimize energy consumption:
1. **Clock Gating**: The `ena` signal should be held low when no computation is required.
2. **Short Protocol**: Reusing scale factors via the Short Protocol reduces the number of register transitions in the configuration block.
3. **Variant Selection**: Choose the "Tiny" variant for applications where low leakage and minimal dynamic power are prioritized over throughput.
