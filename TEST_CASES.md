# OCP MXFP8 Streaming MAC Unit - Test Cases

This document details specific test sequences to verify the functional and debug capabilities of the MAC unit.

## FP8 Random Number (Standard Protocol)

This test case performs a dot product of 32 pairs of random FP8 E4M3 elements using the standard protocol and 1.0 shared scaling.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x00` | `0x00` | `0x00` | **Cycle 0**: Metadata Setup (TRN, SAT, E4M3, Standard Start) |
| 1 | `0x7F` | `0x00` | `0x00` | `0x00` | **Cycle 1**: Load Scale A = 1.0 |
| 2 | `0x7F` | `0x00` | `0x00` | `0x00` | **Cycle 2**: Load Scale B = 1.0 |
| 3 | `0x42` | `0x38` | `0x00` | `0x00` | **Cycle 3**: Element A[0], B[0] (Random Values) |
| 4 | `0x1A` | `0xCC` | `0x00` | `0x00` | **Cycle 4**: Element A[1], B[1] (Random Values) |
| ... | ... | ... | ... | ... | ... |
| 34 | `0x38` | `0x38` | `0x00` | `0x00` | **Cycle 34**: Element A[31], B[31] (Random Values) |
| 35 | `0x00` | `0x00` | `0x00` | `0x00` | **Cycle 35**: Pipeline Flush |
| 36 | `0x00` | `0x00` | `0x00` | `0x00` | **Cycle 36**: Internal Result Capture |
| 37 | `0x00` | `0x00` | `0x00` | `V[31:24]` | **Cycle 37**: Output Result MSB |
| 38 | `0x00` | `0x00` | `0x00` | `V[23:16]` | **Cycle 38**: Output Result Byte 2 |
| 39 | `0x00` | `0x00` | `0x00` | `V[15:8]`  | **Cycle 39**: Output Result Byte 1 |
| 40 | `0x00` | `0x00` | `0x00` | `V[7:0]`   | **Cycle 40**: Output Result LSB |

## FP4 Fast Lane Random Numbers (Short Protocol)

This test case uses the Short Protocol to skip scale loading and process 32 pairs of FP4 E2M1 elements packed into 16 bytes. It uses the previously latched scale values (assumed 1.0).

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x80` | `0x44` | `0x00` | `0x00` | **Cycle 0**: Short Start (`ui_in[7]=1`), Packed Mode (`uio_in[6]=1`), Format FP4 (`uio_in[2:0]=4`) |
| 3 | `0x21` | `0x22` | `0x00` | `0x00` | **Cycle 3**: Packed Elements A[1:0], B[1:0] |
| 4 | `0x23` | `0x12` | `0x00` | `0x00` | **Cycle 4**: Packed Elements A[3:2], B[3:2] |
| ... | ... | ... | ... | ... | ... |
| 18 | `0x22` | `0x22` | `0x00` | `0x00` | **Cycle 18**: Packed Elements A[31:30], B[31:30] |
| 19 | `0x00` | `0x00` | `0x00` | `0x00` | **Cycle 19**: Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | **Cycle 20**: Internal Result Capture |
| 21 | `0x00` | `0x00` | `0x00` | `V[31:24]` | **Cycle 21**: Output Result MSB |
| 22 | `0x00` | `0x00` | `0x00` | `V[23:16]` | **Cycle 22**: Output Result Byte 2 |
| 23 | `0x00` | `0x00` | `0x00` | `V[15:8]`  | **Cycle 23**: Output Result Byte 1 |
| 24 | `0x00` | `0x00` | `0x00` | `V[7:0]`   | **Cycle 24**: Output Result LSB |

## Debug Mode: 0x0 (Default)

