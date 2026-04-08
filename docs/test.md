# Streaming MAC Unit Test Sequences

This document provides comprehensive test sequences for the OCP MXFP8 Streaming MAC Unit, covering functional verification, advanced modes, and real-time debug capabilities. Each sequence follows the streaming protocol (Standard or Short).

## Functional Test Sequences

### Test Sequence 1: Standard FP8 E4M3 Dot Product
**Description**: 32 pairs of 1.0 (E4M3) with 1.0 Shared Scales.
**Calculation**: $\sum_{i=0}^{31} (1.0 \times 1.0) \times 1.0 \times 1.0 = 32.0$.
**Expected Result**: `0x00002000` (Fixed-point, 8 fractional bits: $32 \times 2^8 = 8192 = 0x2000$).

| Cycle | `ui_in` (E4M3) | `uio_in` (E4M3) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x00` | `0x00` | `0x00` | Metadata: TRN, SAT, E4M3, Standard Start |
| 1 | `0x7F` | `0x00` | `0x00` | `0x00` | Load Scale A = 1.0 ($2^{127-127}$) |
| 2 | `0x7F` | `0x00` | `0x00` | `0x00` | Load Scale B = 1.0 ($2^{127-127}$) |
| 3-34 | `0x38` | `0x38` | `0x00` | `0x00` | Stream 32 pairs of 1.0 (E4M3 = `0x38`) |
| 35 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 36 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 37 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result MSB (Byte 3: `0x00`) |
| 38 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result (Byte 2: `0x00`) |
| 39 | `0x00` | `0x00` | `0x00` | `0x20` | Output Result (Byte 1: `0x20`) |
| 40 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result LSB (Byte 0: `0x00`) |

---

### Test Sequence 2: Shared Scaling (2.0x)
**Description**: 32 pairs of 1.0 (E4M3) with Scale A = 2.0 and Scale B = 1.0.
**Expected Result**: $32 \times (1.0 \times 1.0) \times 2.0 = 64.0 \rightarrow$ `0x00004000`.

| Cycle | `ui_in` (E4M3) | `uio_in` (E4M3) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x00` | `0x00` | `0x00` | Standard Start |
| 1 | `0x80` | `0x00` | `0x00` | `0x00` | Scale A = 2.0 ($2^{128-127}$), Format A = E4M3 |
| 2 | `0x7F` | `0x00` | `0x00` | `0x00` | Scale B = 1.0, Format B = E4M3 |
| 3-34 | `0x38` | `0x38` | `0x00` | `0x00` | Elements A=1.0, B=1.0 |
| 35 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 36 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 37-40 | - | - | `0x00` | `Result` | **Result**: `0x00`, `0x00`, `0x40`, `0x00` |

---

### Test Sequence 3: Mixed Precision (E4M3 x E5M2)
**Description**: 32 pairs of 1.0 (E4M3) multiplied by 1.0 (E5M2).
**Expected Result**: $32 \times (1.0 \times 1.0) = 32.0 \rightarrow$ `0x00002000`.

| Cycle | `ui_in` (E4M3) | `uio_in` (E5M2) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x00` | `0x00` | `0x00` | Standard Start |
| 1 | `0x7F` | `0x00` | `0x00` | `0x00` | Scale A = 1.0, Format A = E4M3 |
| 2 | `0x7F` | `0x01` | `0x00` | `0x00` | Scale B = 1.0, Format B = E5M2 |
| 3-34 | `0x38` | `0x3C` | `0x00` | `0x00` | Elements A=1.0 (E4M3), B=1.0 (E5M2) |
| 35 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 36 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 37-40 | - | - | `0x00` | `Result` | **Result**: `0x00`, `0x00`, `0x20`, `0x00` |

---

### Test Sequence 4: Vector Packing (FP4 E2M1) - Standard Protocol
**Description**: 32 pairs of 1.0 (E2M1) using Packed Mode (2 elements per byte).
**Expected Result**: $32 \times (1.0 \times 1.0) = 32.0 \rightarrow$ `0x00002000`.

| Cycle | `ui_in` (FP4)| `uio_in` (FP4) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x40` | `0x00` | `0x00` | Packed Mode Enabled (`uio_in[6]=1`) |
| 1 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale A = 1.0, Format A = E2M1 |
| 2 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale B = 1.0, Format B = E2M1 |
| 3-18 | `0x22` | `0x22` | `0x00` | `0x00` | Packed Elements (High/Low nibble = 1.0 = `0x2`) |
| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 21-24 | - | - | `0x00` | `Result` | **Result**: `0x00`, `0x00`, `0x20`, `0x00` |

---

### Test Sequence 5: FP4 Fast Lane - Short Protocol
**Description**: This test case uses the Short Protocol and Packed Mode for 32 pairs of 1.0 (E2M1) elements.
**Expected Result**: `0x00002000`.

