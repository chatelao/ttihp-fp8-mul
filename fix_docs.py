with open('docs/test.md', 'r') as f:
    lines = f.readlines()

# Sequence 4 starts at line 61 (index 60)
# Sequence 5 starts at line 79 (index 78)
# Sequence 6 starts at line 96 (index 95)

new_ts4 = [
    "### Test Sequence 4: Vector Packing (FP4 E2M1) - Standard Protocol\n",
    "- **Description**: 32 pairs of FP4 (E2M1) using Packed Mode (2 elements per byte), covering all 16 possible values twice.\n",
    "- **Expected Result**: $\sum_{i=0}^{15} 2 \\times (V_i \\times V_i) = 274.0 \\rightarrow$ `0x00011200`.\n",
    "\n",
    "| Cycle | `ui_in` (FP4)| `uio_in` (FP4) | `uio_out` | `uo_out` | Description |\n",
    "|:---:|:---:|:---:|:---:|:---:|---|\n",
    "| 0 | `0x00` | `0x40` | `0x00` | `0x00` | Packed Mode Enabled (`uio_in[6]=1`) |\n",
    "| 1 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale A = 1.0, Format A = E2M1 |\n",
    "| 2 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale B = 1.0, Format B = E2M1 |\n",
    "| 3-10 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Stream values 0x0 to 0xF (0x10, 0x32, ..., 0xFE) |\n",
    "| 11-18 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Repeat values 0x0 to 0xF |\n",
    "| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |\n",
    "| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |\n",
    "| 21-24 | - | - | `0x00` | `Result` | **Result**: `0x00`, `0x01`, `0x12`, `0x00` |\n",
    "\n",
    "---\n",
    "\n"
]

new_ts5 = [
    "### Test Sequence 5: FP4 Fast Lane - Short Protocol\n",
    "- **Description**: This test case uses the Short Protocol and Packed Mode for 32 pairs of FP4 (E2M1) elements, covering all 16 values twice.\n",
    "- **Expected Result**: `0x00011200`.\n",
    "\n",
    "| Cycle | `ui_in`  (Dual E2M1) | `uio_in`  (Dual E2M1) | `uio_out` | `uo_out` | Description |\n",
    "|:---:|:---:|:---:|:---:|:---:|---|\n",
    "| 0 | `0x80` | `0x44` | `0x00` | `0x00` | Short Start, Packed Mode, FP4 (`0x80`, `0x44`) |\n",
    "| 3-10 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Stream values 0x0 to 0xF (0x10, 0x32, ..., 0xFE) |\n",
    "| 11-18 | `0x10...0xFE` | `0x10...0xFE` | `0x00` | `0x00` | Repeat values 0x0 to 0xF |\n",
    "| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |\n",
    "| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |\n",
    "| 21 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 3 (`0x00`) |\n",
    "| 22 | `0x00` | `0x00` | `0x00` | `0x01` | Output Result Byte 2 (`0x01`) |\n",
    "| 23 | `0x00` | `0x00` | `0x00` | `0x12` | Output Result Byte 1 (`0x12`) |\n",
    "| 24 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 0 (`0x00`) |\n",
    "\n",
    "---\n",
    "\n"
]

final_lines = lines[:60] + new_ts4 + new_ts5 + lines[95:]

with open('docs/test.md', 'w') as f:
    f.writelines(final_lines)
