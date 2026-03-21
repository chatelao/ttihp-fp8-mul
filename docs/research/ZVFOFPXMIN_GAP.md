# Gap Analysis: OCP MX Streaming MAC vs. ZvfofpXmin

This document analyzes the architectural and functional gaps between the current **OCP MX Streaming MAC Unit** (implemented for Tiny Tapeout) and the proposed **RISC-V ZvfofpXmin** (Minimal Vector OCP Floating-Point) extension.

## 1. Overview of Entities

### OCP MX Streaming MAC Unit (Current Implementation)
- **Nature**: A standalone hardware peripheral/accelerator designed for Tiny Tapeout.
- **Interface**: Pin-based (8-bit inputs/outputs) using a strictly timed 41-cycle protocol.
- **Scaling**: Hardware-accelerated block scaling ($k=32$) with explicit scale loading phases.
- **Integration**: Requires external controller (e.g., RP2040, FPGA) to drive pins manually.

### RISC-V ZvfofpXmin (Target Specification)
- **Nature**: A RISC-V ISA Extension (Vector-based).
- **Interface**: Instruction Set Architecture (ISA) integrated; operates on Vector Registers (`v0`-`v31`).
- **Scaling**: Integrated into the vector processing pipeline; scaling managed via Vector Control and Status Registers (CSRs) or specific vector instructions.
- **Integration**: Native execution within a RISC-V Vector-enabled CPU core.

## 2. Key Architectural Gaps

| Feature | Streaming MAC Unit | ZvfofpXmin (Vector Extension) | Gap Description |
|:---|:---|:---|:---|
| **Instruction Control** | None (FSM-driven) | Opcode-driven (`vdot.vv`) | The current unit lacks an instruction decoder. Integration into RISC-V requires mapping the FSM to a vector execution unit. |
| **Data Locality** | Streamed from I/O pins | Vector Register File (VRF) | The current unit has no local storage for tensors. ZvfofpXmin requires a VRF and Load/Store Unit (LSU). |
| **Parallelism** | Temporal (Sequential) | Spatial/SIMD | The current unit processes 1 element/cycle. ZvfofpXmin typically implies parallel lanes (VLEN) for higher throughput. |
| **State Management** | Internal FSM state | CSRs (`vtype`, `vl`, `vstart`) | Scaling factors and formats in the current unit are "latched" in registers; ZvfofpXmin uses standard RISC-V CSR mechanisms. |

## 3. Numerical & Protocol Gaps

### 3.1. Block Scaling Management
- **Streaming MAC**: Explicitly loads Scale A (Cycle 1) and Scale B (Cycle 2). It supports "Fast Start" to reuse scales.
- **ZvfofpXmin**: OCP MX scales are likely handled as metadata associated with vector registers or stored in specific scale-vector registers. A significant gap exists in how the ISA handles the "shared" nature of the scale across a vector block.

### 3.2. Subnormal Handling
- **Streaming MAC**: Fully supports subnormal elements (denormals) across all floating-point formats, ensuring high numerical accuracy for small values.
- **ZvfofpXmin**: Even a "Minimal" (Xmin) extension might require configurable subnormal support or specific IEEE-754 exception flags (`fflags`) which are currently omitted.

### 3.3. Accumulator Precision
- **Streaming MAC**: Uses a 32-bit signed fixed-point accumulator.
- **ZvfofpXmin**: Typically requires the vector destination register to match the SEW (Selected Element Width) or use widening operations (`vwdot.vv`) to preserve precision.

## 4. Hardware Resource Gap

| Metric | Streaming MAC (Full) | ZvfofpXmin (Estimated) | Delta |
|:---|:---|:---|:---|
| **Gate Count** | ~3400 Gates | ~15,000+ Gates | ZvfofpXmin requires VRF, LSU, and ISA decoding logic. |
| **Area** | 1x2 TT Tile | Multiple Tiles | ISA integration significantly exceeds the footprint of a standalone MAC. |

## 5. Summary of Necessary Changes for Alignment
To bridge the gap between this implementation and a true **ZvfofpXmin** compliance:
1. **Wrappers**: Implement a RISC-V Vector execution unit wrapper that translates vector register reads into the 41-cycle streaming sequence.
2. **CSR Integration**: Map the `format` and `rounding_mode` registers to RISC-V CSRs.
3. **Interrupts/Exceptions**: Add support for standard RISC-V floating-point status flags (NV, DZ, OF, UF, NX).
4. **Memory Interface**: Replace the pin-based elements with an internal bus interface (e.g., AXI-Stream or TileLink).
