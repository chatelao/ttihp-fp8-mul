with open('docs/test.md', 'r') as f:
    lines = f.readlines()

new_lines = []
skip = False
for line in lines:
    if line.startswith('### Test Sequence 4:'):
        new_lines.append('### Test Sequence 4: Vector Packing (FP4 E2M1) - Standard Protocol\n')
        new_lines.append('- **Description**: 32 pairs of FP4 (E2M1) using Packed Mode (2 elements per byte), covering all 16 possible values twice.\n')
        new_lines.append('- **Expected Result**: $\sum_{i=0}^{15} 2 \times (V_i \times V_i) = 274.0 \rightarrow$ `0x00011200`.\n')
        new_lines.append('\n')
        new_lines.append('| Cycle | `ui_in` (FP4)| `uio_in` (FP4) | `uio_out` | `uo_out` |\n')
        new_lines.append('|:---:|:---:|:---:|:---:|:---:|\n')
        new_lines.append('| 0 | `0x00` | `0x40` | `0x00` | `0x00` | Packed Mode Enabled (`uio_in[6]=1`) |\n')
        new_lines.append('| 1 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale A = 1.0, Format A = E2M1 |\n')
        new_lines.append('| 2 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale B = 1.0, Format B = E2M1 |\n')
        new_lines.append('| 3-10 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Stream values 0x0 to 0xF (0x10, 0x32, ..., 0xFE) |\n')
        new_lines.append('| 11-18 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Repeat values 0x0 to 0xF |\n')
        new_lines.append('| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |\n')
        new_lines.append('| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |\n')
        new_lines.append('| 21-24 | - | - | `0x00` | `Result` | **Result**: `0x00`, `0x01`, `0x12`, `0x00` |\n')
        skip = True
    elif line.startswith('### Test Sequence 5:'):
        new_lines.append('### Test Sequence 5: FP4 Fast Lane - Short Protocol\n')
        new_lines.append('- **Description**: This test case uses the Short Protocol and Packed Mode for 32 pairs of FP4 (E2M1) elements, covering all 16 values twice.\n')
        new_lines.append('- **Expected Result**: `0x00011200`.\n')
        new_lines.append('\n')
        new_lines.append('| Cycle | `ui_in`  (Dual E2M1) | `uio_in`  (Dual E2M1) | `uio_out` | `uo_out` | Description |\n')
        new_lines.append('|:---:|:---:|:---:|:---:|:---:|\n')
        new_lines.append('| 0 | `0x80` | `0x44` | `0x00` | `0x00` | Short Start, Packed Mode, FP4 (`0x80`, `0x44`) |\n')
        new_lines.append('| 3-10 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Stream values 0x0 to 0xF (0x10, 0x32, ..., 0xFE) |\n')
        new_lines.append('| 11-18 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Repeat values 0x0 to 0xF |\n')
        new_lines.append('| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |\n')
        new_lines.append('| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |\n')
        new_lines.append('| 21 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 3 (`0x00`) |\n')
        new_lines.append('| 22 | `0x00` | `0x00` | `0x00` | `0x01` | Output Result Byte 2 (`0x01`) |\n')
        new_lines.append('| 23 | `0x00` | `0x00` | `0x00` | `0x12` | Output Result Byte 1 (`0x12`) |\n')
        new_lines.append('| 24 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 0 (`0x00`) |\n')
        skip = True
    elif line.startswith('---') and skip:
        new_lines.append(line)
        skip = False
    elif not skip:
        new_lines.append(line)

with open('docs/test.md', 'w') as f:
    f.writelines(new_lines)