Verifies that when debug mode is enabled with selector 0x0, `uo_out` remains 0x00 during the streaming phase.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x00` | `0x00` | `0x00` | **Cycle 0**: Debug Enable (`ui_in[6]=1`), Probe Selector 0x0 |
| 1-36 | - | - | `0x00` | `0x00` | **Stream Phase**: Output remains zero |

## Debug Mode: 0x1 (FSM State & Timing)

Verifies that `uo_out` correctly reflects the internal FSM state and logical cycle counter.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x01` | `0x00` | `0x00` | **Cycle 0**: Debug Enable, Probe Selector 0x1 |
| 1 | `0x7F` | `0x00` | `0x00` | `0x41` | **Cycle 1**: State LOAD_SCALE (01), Cycle 1 -> `0x41` |
| 2 | `0x7F` | `0x00` | `0x00` | `0x42` | **Cycle 2**: State LOAD_SCALE (01), Cycle 2 -> `0x42` |
| 3 | `0x38` | `0x38` | `0x00` | `0x83` | **Cycle 3**: State STREAM (10), Cycle 3 -> `0x83` |
| 34 | `0x38` | `0x38` | `0x00` | `0xA2` | **Cycle 34**: State STREAM (10), Cycle 34 -> `0xA2` |

## Debug Mode: 0x2 (Exception Monitor)

Verifies that sticky exception flags (NaN, Inf) are visible on `uo_out`.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x02` | `0x00` | `0x00` | **Cycle 0**: Debug Enable, Probe Selector 0x2 |
| 3 | `0x7F` | `0x38` | `0x00` | `0x90` | **Cycle 3**: Element A is NaN (`0x7F`), `uo_out[7]` (nan_sticky) becomes 1 |

## Debug Mode: 0x3 (Accumulator [31:24])

Verifies real-time monitoring of the accumulator's most significant byte.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x03` | `0x00` | `0x00` | **Cycle 0**: Debug Enable, Probe Selector 0x3 |
| 3-34 | - | - | `0x00` | `ACC[31:24]` | **Stream Phase**: `uo_out` shows live MSB of accumulator |

## Debug Mode: 0x4 (Accumulator [23:16])

Verifies real-time monitoring of the accumulator's second byte.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x04` | `0x00` | `0x00` | **Cycle 0**: Debug Enable, Probe Selector 0x4 |
| 3-34 | - | - | `0x00` | `ACC[23:16]` | **Stream Phase**: `uo_out` shows live Byte 2 of accumulator |

## Debug Mode: 0x5 (Accumulator [15:8])

Verifies real-time monitoring of the accumulator's third byte.

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x05` | `0x00` | `0x00` | **Cycle 0**: Debug Enable, Probe Selector 0x5 |
| 3-34 | - | - | `0x00` | `ACC[15:8]` | **Stream Phase**: `uo_out` shows live Byte 1 of accumulator |

## Debug Mode: 0x6 (Accumulator [7:0])

Verifies real-time monitoring of the accumulator's least significant byte (fractional part).

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x06` | `0x00` | `0x00` | **Cycle 0**: Debug Enable, Probe Selector 0x6 |
| 3-34 | - | - | `0x00` | `ACC[7:0]` | **Stream Phase**: `uo_out` shows live LSB of accumulator |

## Debug Mode: 0x7 (Multiplier Lane 0 [15:8])

Verifies monitoring of the multiplier's upper output byte (exponent/MSB of product).

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x07` | `0x00` | `0x00` | **Cycle 0**: Debug Enable, Probe Selector 0x7 |
| 4-35 | - | - | `0x00` | `MUL[15:8]` | **Stream Phase**: `uo_out` shows pipelined multiplier output MSB |

## Debug Mode: 0x8 (Multiplier Lane 0 [7:0])

Verifies monitoring of the multiplier's lower output byte (mantissa product).

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x08` | `0x00` | `0x00` | **Cycle 0**: Debug Enable, Probe Selector 0x8 |
| 4-35 | - | - | `0x00` | `MUL[7:0]` | **Stream Phase**: `uo_out` shows pipelined multiplier output LSB |

## Debug Mode: 0x9 (Control Signals)

Verifies monitoring of internal control signals (enable, strobe, etc.).

| Cycle | `ui_in` | `uio_in` | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x40` | `0x09` | `0x00` | `0x00` | **Cycle 0**: Debug Enable, Probe Selector 0x9 |
| 3-34 | - | - | `0x00` | `CTRL` | **Stream Phase**: `uo_out` shows internal control status bits |
