# RISC-V Instruction Mnemonics for MAC and OCP MX/MX+

This document lists the identified RISC-V instruction mnemonics for Multiply-Accumulate (MAC) operations, specifically targeting OCP Microscaling Formats (MX) and MX+ for FP8 and FP4. This includes custom extensions defined for this project (OCP-MX-V) and proposed/standard RISC-V extensions (ZvfofpXmin, Zvf8mmai).

## 1. OCP-MX-V (Custom Extension)
Designed for tight integration with bit-serial cores like SERV. Uses the `custom-0` (0x0b) opcode.

| Mnemonic | Opcode | funct3 | funct7 | Description |
|:---|:---:|:---:|:---:|:---|
| **`MX.SETFMT rd, rs1`** | 0x0b | 0x0 | 0x00 | Set format, rounding mode, and overflow behavior from `rs1`. |
| **`MX.LOADS rs1, rs2`** | 0x0b | 0x1 | 0x00 | Load Shared Scale Factor A (`rs1`) and B (`rs2`) into the MAC unit. |
| **`MX.MAC rs1, rs2`** | 0x0b | 0x2 | 0x00 | Stream 4+4 packed 8-bit elements from `rs1` and `rs2` for MAC. |
| **`MX.READ rd`** | 0x0b | 0x3 | 0x00 | Read the 32-bit accumulated result from the internal register to `rd`. |

## 2. ZvfofpXmin (Minimal Vector OCP Floating-Point)
A proposed minimal vector extension to support OCP MX formats natively in the RISC-V Vector (RVV) pipeline.

| Mnemonic | Description |
|:---|:---|
| **`vdot.mx vd, vs2, vs1`** | Vector-Vector dot product using MX shared scaling logic. |
| **`vdot.mx.vs vd, vs2, rs1`** | Vector-Scalar dot product using MX shared scaling logic. |

## 3. Zvf8mmai / Zf8mmai (8-bit Matrix Multiply-Accumulate)
Proposed extensions for hardware-accelerated 8-bit floating-point matrix operations (FP8 E4M3/E5M2).

| Mnemonic | Format | Description |
|:---|:---:|:---|
| **`vfmma.vv`** | Vector | Vector-Vector FP8 matrix multiply-accumulate. |
| **`vfmacc.vv`** | Vector | Vector-Vector FP8 multiply-accumulate (element-wise). |
| **`fmma.s`** | Scalar | Scalar FP8 matrix multiply-accumulate (FPU extension). |

## 4. OCP MX+ / MX++ Specific Mnemonics
Extensions to support repurposed exponent precision (outlier handling) and decoupled scaling.

| Mnemonic | Description |
|:---|:---|
| **`MX.SETFMT.PLUS`** | Extended version of `MX.SETFMT` to enable MX+ features (e.g., `EXT` bit). |
| **`MX.MAC.PLUS`** | MAC operation aware of repurposed exponents for outlier precision. |
| **`vdot.mxplus`** | Vector dot product with MX+ outlier handling enabled. |

## 5. Comparison of Instruction Formats

### R-Type (Scalar/Custom)
Used by `OCP-MX-V`.
`[ funct7 | rs2 | rs1 | funct3 | rd | opcode ]`

### Vector-Config (RVV)
Used by `ZvfofpXmin` and `Zvf8mmai`.
Relies on `vsetvli` to set `vtype` (SEW, LMUL) and uses standard vector opcodes with custom `funct` encodings.

---
*Note: Some mnemonics are proposed and may vary based on final RISC-V International ratification.*
