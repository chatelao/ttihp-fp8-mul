import re

def get_fp4_rows(start_cycle, repeat=False):
    rows = []
    # 16 values: 0x0 to 0xF. Packed into 8 bytes.
    # Elements: (0, 1), (2, 3), ..., (14, 15)
    # Packed byte: (high << 4) | low. So (0x10, 0x32, ..., 0xFE)
    for i in range(8):
        cycle = start_cycle + i
        low = 2 * i
        high = 2 * i + 1
        val = (high << 4) | low
        ui_in = f"0x{val:02X}"
        desc = f"{'Repeat' if repeat else 'Stream'} elements {low} and {high} (Packed: {ui_in})"
        rows.append(f"| {cycle} | `{ui_in}` | `{ui_in}` | `0x00` | `0x00` | {desc} |\n")
    return rows

# Read the clean file
with open('docs/test.md', 'r') as f:
    content = f.read()

# Replace Sequence 4 and 5
ts4_5_replacement = """### Test Sequence 4: Vector Packing (FP4 E2M1) - Standard Protocol
- **Description**: 32 pairs of FP4 (E2M1) using Packed Mode (2 elements per byte), covering all 16 possible values twice.
- **Expected Result**: $\\sum_{i=0}^{15} 2 \\times (V_i \\times V_i) = 274.0 \\rightarrow$ `0x00011200`.

| Cycle | `ui_in` (FP4) | `uio_in` (FP4) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x40` | `0x00` | `0x00` | Packed Mode Enabled (`uio_in[6]=1`) |
| 1 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale A = 1.0, Format A = E2M1 |
| 2 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale B = 1.0, Format B = E2M1 |
""" + "".join(get_fp4_rows(3)) + "".join(get_fp4_rows(11, repeat=True)) + """| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 21 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 3 (`0x00`) |
| 22 | `0x00` | `0x00` | `0x00` | `0x01` | Output Result Byte 2 (`0x01`) |
| 23 | `0x00` | `0x00` | `0x00` | `0x12` | Output Result Byte 1 (`0x12`) |
| 24 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 0 (`0x00`) |

---

### Test Sequence 5: FP4 Fast Lane - Short Protocol
- **Description**: This test case uses the Short Protocol and Packed Mode for 32 pairs of FP4 (E2M1) elements, covering all 16 values twice.
- **Expected Result**: `0x00011200`.

| Cycle | `ui_in`  (Dual E2M1) | `uio_in`  (Dual E2M1) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x80` | `0x44` | `0x00` | `0x00` | Short Start, Packed Mode, FP4 (`0x80`, `0x44`) |
""" + "".join(get_fp4_rows(3)) + "".join(get_fp4_rows(11, repeat=True)) + """| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 21 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 3 (`0x00`) |
| 22 | `0x00` | `0x00` | `0x00` | `0x01` | Output Result Byte 2 (`0x01`) |
| 23 | `0x00` | `0x00` | `0x00` | `0x12` | Output Result Byte 1 (`0x12`) |
| 24 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 0 (`0x00`) |

---
"""

# Perform replacement
content = re.sub(r'### Test Sequence 4: Vector Packing.*?### Test Sequence 6: OCP MX\+', ts4_5_replacement + "### Test Sequence 6: OCP MX+", content, flags=re.DOTALL)

with open('docs/test.md', 'w') as f:
    f.write(content)

# Update YAML
with open('test/TEST_MX_FP4.yaml', 'a') as f:
    f.write("""
- test_case: 7
  comment: "Full range FP4 (E2M1) multiplication. All 16 values squared and summed twice. Expected: 274.0."
  inputs:
    format_a: 4
    format_b: 4
    scale_a: 127
    scale_b: 127
    round_mode: 0
    overflow_mode: 0
    packed_mode: 1
    a_elements: [0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF, 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF]
    b_elements: [0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF, 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF]
  expected_output: 70144
""")
