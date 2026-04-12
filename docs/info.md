<!---
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

# OCP MXFP8 Streaming MAC Unit
## High-Performance AI Inference Accelerator with Shared Scaling

### 1. General Description
The **OCP MXFP8 Streaming MAC Unit** is a high-performance, area-optimized arithmetic core designed for next-generation AI inference acceleration. Fully compliant with the **OpenCompute (OCP) Microscaling Formats (MX) Specification v1.0**, the unit supports a comprehensive suite of sub-8-bit floating-point and integer formats.

Featuring hardware-accelerated shared scaling and an area-efficient logarithmic multiplier path, the core is optimized for deployment in resource-constrained edge devices and large-scale AI accelerators alike. The "Full" edition provides a 2x2 tile configuration (Tiny Tapeout) with dual-lane processing capabilities.

### 2. Features
*   **OCP MX Compliance**: Full support for OCP Microscaling Formats v1.0.
*   **Multi-Format Support**:
    *   FP8 (E4M3, E5M2)
    *   FP6 (E3M2, E2M3)
    *   FP4 (E2M1)
    *   INT8 / INT8_SYM
*   **High-Precision Datapath**:
    *   40-bit internal aligner for high-dynamic range support.
    *   32-bit signed fixed-point accumulator.
*   **Vector Packing**: 2x throughput for 4-bit formats (FP4) via dual-lane streaming.
*   **Hardware Scaling**: Automatic UE8M0 shared exponent application ($2^{E-127}$).
*   **Flexible Rounding**: Supports RNE (Round-to-Nearest-Even), TRN, CEL, and FLR.
*   **MX+ Extensions**: Extended mantissa for "Block Max" outliers to improve accuracy.
*   **LNS Mode**: Integrated Mitchell’s Approximation for area-optimized multiplication.
*   **Logic Analyzer Mode**: 14 selectable internal probes for real-time silicon monitoring.
*   **Mixed Precision**: Independent format selection for Operand A and Operand B.

### 3. Applications
*   Mobile and Edge AI Inference.
*   Deep Learning Accelerator (DLA) sub-modules.
*   Convolutional Neural Network (CNN) hardware acceleration.
*   Quantized Large Language Model (LLM) execution.
*   Low-power DSP for IoT and wearables.

### 4. Functional Block Diagram
The unit follows a pipelined architecture consisting of a dual-lane multiplier, a high-dynamic range aligner, and a 32-bit accumulator.

![System Context Diagram](circuit.svg)

---

### 5. Pin Configuration and Functions
The unit utilizes an 8-bit streaming interface to minimize pin count while maintaining high throughput.

| Pin | Name | Type | Description |
|:---:|------|:----:|-------------|
| `ui_in[7:0]` | **DATA_A** | I | Operand A elements, Scale A, or Metadata 0. |
| `uio_in[7:0]` | **DATA_B** | I | Operand B elements, Scale B, or Metadata 1. |
| `uo_out[7:0]` | **RESULT** | O | Serialized 32-bit result or Debug Probe data. |
| `uio_out[7:0]`| **RESERVED**| O | Driven to 0x00 (Configured as Inputs via `uio_oe`). |
| `clk` | **CLK** | I | System Clock (Target: 20MHz). |
| `rst_n` | **RESET_N** | I | Active-low asynchronous reset. |
| `ena` | **ENA** | I | Clock Enable. |

---

### 6. Detailed Description

#### 6.1 Operational Modes
The MAC unit supports several specialized modes to balance throughput, area, and precision.

*   **Standard Mode**: Single-lane processing for 8-bit, 6-bit, and 4-bit formats over 41 cycles.
*   **Packed Mode**: Dual-lane processing for 4-bit formats (FP4), doubling throughput by reducing the stream phase to 16 cycles.
*   **LNS Mode**: Replaces the standard multiplier with a logarithmic adder using Mitchell's Approximation, reducing area by ~50% in the multiplier core.
*   **Debug Mode**: Allows internal probing of the accumulator, FSM states, and multiplier results via the `uo_out` port.

#### 6.2 Streaming Protocol
The unit operates using a **41-cycle streaming protocol** to process a block of 32 elements ($k=32$).

| Cycle | Input `ui_in` | Input `uio_in` | Output `uo_out` | Phase |
|-------|---------------|----------------|-----------------|-------|
| 0 | Metadata 0 | Metadata 1 | 0x00 / Probe | **IDLE / CONFIG** |
| 1 | Scale A | Format A / BM A | 0x00 / Probe | **LOAD_CFG_A** |
| 2 | Scale B | Format B / BM B | 0x00 / Probe | **LOAD_CFG_B** |
| 3-34 | Element $A_i$ | Element $B_i$ | 0x00 / Probe | **STREAM** |
| 35 | - | - | Meta Echo | **FLUSH** |
| 36 | - | - | 0x00 | **CALC** |
| 37-40 | - | - | Result [31:0] | **OUTPUT** |

