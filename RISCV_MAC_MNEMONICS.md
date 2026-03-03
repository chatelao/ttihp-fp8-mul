# RISC-V MAC Mnemonics: OCP MX, FP8, and FP4

This document summarizes the identified RISC-V instructions for Multiply-Accumulate (MAC) operations utilizing OCP Microscaling Formats (MX) for FP8 and FP4.

## 1. OCP-MX-V (Custom Scalar Extension)
The `OCP-MX-V` extension provides a set of custom R-type instructions (Opcode `0x0b`) for bit-serial MAC operations, optimized for integration with the SERV core.

| Mnemonic | Opcode | funct3 | Description |
|:---|:---:|:---:|:---|
| `MX.SETFMT` | 0x0b | 0x0 | Set format/rounding mode from `rs1`. |
| `MX.LOADS`  | 0x0b | 0x1 | Load Shared Scale A (`rs1`) and B (`rs2`). |
| `MX.MAC`    | 0x0b | 0x2 | Stream 4+4 packed elements for MAC from `rs1`, `rs2`. |
| `MX.READ`   | 0x0b | 0x3 | Read 32-bit accumulator into `rd`. |

### Register Bit-Mapping (`MX.SETFMT`)
- `rs1[2:0]`: `format_a`
- `rs1[4:3]`: `round_mode`
- `rs1[5]`: `overflow_wrap`

---

## 2. ZvfofpXmin (Minimal Vector OCP Floating-Point)
`ZvfofpXmin` is a proposed minimal vector extension for OCP MX support, integrating the MAC unit into the RISC-V Vector pipeline.

| Mnemonic | Type | Description |
|:---|:---:|:---|
| `vdot.mx` | Vector-Vector | Vector dot product of two OCP MX blocks. |

### Architectural Integration
- **CSRs**: Uses `vmxfmt` (0x800) for format configuration.
- **State**: Respects standard RVV 1.0 CSRs (`vstart`, `vl`, `vtype`, `vxsat`).

---

## 3. Zvf8mmai (Vector FP8 Matrix-Multiply-Accumulate)
`Zvf8mmai` is an inferred extension for vector-based 8-bit floating-point matrix operations.

| Mnemonic | Description |
|:---|:---|
| `vf8mmai.vv` | Vector matrix-multiply-accumulate for FP8 formats (E4M3/E5M2). |

---

## 4. Zf8 (Scalar FP8 Support)
`Zf8` refers to scalar support for 8-bit floating-point formats, providing base conversion and arithmetic instructions.

| Mnemonic | Description |
|:---|:---|
| `fcvt.s.f8` | Convert FP8 to Single-Precision (FP32). |
| `fcvt.f8.s` | Convert Single-Precision (FP32) to FP8. |
| `fadd.f8`    | Scalar FP8 addition (rare in minimal implementations). |

---

## 5. Summary of OCP MX Formats (Element IDs)
These IDs are used in `MX.SETFMT` and `vmxfmt`.

| ID | Format | Type | Bits |
|:---|:---|:---|:---:|
| `000` | E4M3 | MXFP8 | 8 |
| `001` | E5M2 | MXFP8 | 8 |
| `010` | E3M2 | MXFP6 | 6 |
| `011` | E2M3 | MXFP6 | 6 |
| `100` | E2M1 | MXFP4 | 4 |
| `101` | INT8 | MXINT8 | 8 |
| `110` | INT8_SYM | MXINT8 | 8 |

---

## References
- `documentation/SERV_INTEGRATION_CONCEPT.md`
- `documentation/CSR_RVV_CONCEPT_AND_ROADMAP.md`
- `documentation/ZvfofpXmin_GAP.md`
- `documentation/RISCV/OCP-MICROSCALING-FORMATS-MX-V1-0-SPEC.PDF`
- `documentation/RISCV/2510.14557V1.PDF`
