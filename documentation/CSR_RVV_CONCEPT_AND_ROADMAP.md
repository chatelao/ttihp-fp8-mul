# CSR Mapping Concept & Implementation Roadmap: OCP MX for RISC-V

This document defines the conceptual mapping of the **OCP MX Streaming MAC Unit** to **RISC-V Control and Status Registers (CSRs)** and outlines the roadmap for full **ZvfofpXmin** integration.

## 1. Proposed CSR Layout

To manage the specific requirements of OCP Microscaling Formats (MX), a new custom CSR is proposed: `vmxfmt` (**Vector MX Format Configuration**).

### 1.1. `vmxfmt` (Custom Read/Write CSR, Address 0x800)

| Bits | Name | Description | OCP MX Cycle 1 Mapping |
|:---|:---|:---|:---|
| [2:0] | **FMT_A** | Element Format for Tensor A. | `uio_in[2:0]` |
| [5:3] | **FMT_B** | Element Format for Tensor B. | `uio_in[2:0]` (Cycle 2) |
| [6] | **OVF** | Overflow Mode (0: Saturation, 1: Wrap). | `uio_in[5]` |
| [7] | **EXT** | Extended Accuracy (MX+) Enable. | N/A |
| [31:8] | **RES** | Reserved for future use (e.g., MX++). | - |

#### Format IDs (FMT_A / FMT_B)
| ID | Format | Type |
|:---|:---|:---|
| `000` | E4M3 | MXFP8 |
| `001` | E5M2 | MXFP8 |
| `010` | E3M2 | MXFP6 |
| `011` | E2M3 | MXFP6 |
| `100` | E2M1 | MXFP4 |
| `101` | INT8 | MXINT8 |
| `110` | INT8_SYM | MXINT8 |

---

## 2. Integration with Standard RISC-V CSRs

### 2.1. Rounding Mode (`frm`)
Mapped to the standard RISC-V **`frm`** field in the **`fcsr`**.

| `frm` | OCP MX Rounding Mode | Description |
|:---|:---|:---|
| `000` | **RNE** (11) | Round to Nearest, ties to Even. |
| `001` | **TRN** (00) | Round towards Zero (Truncate). |
| `010` | **FLR** (10) | Round down (towards -Infinity). |
| `011` | **CEL** (01) | Round up (towards +Infinity). |

### 2.2. Saturation Flag (`vxsat`)
Sticky bit set if any element in the 32-element block triggers saturation.

---

## 3. Operational Flow in a RISC-V System

1. **Configuration**: `csrrw x0, vmxfmt, t0` (Set formats/overflow).
2. **Instruction**: Issue `vdot.mx v1, v2, v3` (Custom-0 Opcode).
3. **Execution**: The RVV-to-MX Bridge fetches operands from VRF and drives the 41-cycle MAC sequence.
4. **Result**: 32-bit result is written to destination VRF; `vxsat` updated.

---

## 4. RVV to MX Bridge Module

The "RVV to MX Bridge" acts as the hardware shim between the RISC-V Vector Register File (VRF) and the 41-cycle streaming protocol of the OCP MX MAC unit.

### 4.1. Functional Responsibilities
- **Operand Fetch**: Translates vector register addresses into a sequential stream of 8-bit elements.
- **Protocol Synchronization**: Drives the `ui_in` and `uio_in` pins of the MAC unit based on the internal FSM state.
- **Result Back-Pressure**: Buffers the 32-bit accumulated result and triggers the VRF write-back sequence.

### 4.2. Interface Diagram (Conceptual)
```
[ RISC-V VXU ] <--> [ CSRs (vmxfmt, vxsat) ]
      |
      v
[ RVV-to-MX Bridge ]
      | (8-bit Stream)
      v
[ OCP MX MAC Unit ] (41-cycle FSM)
```

---

## 5. Implementation Roadmap

### 5.1. Overall Strategy (Gesamtplan)

| Variant | Description | Pros | Cons |
|:---|:---|:---|:---|
| **A: Phased Modular Integration** | Incremental build-up: 1. CSR logic, 2. Bridge logic, 3. ISA decoding. | High testability; stable milestones. | Slightly slower initial "visible" progress. |
| **B: Vertical Feature Slicing** | Full path for one format (e.g., E4M3) first, then expand to others. | Faster end-to-end demo. | Higher risk of major rework when adding complex formats (MX+). |
| **C: Simulation-First Wrapper** | Develop a Cocotb/SystemC wrapper that emulates the VRF before RTL. | Early software toolchain testing. | Risk of mismatch between emulated and real hardware timing. |

**Selection & Justification**: **Variant A** is chosen. In an ASIC context (Tiny Tapeout), modular verification is paramount. Establishing the CSR foundation first ensures that the configuration logic is robust before dealing with complex streaming timing.

### 5.2. Sub-step 1: CSR Implementation

| Variant | Description | Justification |
|:---|:---|:---|
| **1.1: Centralized CSR Unit** | A dedicated module handles all custom CSR addresses (0x800+). | **Selected**: Best separation of concerns. Makes the ISA extension modular and reusable across different MAC implementations. |
| **1.2: Distributed Shadow Regs** | Latch configuration directly in the MAC's FSM, mapped to the bus. | Saves a few gates but makes timing analysis harder as configuration logic is interleaved with arithmetic logic. |
| **1.3: Bus-Mapped Config Window** | Use a single "data" CSR and an "address" CSR to access internal state. | High latency for configuration; complex software driver required. |

### 5.3. Sub-step 2: VRF-to-Stream Bridge

| Variant | Description | Justification |
|:---|:---|:---|
| **2.1: Asynchronous FIFO Buffer** | Use a small 8-entry FIFO to decouple VRF read-latency from MAC timing. | **Selected**: Provides immunity against pipeline stalls or memory wait-states. Essential for a reliable 41-cycle streaming guarantee. |
| **2.2: Tightly-Coupled Lane** | MAC FSM stalls the entire CPU pipeline until the 32 elements are read. | Simple hardware but devastating for system performance (32+ cycles of blocking). |
| **2.3: DMA-Style Transfer** | Software configures a DMA to move data from memory to the MAC unit. | Avoids VRF pressure but requires complex interrupt handling and memory management logic. |

### 5.4. Sub-step 3: ISA Integration & Decoding

| Variant | Description | Justification |
|:---|:---|:---|
| **3.1: Dedicated OCP Opcode** | Define a new `vdot.mx` instruction in the custom-0/1 opcode space. | **Selected**: Cleanest ISA integration. Enables compiler optimizations and follows the standard RISC-V extension path. |
| **3.2: CSR-Triggered Execution** | Writing to a specific control bit in `vmxfmt` starts the operation. | Non-standard; hard to pipeline in a superscalar or out-of-order core. |
| **3.3: ALU Re-purposing** | Reuse `vdot.vv` with a specific state bit in `vtype`. | Causes confusion with standard floating-point operations; breaks IEEE-754 compatibility expectations. |