*\*Note: In Packed Mode, the STREAM phase is reduced to 16 cycles (Cycles 3-18).*

#### 6.3 Register Layouts (Cycle 0-2)

**Cycle 0: Metadata 0 (`ui_in`)**
![Metadata 0 (ui_in)](metadata_c0_ui.svg)

| Bit | Name | Description |
|:---:|------|-------------|
| `[7]` | **SHORT_PROT** | 1: Reuse previous scales/formats; jump to Cycle 3. |
| `[6]` | **DEBUG_EN** | 1: Enable internal probing and metadata echo. |
| `[5]` | **LOOPBACK_EN** | 1: Enable XOR loopback (`uo_out = ui_in ^ uio_in`). |
| `[4:3]` | **LNS_MODE** | Multiplier mode: `0`: Normal, `1`: LNS, `2`: Hybrid. |
| `[2:0]` | **NBM_OFF_A** | Exponent offset for Operand A (MX++). |

**Cycle 0: Metadata 1 (`uio_in`)**
![Metadata 1 (uio_in)](metadata_c0_uio.svg)

| Bit | Name | Description |
|:---:|------|-------------|
| `[7]` | **MX_PLUS_EN** | 1: Enable OCP MX+ extended mantissa. |
| `[6]` | **PACKED_EN** | 1: Enable Vector Packing (2 elements/byte). |
| `[5]` | **OVFL_WRAP** | 0: SAT (Saturate), 1: WRAP. |
| `[4:3]` | **ROUND_MODE** | `0`: TRN, `1`: CEL, `2`: FLR, `3`: RNE. |
| `[2:0]` | **NBM_OFF_B** | Exponent offset for Operand B / Format select. |

**Cycle 1: Scale A and Config A**
![Scale A](scale_a.svg)
![Config A](config_a.svg)

| Port | Name | Description |
|:---:|------|-------------|
| `ui_in[7:0]` | **SCALE_A** | 8-bit unsigned biased exponent (UE8M0, Bias 127). |
| `uio_in[7:3]`| **BM_IDX_A** | Block Max Index (0-31) for Operand A. |
| `uio_in[2:0]`| **FORMAT_A** | `0`: E4M3, `1`: E5M2, `2`: E3M2, `3`: E2M3, `4`: E2M1, `5`: INT8. |

**Cycle 2: Scale B and Config B**
![Scale B](scale_b.svg)
![Config B](config_b.svg)

| Port | Name | Description |
|:---:|------|-------------|
| `ui_in[7:0]` | **SCALE_B** | 8-bit unsigned biased exponent (UE8M0, Bias 127). |
| `uio_in[7:3]`| **BM_IDX_B** | Block Max Index (0-31) for Operand B. |
| `uio_in[2:0]`| **FORMAT_B** | Independent format for Operand B. |

#### 6.4 Format Support and Packing
The unit supports a wide range of OCP MX compliant formats. During the STREAM phase (Cycles 3-34), elements are presented on `ui_in` and `uio_in`.