| Cycle | `ui_in`  (Dual E2M1) | `uio_in`  (Dual E2M1) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x80` | `0x44` | `0x00` | `0x00` | Short Start, Packed Mode, FP4 (`0x80`, `0x44`) |
| 3-18 | `0x22` | `0x22` | `0x00` | `0x00` | Stream 16 bytes of packed 1.0 (FP4 1.0 = `0x2`) |
| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 21 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 3 (`0x00`) |
| 22 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 2 (`0x00`) |
| 23 | `0x00` | `0x00` | `0x00` | `0x20` | Output Result Byte 1 (`0x20`) |
| 24 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 0 (`0x00`) |

---

### Test Sequence 6: OCP MX+ (Extended Mantissa)
**Description**: 1 pair of 1.0 (BM elements) and 31 pairs of 0.0. BM Index 0.
**Expected Result**: $1.0 \times 1.0 = 1.0 \rightarrow$ `0x00000100`.
*Note: In MX+ mode, a BM element with bits `0x00` represents 1.0 (scaled).*

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x80` | `0x00` | `0x00` | MX+ Enabled (`uio_in[7]=1`) |
| 1 | `0x7F` | `0x00` | `0x00` | `0x00` | Scale A = 1.0, Format A = E4M3, BM Index A = 0 |
| 2 | `0x7F` | `0x00` | `0x00` | `0x00` | Scale B = 1.0, Format B = E4M3, BM Index B = 0 |
| 3 | `0x00` | `0x00` | `0x00` | `0x00` | BM Elements (Value = 1.0) |
| 4-34 | `0x00` | `0x00` | `0x00` | `0x00` | Non-BM Elements (Value = 0.0) |
| 35 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 36 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 37-40 | - | - | `0x00` | `Result` | **Result**: `0x00`, `0x00`, `0x01`, `0x00` |

---

### Test Sequence 7: Logarithmic Multiplier (LNS Mode)
**Description**: 32 pairs of 1.125 (0x39) and 1.25 (0x3A) in E4M3 format using Mitchell's Approximation.
**Calculation**: Using Mitchell's Approximation, $1.125 \times 1.25 \approx 1.375$. $\sum_{i=0}^{31} (1.375) = 44.0$.
**Expected Result**: `0x00002C00` (Fixed-point, 8 fractional bits: $44 \times 2^{8} = 11264 = 0x2C00$).

| Cycle | `ui_in` (E4M3) | `uio_in` (E4M3) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x08` | `0x00` | `0x00` | `0x00` | Metadata: LNS Mode 1 enabled (`ui_in[4:3]=1`) |
| 1 | `0x7F` | `0x00` | `0x00` | `0x00` | Load Scale A = 1.0 |
| 2 | `0x7F` | `0x00` | `0x00` | `0x00` | Load Scale B = 1.0 |
| 3-34 | `0x39` | `0x3A` | `0x00` | `0x00` | Stream 32 pairs (A=1.125, B=1.25) |
| 35 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 36 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 37-40 | - | - | `0x00` | `Result` | **Result**: `0x00`, `0x00`, `0x2C`, `0x00` |

---

## Debug & Observability Test Sequences

These test cases demonstrate the unit's "Logic Analyzer" mode, enabled via `ui_in[6]` in Cycle 0.

### Debug Mode: 0x0 (Default)
**Related Specification**: [Logic Analyzer Mode](info.md#1-real-time-observability-logic-analyzer-mode)

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x00` | `0x00` | `0x00` | Debug Enable, Probe Selector 0x0 |
| 1-36 | `0x00` | `0x00` | `0x00` | `0x00` | Normal operation: `uo_out` remains 0x00 |

### Debug Mode: 0x1 (FSM State & Timing)
**Description**: Standard E4M3 run with Debug Mode enabled. Monitoring FSM State.
**Mapping**: `uo_out[7:6]` = State (0:IDLE, 1:LOAD, 2:STREAM, 3:OUT), `uo_out[5:0]` = Cycle.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x01` | `0x00` | `0x00` | Debug En, Sel 0x1 |
| 1 | `0x7F` | `0x00` | `0x00` | `0x41` | State LOAD (01), Cycle 1 |
| 2 | `0x7F` | `0x00` | `0x00` | `0x42` | State LOAD (01), Cycle 2 |
| 3 | `0x38` | `0x38` | `0x00` | `0x83` | State STREAM (10), Cycle 3 |
| 4-34 | `0x38` | `0x38` | `0x00` | `0x80+cycle` | State STREAM (10), Cycles 4-34 |
| 35 | `0x00` | `0x00` | `0x00` | `0x00`* | **Metadata Echo** (format_a=0) |
| 36 | `0x00` | `0x00` | `0x00` | `0xA4` | State STREAM (10), Cycle 36 |
| 37-40 | `0x00` | `0x00` | `0x00` | `Result` | State OUTPUT (11) - Probe disabled, shows result |

*\*Note: Metadata Echo in Cycle 35 depends on previous inputs. For this run (E4M3, TRN, SAT), it should be `0x00`.*

### Debug Mode: 0x2 (Exception Monitor)
**Mapping**: `uo_out[7]` nan_sticky, `[6]` inf_pos, `[5]` inf_neg, `[4]` strobe.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x02` | `0x00` | `0x10` | `uo_out[4]=1` (strobe) |
| 3 | `0x7F` | `0x38` | `0x00` | `0x90` | A=NaN (`0x7F`). `uo_out[7]` (nan_sticky) = 1 |

