import sys

with open('docs/test.md', 'r') as f:
    content = f.read()

old_ts4 = """### Test Sequence 4: Vector Packing (FP4 E2M1) - Standard Protocol
- **Description**: 32 pairs of 1.0 (E2M1) using Packed Mode (2 elements per byte).
- **Expected Result**: $32 \\times (1.0 \\times 1.0) = 32.0 \\rightarrow$ `0x00002000`.

| Cycle | `ui_in` (FP4)| `uio_in` (FP4) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x40` | `0x00` | `0x00` | Packed Mode Enabled (`uio_in[6]=1`) |
| 1 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale A = 1.0, Format A = E2M1 |
| 2 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale B = 1.0, Format B = E2M1 |
| 3-18 | `0x22` | `0x22` | `0x00` | `0x00` | Packed Elements (High/Low nibble = 1.0 = `0x2`) |
| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 21-24 | - | - | `0x00` | `Result` | **Result**: `0x00`, `0x00`, `0x20`, `0x00` |"""

new_ts4 = """### Test Sequence 4: Vector Packing (FP4 E2M1) - Standard Protocol
- **Description**: 32 pairs of FP4 (E2M1) using Packed Mode (2 elements per byte), covering all 16 possible values twice.
- **Expected Result**: $\sum_{i=0}^{15} 2 \\times (V_i \\times V_i) = 274.0 \\rightarrow$ `0x00011200`.

| Cycle | `ui_in` (FP4)| `uio_in` (FP4) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x40` | `0x00` | `0x00` | Packed Mode Enabled (`uio_in[6]=1`) |
| 1 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale A = 1.0, Format A = E2M1 |
| 2 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale B = 1.0, Format B = E2M1 |
| 3-10 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Stream values 0x0 to 0xF (0x10, 0x32, ..., 0xFE) |
| 11-18 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Repeat values 0x0 to 0xF |
| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 21-24 | - | - | `0x00` | `Result` | **Result**: `0x00`, `0x01`, `0x12`, `0x00` |"""

old_ts5 = """### Test Sequence 5: FP4 Fast Lane - Short Protocol
- **Description**: This test case uses the Short Protocol and Packed Mode for 32 pairs of 1.0 (E2M1) elements.
- **Expected Result**: `0x00002000`.

| Cycle | `ui_in`  (Dual E2M1) | `uio_in`  (Dual E2M1) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x80` | `0x44` | `0x00` | `0x00` | Short Start, Packed Mode, FP4 (`0x80`, `0x44`) |
| 3-18 | `0x22` | `0x22` | `0x00` | `0x00` | Stream 16 bytes of packed 1.0 (FP4 1.0 = `0x2`) |
| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 21 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 3 (`0x00`) |
| 22 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 2 (`0x00`) |
| 23 | `0x00` | `0x00` | `0x00` | `0x20` | Output Result Byte 1 (`0x20`) |
| 24 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 0 (`0x00`) |"""

new_ts5 = """### Test Sequence 5: FP4 Fast Lane - Short Protocol
- **Description**: This test case uses the Short Protocol and Packed Mode for 32 pairs of FP4 (E2M1) elements, covering all 16 values twice.
- **Expected Result**: `0x00011200`.

| Cycle | `ui_in`  (Dual E2M1) | `uio_in`  (Dual E2M1) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x80` | `0x44` | `0x00` | `0x00` | Short Start, Packed Mode, FP4 (`0x80`, `0x44`) |
| 3-10 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Stream values 0x0 to 0xF (0x10, 0x32, ..., 0xFE) |
| 11-18 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Repeat values 0x0 to 0xF |
| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 21 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 3 (`0x00`) |
| 22 | `0x00` | `0x00` | `0x00` | `0x01` | Output Result Byte 2 (`0x01`) |
| 23 | `0x00` | `0x00` | `0x00` | `0x12` | Output Result Byte 1 (`0x12`) |
| 24 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 0 (`0x00`) |"""

if old_ts4 not in content:
    print("Could not find old_ts4")
else:
    content = content.replace(old_ts4, new_ts4)

if old_ts5 not in content:
    print("Could not find old_ts5")
else:
    content = content.replace(old_ts5, new_ts5)

with open('docs/test.md', 'w') as f:
    f.write(content)