| Format | $E_{bits}$ | $M_{bits}$ | Bias | Bit Layout |
|:---:|:---:|:---:|:---:|---|
| **E4M3** | 4 | 3 | 7 | `S[7] E[6:3] M[2:0]` |
| **E5M2** | 5 | 2 | 15| `S[7] E[6:2] M[1:0]` |
| **E3M2** | 3 | 2 | 3 | `S[5] E[4:2] M[1:0]` (Bits [7:6] ignored) |
| **E2M3** | 2 | 3 | 1 | `S[5] E[4:3] M[2:0]` (Bits [7:6] ignored) |
| **E2M1** | 2 | 1 | 1 | `S[3] E[2:1] M[0]` (Bits [7:4] ignored) |
| **INT8** | - | - | - | `S[7] V[6:0]` (Two's complement) |

**Packed FP4 (FP4/Dual)**
When `PACKED_EN=1` (Metadata 1) and both formats are FP4 (E2M1), the unit processes two elements per cycle per lane.
![Packed FP4](element_fp4_packed.svg)

| Bit | Name | Description |
|:---:|------|-------------|
| `[7:4]` | **Element i+1** | High nibble contains the next element in the sequence. |
| `[3:0]` | **Element i** | Low nibble contains the current element. |

#### 6.5 Debug Capabilities
The unit includes integrated logic analyzer probes for real-time silicon monitoring, enabled via `DEBUG_EN=1` at Cycle 0.

| Selector (`uio_in[3:0]` @ C0) | Signal Description | Bit Mapping |
|:---:|---|---|
| `0x1` | **FSM State** | `[7:6]` State, `[5:0]` logical_cycle |
| `0x2` | **Exceptions** | `[7]` nan_sticky, `[6]` inf_pos, `[5]` inf_neg, `[4]` strobe |
| `0x3-0x6`| **Accumulator** | Live 32-bit accumulator (Byte-wise) |
| `0x7-0x8`| **Multiplier L0**| Lane 0 product (MSB/LSB) |
| `0x9` | **Control** | ENA, Strobe, Acc_En, Acc_Clear |
| `0xA` | **L0 Metadata** | `[7]` sign, `[6]` nan, `[5]` inf, `[4:0]` exp_sum |
| `0xB-0xC`| **Multiplier L1**| Lane 1 product (MSB/LSB) |
| `0xD` | **L1 Metadata** | `[7]` sign, `[6]` nan, `[5]` inf, `[4:0]` exp_sum |

#### 6.6 FP4 Fast Mode
The unit provides a high-throughput **FP4 Fast Lane** mode by combining **Vector Packing** and the **Short Protocol**.

In this mode:
- **Vector Packing** (`uio_in[6]=1` at Cycle 0) enables dual-lane processing, reducing the STREAM phase from 32 to 16 cycles.
- **Short Protocol** (`ui_in[7]=1` at Cycle 0) bypasses the Scale/Format load cycles (Cycles 1-2).
- The total block latency is reduced from 41 cycles to **23 cycles** (1 Config + 16 Stream + 6 Flush/Output).

### 7. Application and Implementation

#### 7.1 Typical Application Circuit
The MAC unit is typically interfaced with a host MCU (e.g., RP2040 or a RISC-V core like SERV) via the 8-bit `ui_in` and `uio_in` buses.

#### 7.2 Firmware Example (C-style)
```c
// Perform a single MX block operation (32 elements)
void run_mac_block(uint8_t* a, uint8_t* b, uint8_t scale_a, uint8_t scale_b) {
    // Cycle 0: Configuration
    tt_write(0, 0x00, 0x00);
    // Cycle 1-2: Load Scales and Formats
    tt_write(1, scale_a, 0x00); // Set Scale A and Format A (E4M3)
    tt_write(2, scale_b, 0x00); // Set Scale B and Format B (E4M3)
    // Cycles 3-34: Stream Elements
    for(int i=0; i<32; i++) {
        tt_write(3+i, a[i], b[i]);
    }
    // Result ready at Cycle 37-40
    uint32_t result = tt_read_result();
}
```

---

### 8. Package and Ordering Information
The unit is delivered as a hard macro within the Tiny Tapeout 2x2 tile framework.

| Part Number | Description | Gate Count | Tile Size |
|-------------|-------------|:---:|:---:|
| **TT-MXFP8-F** | Full Edition (Dual-Lane, MX+) | ~6600 | 2x2 |
| **TT-MXFP8-L** | Lite Edition (Single-Lane) | ~3900 | 1x1 |
| **TT-MXFP8-T** | Tiny Edition (FP8/FP4 Only) | ~2100 | 1x1 |

---

### 9. Revision History
| Revision | Date | Description |
|:---:|:---:|---|
| 1.0 | 2024-05 | Initial release for Tiny Tapeout. |
| 1.1 | 2025-03 | Expanded to comprehensive reference manual. |

---

## Appendix: Mathematics

### OCP MX+ (Extended Mantissa)
MX+ leverages the redundancy in the Block Max element (where the exponent is always $E_{max}$) to provide additional mantissa precision:
$$V(A_{BM}) = S \cdot 2^{E_{max} - \text{Bias}} \cdot \left(1 + \frac{\text{concat}(E_i, M_i)}{2^{E_{bits} + M_{bits}}}\right) \cdot 2^{X_A - 127}$$

### Mitchell's Approximation (LNS Mode)
In LNS mode, multiplication is simplified to the addition of logarithmic representations:
$$\log_2(1+M) \approx M$$
$$\log_2(A \times B) \approx (E_A + M_A) + (E_B + M_B) - 2 \times \text{Bias}$$

## Thank you!
Special thanks to the Tiny Tapeout and IHP communities for supporting open-source silicon development.