### Debug Mode: 0x3-0x6 (Accumulator Monitoring)
Allows real-time monitoring of the 32-bit internal accumulator.

| Selector | Mapping | Description |
|:---:|:---|:---|
| 0x3 | `uo_out` = `ACC[31:24]` | Live MSB monitoring |
| 0x4 | `uo_out` = `ACC[23:16]` | Live Byte 2 monitoring |
| 0x5 | `uo_out` = `ACC[15:8]` | Live Byte 1 monitoring |
| 0x6 | `uo_out` = `ACC[7:0]` | Live LSB monitoring |

### Debug Mode: 0x7-0x8 (Multiplier Lane 0)
Allows monitoring of the product from the first multiplier lane.

| Selector | Mapping | Description |
|:---:|:---|:---|
| 0x7 | `uo_out` = `MUL[15:8]` | Upper byte of lane 0 product |
| 0x8 | `uo_out` = `MUL[7:0]` | Lower byte of lane 0 product |

### Debug Mode: 0x9 (Control Signals)
**Mapping**: `uo_out[7]` ena, `[6]` strobe, `[5]` acc_en, `[4]` acc_clear.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x09` | `0x00` | `0x00` | Control signals monitoring |
| 1-2 | `0x7F` | `0x00` | `0x00` | `0xD0` | `ena=1, strobe=1, acc_clear=1` |
| 4-34 | `0x38` | `0x38` | `0x00` | `0xE0` | `ena=1, strobe=1, acc_en=1` |

### Test Sequence 8: NaN Exception (Element-triggered)
**Description**: Streaming an E4M3 NaN element (`0x7F`) to trigger `nan_sticky` in Debug Mode 0x2.
**Expected Result**: `uo_out[7]` becomes 1.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x02` | `0x00` | `0x10` | Debug En, Sel 0x2 (Exception Monitor) |
| 1 | `127` | `0x00` | `0x00` | `0x10` | Scale A = 1.0 (127), Format A = E4M3 |
| 2 | `127` | `0x00` | `0x00` | `0x10` | Scale B = 1.0 (127), Format B = E4M3 |
| 3 | `0x7F` | `0x38` | `0x00` | `0x10` | Stream NaN (`0x7F`) |
| 4 | `0x38` | `0x38` | `0x00` | `0x10` | Pipelining... |
| 5 | `0x38` | `0x38` | `0x00` | `0x90` | `uo_out[7]` (nan_sticky) = 1 |

---

### Test Sequence 9: NaN Exception (Scale-triggered)
**Description**: Loading Scale A = `0xFF` during Cycle 1.
**Expected Result**: `uo_out[7]` becomes 1.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x02` | `0x00` | `0x10` | Debug En, Sel 0x2 |
| 1 | `255` | `0x00` | `0x00` | `0x10` | Scale A = 255 (0xFF, NaN) |
| 2 | `127` | `0x00` | `0x00` | `0x90` | `nan_sticky` set due to Cycle 1 Scale |

---

### Test Sequence 10: Infinity Exceptions (Positive and Negative)
**Description**: Using E5M2 operands to trigger `inf_pos_sticky` and `inf_neg_sticky`.
**Expected Result**: `uo_out[6]` and `uo_out[5]` go high.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x02` | `0x00` | `0x10` | Debug En, Sel 0x2 |
| 1 | `127` | `0x00` | `0x00` | `0x10` | Scale A = 1.0 |
| 2 | `127` | `0x01` | `0x00` | `0x10` | Scale B = 1.0, Format B = E5M2 |
| 3 | `0x7C` | `0x3C` | `0x00` | `0x10` | +Inf (0x7C) x 1.0 (0x3C) |
| 4 | `0xFC` | `0x3C` | `0x00` | `0x10` | -Inf (0xFC) x 1.0 (0x3C) |
| 5 | `0x3C` | `0x3C` | `0x00` | `0x50` | `inf_pos_sticky` (uo_out[6]) = 1 |
| 6 | `0x3C` | `0x3C` | `0x00` | `0x70` | `inf_neg_sticky` (uo_out[5]) = 1 |
