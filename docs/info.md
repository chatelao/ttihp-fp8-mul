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
    *   40-bit internal aligner.
    *   32-bit signed fixed-point accumulator.
*   **Vector Packing**: 2x throughput for 4-bit formats (FP4) via dual-lane streaming.
*   **Hardware Scaling**: Automatic UE8M0 shared exponent application ($2^{E-127}$).
*   **Flexible Rounding**: Supports RNE (Round-to-Nearest-Even), TRN, CEL, and FLR.
*   **MX+ Extensions**: Extended mantissa for "Block Max" outliers to improve accuracy.
*   **LNS Mode**: Integrated Mitchell’s Approximation for area-optimized multiplication.
*   **Logic Analyzer Mode**: 14 selectable internal probes for real-time silicon monitoring.

### 3. Applications
*   Mobile and Edge AI Inference.
*   Deep Learning Accelerator (DLA) sub-modules.
*   Convolutional Neural Network (CNN) hardware acceleration.
*   Quantized Large Language Model (LLM) execution.
*   Low-power DSP for IoT and wearables.

### 4. Functional Block Diagram
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

### 6. Specifications

#### 6.1 Absolute Maximum Ratings
*Stresses beyond those listed under Absolute Maximum Ratings may cause permanent damage to the device. Exposure to absolute-maximum-rated conditions for extended periods may affect device reliability.*

| Parameter | Symbol | Min | Max | Unit |
|-----------|:------:|:---:|:---:|:----:|
| Supply Voltage | $V_{DD}$ | -0.3 | 1.8 | V |
| Input Voltage | $V_{IN}$ | -0.3 | $V_{DD} + 0.3$ | V |
| Storage Temperature| $T_{STG}$ | -65 | 150 | °C |
| ESD Rating (HBM)   | $V_{ESD}$ | - | 2000 | V |

#### 6.2 Recommended Operating Conditions
| Parameter | Symbol | Min | Typ | Max | Unit |
|-----------|:------:|:---:|:---:|:---:|:----:|
| Supply Voltage | $V_{DD}$ | 1.62 | 1.8 | 1.98 | V |
| Operating Temperature| $T_A$ | -40 | 25 | 85 | °C |
| Clock Frequency | $F_{CLK}$ | - | 20 | 50 | MHz |

#### 6.3 Electrical Characteristics
*(Targeted for IHP SG13G2 Process)*

| Parameter | Symbol | Conditions | Min | Typ | Max | Unit |
|-----------|:------:|------------|:---:|:---:|:---:|:----:|
| High-level Input Voltage | $V_{IH}$ | | 0.7 $V_{DD}$ | | | V |
| Low-level Input Voltage | $V_{IL}$ | | | | 0.3 $V_{DD}$ | V |
| High-level Output Voltage| $V_{OH}$ | $I_{OH} = -2mA$ | $V_{DD} - 0.45$| | | V |
| Low-level Output Voltage | $V_{OL}$ | $I_{OL} = 2mA$ | | | 0.45 | V |

---

### 7. Detailed Description

#### 7.1 Streaming Protocol
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

#### 7.2 Register Layouts

The unit captures configuration and scaling data during the initial cycles.

**Cycle 0: Metadata 0 (`ui_in`)**
| Bit | Name | Description |
|:---:|------|-------------|
| `[7]` | **SHORT_PROT** | 1: Reuse previous scales/formats; jump to Cycle 3. |
| `[6]` | **DEBUG_EN** | 1: Enable internal probing and metadata echo. |
| `[5]` | **LOOPBACK_EN** | 1: Enable XOR loopback (`uo_out = ui_in ^ uio_in`). |
| `[4:3]` | **LNS_MODE** | Multiplier mode: `0`: Normal, `1`: LNS, `2`: Hybrid. |
| `[2:0]` | **NBM_OFF_A** | Exponent offset for Operand A (MX++). |

**Cycle 0: Metadata 1 (`uio_in`)**
If `DEBUG_EN=1`, bits `[3:0]` select the internal probe.
| Bit | Name | Description |
|:---:|------|-------------|
| `[7]` | **MX_PLUS_EN** | 1: Enable OCP MX+ extended mantissa. |
| `[6]` | **PACKED_EN** | 1: Enable Vector Packing (2 elements/byte). |
| `[5]` | **OVFL_WRAP** | 0: SAT (Saturate), 1: WRAP. |
| `[4:3]` | **ROUND_MODE** | `0`: TRN, `1`: CEL, `2`: FLR, `3`: RNE. |
| `[2:0]` | **NBM_OFF_B** | Exponent offset for Operand B / Format select. |

