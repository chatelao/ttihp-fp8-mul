# Streaming MAC Unit Test Sequences

This document provides 5 test sequences for the OCP MXFP8 Streaming MAC Unit. Each sequence follows the 41-cycle streaming protocol.

## Test Sequence 1: Standard FP8 E4M3 Dot Product
**Description**: 32 pairs of 1.0 (E4M3) with 1.0 Shared Scales.
**Expected Result**: $32 \times (1.0 \times 1.0) = 32.0 \rightarrow$ `0x00002000` (Fixed-point, 8 fractional bits).

| Cycle | `ui_in` | `uio_in` | Description |
|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x00` | Standard Start, Normal Mode, TRN, SAT |
| 1 | `0x7F` | `0x00` | Scale A = 1.0, Format A = E4M3 |
| 2 | `0x7F` | `0x00` | Scale B = 1.0, Format B = E4M3 |
| 3-34 | `0x38` | `0x38` | Elements A=1.0, B=1.0 |
| 35-36 | `0x00` | `0x00` | Pipeline Flush |
| 37-40 | - | - | **Result**: `0x00`, `0x00`, `0x20`, `0x00` |

---

## Test Sequence 2: Shared Scaling (2.0x)
**Description**: 32 pairs of 1.0 (E4M3) with Scale A = 2.0 and Scale B = 1.0.
**Expected Result**: $32 \times (1.0 \times 1.0) \times 2.0 = 64.0 \rightarrow$ `0x00004000`.

| Cycle | `ui_in` | `uio_in` | Description |
|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x00` | Standard Start |
| 1 | `0x80` | `0x00` | Scale A = 2.0 ($2^{128-127}$), Format A = E4M3 |
| 2 | `0x7F` | `0x00` | Scale B = 1.0, Format B = E4M3 |
| 3-34 | `0x38` | `0x38` | Elements A=1.0, B=1.0 |
| 35-36 | `0x00` | `0x00` | Pipeline Flush |
| 37-40 | - | - | **Result**: `0x00`, `0x00`, `0x40`, `0x00` |

---

## Test Sequence 3: Mixed Precision (E4M3 x E5M2)
**Description**: 32 pairs of 1.0 (E4M3) multiplied by 1.0 (E5M2).
**Expected Result**: $32 \times (1.0 \times 1.0) = 32.0 \rightarrow$ `0x00002000`.

| Cycle | `ui_in` | `uio_in` | Description |
|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x00` | Standard Start |
| 1 | `0x7F` | `0x00` | Scale A = 1.0, Format A = E4M3 |
| 2 | `0x7F` | `0x01` | Scale B = 1.0, Format B = E5M2 |
| 3-34 | `0x38` | `0x3C` | Elements A=1.0 (E4M3), B=1.0 (E5M2) |
| 35-36 | `0x00` | `0x00` | Pipeline Flush |
| 37-40 | - | - | **Result**: `0x00`, `0x00`, `0x20`, `0x00` |

---

## Test Sequence 4: Vector Packing (FP4 E2M1)
**Description**: 32 pairs of 1.0 (E2M1) using Packed Mode (2 elements per byte).
**Expected Result**: $32 \times (1.0 \times 1.0) = 32.0 \rightarrow$ `0x00002000`.

| Cycle | `ui_in` | `uio_in` | Description |
|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x40` | Packed Mode Enabled (`uio_in[6]=1`) |
| 1 | `0x7F` | `0x04` | Scale A = 1.0, Format A = E2M1 |
| 2 | `0x7F` | `0x04` | Scale B = 1.0, Format B = E2M1 |
| 3-18 | `0x22` | `0x22` | Packed Elements (High/Low nibble = 1.0 = `0x2`) |
| 19-20 | `0x00` | `0x00` | Pipeline Flush |
| 21-24 | - | - | **Result**: `0x00`, `0x00`, `0x20`, `0x00` |

---

## Test Sequence 5: OCP MX+ (Extended Mantissa)
**Description**: 1 pair of 1.0 (BM elements) and 31 pairs of 0.0. BM Index 0.
**Expected Result**: $1.0 \times 1.0 = 1.0 \rightarrow$ `0x00000100`.
*Note: In MX+ mode, a BM element with bits `0x00` represents 1.0 (scaled).*

| Cycle | `ui_in` | `uio_in` | Description |
|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x80` | MX+ Enabled (`uio_in[7]=1`) |
| 1 | `0x7F` | `0x00` | Scale A = 1.0, Format A = E4M3, BM Index A = 0 |
| 2 | `0x7F` | `0x00` | Scale B = 1.0, Format B = E4M3, BM Index B = 0 |
| 3 | `0x00` | `0x00` | BM Elements (Value = 1.0) |
| 4-34 | `0x00` | `0x00` | Non-BM Elements (Value = 0.0) |
| 35-36 | `0x00` | `0x00` | Pipeline Flush |
| 37-40 | - | - | **Result**: `0x00`, `0x00`, `0x01`, `0x00` |
