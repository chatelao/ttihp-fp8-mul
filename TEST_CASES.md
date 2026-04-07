# OCP MXFP8 Streaming MAC Unit - Test Cases

This document details specific test sequences to verify the functional and debug capabilities of the MAC unit.

## FP8 Dot Product (Standard Protocol)
**Related Specification**: [Streaming Protocol](docs/info.md#streaming-protocol), [E4M3 Format](docs/reference/SUMMARY.md#supported-element-formats)

This test case performs a dot product of 32 pairs of 1.0 (E4M3) elements.
**Calculation**: $\sum_{i=0}^{31} (1.0 \times 1.0) \times 1.0 \times 1.0 = 32.0$.
**Result (Hex)**: `0x00002000` (Fixed-point, 8 fractional bits: $32 \times 2^8 = 8192 = 0x2000$).

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
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

## FP4 Fast Lane (Short Protocol)
**Related Specification**: [Short Protocol](docs/info.md#cycle-0-metadata-0-ui_in), [Vector Packing](docs/info.md#advanced-modes), [FP4 Format](docs/reference/SUMMARY.md#supported-element-formats)

This test case uses the Short Protocol and Packed Mode for 32 pairs of 1.0 (E2M1) elements.
**Calculation**: $\sum_{i=0}^{31} (1.0 \times 1.0) \times 1.0 \times 1.0 = 32.0$.
**Result (Hex)**: `0x00002000`.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x80` | `0x44` | `0x00` | `0x00` | Short Start, Packed Mode, FP4 (`0x80`, `0x44`) |
| 3-18 | `0x22` | `0x22` | `0x00` | `0x00` | Stream 16 bytes of packed 1.0 (FP4 1.0 = `0x2`) |
| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 21 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 3 (`0x00`) |
| 22 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 2 (`0x00`) |
| 23 | `0x00` | `0x00` | `0x00` | `0x20` | Output Result Byte 1 (`0x20`) |
| 24 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 0 (`0x00`) |

## Debug Mode: 0x0 (Default)
**Related Specification**: [Logic Analyzer Mode](docs/info.md#1-real-time-observability-logic-analyzer-mode)

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x00` | `0x00` | `0x00` | Debug Enable, Probe Selector 0x0 |
| 1-36 | `0x00` | `0x00` | `0x00` | `0x00` | Normal operation: `uo_out` remains 0x00 |

## Debug Mode: 0x1 (FSM State & Timing)
**Related Specification**: [Logic Analyzer Mode - Selector 0x1](docs/info.md#1-real-time-observability-logic-analyzer-mode)

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

## Debug Mode: 0x2 (Exception Monitor)
**Related Specification**: [Logic Analyzer Mode - Selector 0x2](docs/info.md#1-real-time-observability-logic-analyzer-mode)

**Mapping**: `[7]` nan_sticky, `[6]` inf_pos, `[5]` inf_neg, `[4]` strobe.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x02` | `0x00` | `0x10` | `uo_out[4]=1` (strobe) |
| 3 | `0x7F` | `0x38` | `0x00` | `0x90` | A=NaN (`0x7F`). `uo_out[7]` (nan_sticky) = 1 |

## Debug Mode: 0x3 (Accumulator [31:24])
**Related Specification**: [Logic Analyzer Mode - Selector 0x3](docs/info.md#1-real-time-observability-logic-analyzer-mode)

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x03` | `0x00` | `0x00` | Live MSB monitoring |
| 3-36 | `0x38` | `0x38` | `0x00` | `ACC[31:24]` | Live value of accumulator |

## Debug Mode: 0x4 (Accumulator [23:16])
**Related Specification**: [Logic Analyzer Mode - Selector 0x4](docs/info.md#1-real-time-observability-logic-analyzer-mode)

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x04` | `0x00` | `0x00` | Live Byte 2 monitoring |
| 3-36 | `0x38` | `0x38` | `0x00` | `ACC[23:16]` | Live value of accumulator |

## Debug Mode: 0x5 (Accumulator [15:8])
**Related Specification**: [Logic Analyzer Mode - Selector 0x5](docs/info.md#1-real-time-observability-logic-analyzer-mode)

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x05` | `0x00` | `0x00` | Live Byte 1 monitoring |
| 3-36 | `0x38` | `0x38` | `0x00` | `ACC[15:8]` | Live value of accumulator |

## Debug Mode: 0x6 (Accumulator [7:0])
**Related Specification**: [Logic Analyzer Mode - Selector 0x6](docs/info.md#1-real-time-observability-logic-analyzer-mode)

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x06` | `0x00` | `0x00` | Debug En, Sel 0x6 |
| 3-36 | `0x38` | `0x38` | `0x00` | `ACC[7:0]` | Live value of accumulator |

## Debug Mode: 0x7 (Multiplier Lane 0 [15:8])
**Related Specification**: [Logic Analyzer Mode - Selector 0x7](docs/info.md#1-real-time-observability-logic-analyzer-mode)

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x07` | `0x00` | `0x00` | Multiplier output monitoring |
| 4-35 | `0x38` | `0x38` | `0x00` | `MUL[15:8]` | Upper byte of lane 0 product |

## Debug Mode: 0x8 (Multiplier Lane 0 [7:0])
**Related Specification**: [Logic Analyzer Mode - Selector 0x8](docs/info.md#1-real-time-observability-logic-analyzer-mode)

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x08` | `0x00` | `0x00` | Multiplier output monitoring |
| 4-35 | `0x38` | `0x38` | `0x00` | `MUL[7:0]` | Lower byte of lane 0 product |

## Debug Mode: 0x9 (Control Signals)
**Related Specification**: [Logic Analyzer Mode - Selector 0x9](docs/info.md#1-real-time-observability-logic-analyzer-mode)

**Mapping**: `[7]` ena, `[6]` strobe, `[5]` acc_en, `[4]` acc_clear.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x09` | `0x00` | `0x00` | Control signals monitoring |
| 1-2 | `0x7F` | `0x00` | `0x00` | `0xD0` | `ena=1, strobe=1, acc_clear=1` |
| 4-34 | `0x38` | `0x38` | `0x00` | `0xE0` | `ena=1, strobe=1, acc_en=1` |