**Cycle 1: Scale A and Config A**
| Port | Name | Description |
|:---:|------|-------------|
| `ui_in[7:0]` | **SCALE_A** | 8-bit unsigned biased exponent (UE8M0, Bias 127). |
| `uio_in[7:3]`| **BM_IDX_A** | Block Max Index (0-31) for Operand A. |
| `uio_in[2:0]`| **FORMAT_A** | `0`: E4M3, `1`: E5M2, `2`: E3M2, `3`: E2M3, `4`: E2M1, `5`: INT8. |

**Cycle 2: Scale B and Config B**
| Port | Name | Description |
|:---:|------|-------------|
| `ui_in[7:0]` | **SCALE_B** | 8-bit unsigned biased exponent (UE8M0, Bias 127). |
| `uio_in[7:3]`| **BM_IDX_B** | Block Max Index (0-31) for Operand B. |
| `uio_in[2:0]`| **FORMAT_B** | Independent format for Operand B. |

#### 7.3 Debug Capabilities
The unit includes integrated logic analyzer probes for non-intrusive monitoring.

| Selector | Signal Description | Bit Mapping |
|:---:|---|---|
| `0x1` | **FSM State** | `[7:6]` State, `[5:0]` logical_cycle |
| `0x2` | **Exceptions** | `[7]` nan_sticky, `[6]` inf_pos, `[5]` inf_neg, `[4]` strobe |
| `0x3-0x6`| **Accumulator** | Live 32-bit accumulator (Byte-wise) |
| `0x7-0x8`| **Multiplier L0**| Lane 0 product (MSB/LSB) |
| `0x9` | **Control** | ENA, Strobe, Acc_En, Acc_Clear |
| `0xA` | **L0 Metadata** | `[7]` sign, `[6]` nan, `[5]` inf, `[4:0]` exp_sum |
| `0xB-0xC`| **Multiplier L1**| Lane 1 product (MSB/LSB) |
| `0xD` | **L1 Metadata** | `[7]` sign, `[6]` nan, `[5]` inf, `[4:0]` exp_sum |

---

### 8. Application Information

#### 8.1 Basic Operation Sequence
1.  **Reset**: Pulse `rst_n` low.
2.  **Config**: Send metadata in Cycle 0.
3.  **Scale**: Provide UE8M0 scales in Cycles 1-2.
4.  **Stream**: Send 32 element pairs.
5.  **Collect**: Read 4-byte result in Cycles 37-40.

#### 8.2 Firmware Example (C-style)
```c
void run_mac_block(uint8_t* a, uint8_t* b, uint8_t scale_a, uint8_t scale_b) {
    tt_write(0, 0x00, 0x00); // Standard Mode
    tt_write(1, scale_a, 0x00); // E4M3
    tt_write(2, scale_b, 0x00);
    for(int i=0; i<32; i++) {
        tt_write(3+i, a[i], b[i]);
    }
    // Result ready at Cycle 37
}
```

---

### 9. Package and Ordering Information
*The unit is delivered as a hard macro within the Tiny Tapeout 2x2 tile framework.*

| Part Number | Features | Package |
|-------------|----------|---------|
| TT-MXFP8-F | Full Edition (Dual-Lane, MX+) | QFN-64 (TT DevKit) |
| TT-MXFP8-L | Lite Edition (Balanced)       | QFN-64 (TT DevKit) |
| TT-MXFP8-T | Tiny Edition (Area-optimized) | QFN-64 (TT DevKit) |

---

### 10. Revision History
| Revision | Date | Description |
|----------|------|-------------|
| 1.0 | 2024-05 | Initial release for Tiny Tapeout. |

---

## Appendix: Mathematics

### OCP MX+ (Extended Mantissa)
$$V(A_{BM}) = S \cdot 2^{E_{max} - \text{Bias}} \cdot \left(1 + \frac{\text{concat}(E_i, M_i)}{2^{E_{bits} + M_{bits}}}\right) \cdot 2^{X_A - 127}$$

### Mitchell's Approximation
$$\log_2(1+m) \approx m, \quad m \in [0, 1)$$

## Thank you!
Special thanks to the Tiny Tapeout and IHP communities for supporting open-source silicon development.
