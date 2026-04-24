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

## 2. PULP Snitch (Small-Float / Xff8 Extension)
The Snitch core from the PULP platform utilizes a custom "Small-Float" extension for efficient 8-bit floating-point arithmetic.

| Mnemonic | Opcode | funct3 | Description |
|:---|:---:|:---:|:---|
| `vfdotp.s.f8` | 0x5b | 0x4 | Vector dot-product of FP8 elements (Sum of Products). |
| `vfmac.s.f8`  | 0x5b | 0x5 | Vector multiply-accumulate for FP8 elements. |
| `vfmadd.s.f8` | 0x5b | 0x6 | Vector fused multiply-add for FP8 elements. |

### Architectural Integration
- **Extension**: Part of the `Xpulpf` / `Xff8` ISA extension.
- **Register File**: Operates on the 32-bit (or 64-bit) floating-point registers, treating them as vectors of 4 (or 8) FP8 elements.

---

## 3. ZvfofpXmin (Minimal Vector OCP Floating-Point)
`ZvfofpXmin` is a proposed minimal vector extension for OCP MX support, integrating the MAC unit into the RISC-V Vector pipeline.

| Mnemonic | Type | Description |
|:---|:---:|:---|
| `vdot.mx` | Vector-Vector | Vector dot product of two OCP MX blocks. |

### Architectural Integration
- **CSRs**: Uses `vmxfmt` (0x800) for format configuration.
- **State**: Respects standard RVV 1.0 CSRs (`vstart`, `vl`, `vtype`, `vxsat`).

---

## 4. Zvf8mmai (Vector FP8 Matrix-Multiply-Accumulate)
`Zvf8mmai` is an inferred extension for vector-based 8-bit floating-point matrix operations.

| Mnemonic | Description |
|:---|:---|
| `vf8mmai.vv` | Vector matrix-multiply-accumulate for FP8 formats (E4M3/E5M2). |

---

## 5. Zf8 (Scalar FP8 Support)
`Zf8` refers to scalar support for 8-bit floating-point formats, providing base conversion and arithmetic instructions.

| Mnemonic | Description |
|:---|:---|
| `fcvt.s.f8` | Convert FP8 to Single-Precision (FP32). |
| `fcvt.f8.s` | Convert Single-Precision (FP32) to FP8. |
| `fadd.f8`    | Scalar FP8 addition (rare in minimal implementations). |

---

## 6. Summary of OCP MX Formats (Element IDs)
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
- `integration/SERV_INTEGRATION_CONCEPT.md`
- `integration/CSR_RVV_CONCEPT_AND_ROADMAP.md`
- `research/ZVFOFPXMIN_GAP.md`
- `integration/RISCV/OCP-MICROSCALING-FORMATS-MX-V1-0-SPEC.PDF`
- `integration/RISCV/2510.14557V1.PDF`
