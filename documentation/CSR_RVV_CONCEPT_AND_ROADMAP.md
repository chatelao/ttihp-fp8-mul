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

---

## 6. SERV CPU Integration Concept

### 6.1. Architectural Challenge: The Bit-Serial Impedance Mismatch
SERV is a bit-serial RISC-V CPU, meaning it processes 1 bit per cycle and takes 32 cycles for a standard 32-bit operation. The OCP MX Bridge, however, expects a byte-serial stream (8 bits per cycle) to drive the MAC unit's 41-cycle protocol. Integrating these two requires a transformation between bit-serial dataflow and the bridge's byte-oriented FSM.

### 6.2. Evaluated Integration Variants

| Variant | Description | Pros | Cons |
|:---|:---|:---|:---|
| **6.2.1: Wishbone-Attached Peripheral** | The Bridge/MAC unit is treated as a memory-mapped peripheral on the Wishbone bus. | Minimal CPU modification; standard software access. | High overhead (latency for bus arbitration); difficult to fit in 1x1 tile due to bus logic. |
| **6.2.2: Extension-Interface (MDU-style)** | Leverages SERV's extension interface. The bridge captures instructions and serial data directly from the CPU's internal shift registers. | High efficiency; bypasses the bus; low gate count. | Requires modification of the CPU core to support the custom OCP opcode. |
| **6.2.3: Shadow Shift-Register Bridge** | A separate 32-bit shift register snoops the CPU's write-back data. Once "full" (after 32 cycles), it parallelizes the byte for the MAC bridge. | No timing impact on CPU; asynchronous processing. | Duplicate registers (32-bit buffer) increase area, threatening the 1x1 tile limit. |

### 6.3. Evaluation & Selection

**Selection**: **Variant 6.2.2 (Extension-Interface)** is selected for the minimal implementation.

**Justification**:
- **Area Efficiency**: By hooking into the existing bit-serial datapath (similar to how the MDU/Multiplier unit is integrated), we avoid 32-bit parallel buffers. We can accumulate bits into an 8-bit shift-register (part of the Bridge) every 8 CPU cycles.
- **Protocol Alignment**: Since SERV takes 32 cycles to "produce" a 32-bit register value, and the MAC unit expects 32 elements, the timing is naturally aligned for a low-gate-count implementation.
- **1x1 Tile Target**: This variant minimizes "dead" silicon used for bus interconnects or large buffers, maximizing the area available for the MAC arithmetic logic.

### 6.4. Dataflow for Minimal SERV Integration
1. CPU executes `vdot.mx` (custom opcode).
2. CPU shifts out `rs1` and `rs2` bit-by-bit over 32 cycles.
3. Bridge collects bits into 8-bit chunks.
4. Every 8 cycles, the Bridge feeds one element to the MAC unit.
5. MAC Unit runs in parallel (pipelined) or stalls the CPU if protocol cycles > 32.
