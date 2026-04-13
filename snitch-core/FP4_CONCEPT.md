# Concept: Add FP4 - Proposed FP4 Support for Snitch Core

## 1. Objective
This concept proposes the addition of 4-bit floating-point (FP4) support to the Snitch core, extending its current capabilities beyond RV32E, FP32, FP16, and FP8. This extension, tentatively named **Xff4**, aims to enable ultra-low-precision arithmetic for high-throughput machine learning applications, particularly for large language model (LLM) inference where FP4 quantization is increasingly relevant.

## 2. Proposed ISA Extension (Xff4)
The **Xff4** extension introduces scalar and vectorial instructions for FP4 arithmetic. It follows the established pattern of Snitch's small-float extensions (Xff16, Xff8), but utilizes the `CUSTOM0` (0x0B) opcode to avoid conflict with standard and existing custom extensions, as all format bits in the standard OP-FP and OP spaces are already allocated.

**Note**: This implementation provides the architectural and structural framework (parameters, decoding, subsystem routing). Full hardware support in the FPU requires corresponding updates to the underlying `fpnew` library to define and implement the FP4/Petit formats.

### 2.1. Instruction Encodings
FP4 instructions leverage the `OP-CUSTOM-0` (0x0B) opcode.

#### Petit Instructions (Opcode: 0x0B)
| Mnemonic | Description | Funct7 | Funct3 |
|:---|:---|:---:|:---:|
| `fadd.p` | Scalar FP4 Addition | `0000000` | `000` |
| `fsub.p` | Scalar FP4 Subtraction | `0000100` | `000` |
| `fmul.p` | Scalar FP4 Multiplication | `0001000` | `000` |
| `vfadd.p` | Vector FP4 Addition | `1000001` | `000` |
| `vfsub.p` | Vector FP4 Subtraction | `1000010` | `000` |
| `vfmul.p` | Vector FP4 Multiplication | `1000011` | `000` |
| `vfmac.p` | Vector FP4 MAC | `1001000` | `000` |
| `vfsum.p` | Vector FP4 Sum (Reduction) | `1000111` | `000` |

*Note: 'p' suffix denotes 'Petit' (4-bit).*

### 2.2. Register Packing (Vector Mode)
FP4 elements are packed into 32-bit (or 64-bit) floating-point registers:
- **32-bit (RV32E)**: 8 elements per register.
- **64-bit (DataWidth=64)**: 16 elements per register.

## 3. Hardware Impact

### 3.1. Snitch Core (`snitch.sv`)
- **Parameters**: `XF4` and `XF4ALT` added to conditionally enable logic.
- **Decoder**: Updated to recognize `0x0B` instructions and route them to the Accelerator Interface (FP_SS).
- **NSX**: `XF4` is added to the Non-Standard Extension check.

### 3.2. Floating-Point Subsystem (`snitch_fp_ss.sv`)
- **Operand Replication**: Extended to support 4-bit expansion (8x replication for 32-bit `FLEN`).
- **Format Mapping**: Maps instructions to `fpnew_pkg::FP8` as a structural placeholder until `fpnew_pkg::FP4` is defined in the FPU package.
- **IsPetit**: Internal logic to identify Petit instructions for correct operand handling.

### 3.3. FPU Wrapper (`snitch_fpu.sv`)
- Propagates `XF4` and `XF4ALT` parameters.
- Updates `FpFmtMask` and `IntFmtMask` to include support for 4-bit paths.

## 4. Format Definition (OCP E2M1)
The baseline FP4 format follows the OCP (Open Compute Project) Microscaling Format:
- **Encoding**: 1-bit Sign, 2-bit Exponent, 1-bit Mantissa (E2M1).
- **Bias**: 1.
- **Special Values**: Supports NaN and +/- Infinity (if configured).
