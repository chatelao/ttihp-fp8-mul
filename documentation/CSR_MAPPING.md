# CSR Mapping Concept: OCP MX Streaming MAC for RISC-V

This document defines the conceptual mapping of the **OCP MX Streaming MAC Unit** configuration and status to **RISC-V Control and Status Registers (CSRs)**. This mapping is intended to bridge the gap between the standalone 41-cycle streaming hardware and a integrated RISC-V Vector Execution Unit (aligned with the **ZvfofpXmin** extension).

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

The design leverages existing RISC-V CSRs where possible to maintain ISA consistency.

### 2.1. Rounding Mode (`frm`)
The OCP MX Rounding Mode is mapped to the standard RISC-V **`frm`** (Floating-point Rounding Mode) field in the **`fcsr`** (or bits [14:12] of `mstatus`/`sstatus`).

| `frm` | OCP MX Rounding Mode | Description |
|:---|:---|:---|
| `000` | **RNE** (11) | Round to Nearest, ties to Even. |
| `001` | **TRN** (00) | Round towards Zero (Truncate). |
| `010` | **FLR** (10) | Round down (towards -Infinity). |
| `011` | **CEL** (01) | Round up (towards +Infinity). |

*Note: OCP MX internal IDs (00-11) are remapped to match RISC-V standard `frm` encodings during hardware integration.*

### 2.2. Saturation Flag (`vxsat`)
The OCP MX unit's internal saturation detection (which triggers during Aligner or Accumulator clamping) is mapped to the standard RISC-V **`vxsat`** (Vector Fixed-Point Saturation Flag).

- If any element in the 32-element block triggers saturation, the `vxsat` bit is set to 1.
- This bit is "sticky" and must be cleared manually by software, consistent with the RISC-V Vector Spec.

---

## 3. Operational Flow in a RISC-V System

In an integrated environment, the 41-cycle FSM is abstracted by the instruction decoder.

1. **Configuration**: Software sets the formats and rounding via `csrrw x0, vmxfmt, t0` and `fsrm t1`.
2. **Instruction**: A vector dot-product instruction (e.g., `vdot.vv v1, v2, v3`) is issued.
3. **Execution**:
    - The Vector Execution Unit (VXU) samples the CSRs.
    - It triggers the 41-cycle sequence internally.
    - Operands are pulled from the Vector Register File (VRF) instead of external pins.
    - The final 32-bit result is written back to the destination register.
4. **Status**: If saturation occurred, the VXU sets the `vxsat` bit in the background.

## 4. Advantages of CSR Mapping
- **Software Portability**: Compilers can target standard CSR instructions to configure the unit.
- **Context Switching**: The hardware state (Format, Rounding) is automatically saved/restored as part of the processor's architectural state.
- **Pipelining**: Decoupling configuration from data streaming allows for better instruction scheduling.
