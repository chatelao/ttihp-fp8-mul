import re

def get_fp4_rows(start_cycle, repeat=False):
    rows = []
    for i in range(8):
        cycle = start_cycle + i
        low = 2 * i
        high = 2 * i + 1
        val = (high << 4) | low
        ui_in = f"0x{val:02X}"
        desc = f"{'Repeat' if repeat else 'Stream'} elements {low} and {high} (Packed: {ui_in})"
        rows.append(f"| {cycle} | `{ui_in}` | `{ui_in}` | `0x00` | `0x00` | {desc} |")
    return "\n".join(rows) + "\n"

with open('docs/test.md', 'r') as f:
    content = f.read()

# 274.0 in Binary32 = 0x43890000
ts4_new = f"""### Test Sequence 4: Vector Packing (FP4 E2M1) - Standard Protocol
- **Description**: 32 pairs of FP4 (E2M1) using Packed Mode (2 elements per byte), covering all 16 possible values twice.
- **Expected Result**: $\\sum_{{i=0}}^{{15}} 2 \\times (V_i \\times V_i) = 274.0 \\rightarrow$ `0x43890000`.

| Cycle | `ui_in` (FP4) | `uio_in` (FP4) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x40` | `0x00` | `0x00` | Packed Mode Enabled (`uio_in[6]=1`) |
| 1 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale A = 1.0, Format A = E2M1 |
| 2 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale B = 1.0, Format B = E2M1 |
{get_fp4_rows(3)}{get_fp4_rows(11, repeat=True)}| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 21 | `0x00` | `0x00` | `0x00` | `0x43` | Output Result Byte 3 (`0x43`) |
| 22 | `0x00` | `0x00` | `0x00` | `0x89` | Output Result Byte 2 (`0x89`) |
| 23 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 1 (`0x00`) |
| 24 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 0 (`0x00`) |

---

### Test Sequence 5: FP4 Fast Lane - Short Protocol
- **Description**: This test case uses the Short Protocol and Packed Mode for 32 pairs of FP4 (E2M1) elements, covering all 16 values twice.
- **Expected Result**: `0x43890000`.

| Cycle | `ui_in`  (Dual E2M1) | `uio_in`  (Dual E2M1) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x80` | `0x44` | `0x00` | `0x00` | Short Start, Packed Mode, FP4 (`0x80`, `0x44`) |
{get_fp4_rows(3)}{get_fp4_rows(11, repeat=True)}| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00" | `0x00` | Internal Result Capture |
| 21 | `0x00` | `0x00` | `0x00` | `0x43` | Output Result Byte 3 (`0x43`) |
| 22 | `0x00` | `0x00` | `0x00` | `0x89` | Output Result Byte 2 (`0x89`) |
| 23 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 1 (`0x00`) |
| 24 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 0 (`0x00`) |

---
"""

# Escape backslashes for re.sub
ts4_escaped = ts4_new.replace('\\', '\\\\')

# Update Sequence 1 as well: 32.0 -> 0x42000000
new_content = re.sub(r'Expected Result.*`0x00002000`', 'Expected Result: `0x42000000` (32.0 in Binary32)', content)
new_content = re.sub(r'\| 37 \| `0x00` \| `0x00` \| `0x00` \| `0x00` \| Output Byte 3 \(MSB: `0x00`\) \|', '| 37 | `0x00` | `0x00` | `0x00` | `0x42` | Output Byte 3 (MSB: `0x42`) |', new_content)
new_content = re.sub(r'\| 38 \| `0x00` \| `0x00` \| `0x00` \| `0x00` \| Output Byte 2 \(`0x00`\) \|', '| 38 | `0x00` | `0x00` | `0x00` | `0x00` | Output Byte 2 (`0x00`) |', new_content)
new_content = re.sub(r'\| 39 \| `0x00` \| `0x00` \| `0x00` \| `0x20` \| Output Byte 1 \(`0x20`\) \|', '| 39 | `0x00` | `0x00` | `0x00` | `0x00` | Output Byte 1 (`0x00`) |', new_content)

# Replace Sequence 4/5
pattern = r'### Test Sequence 4: Vector Packing.*?### Test Sequence 6: OCP MX\+'
new_content = re.sub(pattern, ts4_escaped + '### Test Sequence 6: OCP MX+', new_content, flags=re.DOTALL)

with open('docs/test.md', 'w') as f:
    f.write(new_content)
