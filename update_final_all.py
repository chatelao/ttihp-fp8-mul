import os

# 1. Update docs/test.md
doc_path = 'docs/test.md'
if os.path.exists(doc_path):
    with open(doc_path, 'r') as f:
        content = f.read()
    idx4 = content.find('### Test Sequence 4:')
    idx6 = content.find('### Test Sequence 6:')
    if idx4 != -1 and idx6 != -1:
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
        ts4_new = f"""### Test Sequence 4: Vector Packing (FP4 E2M1) - Standard Protocol
- **Description**: 32 pairs of FP4 (E2M1) using Packed Mode (2 elements per byte), covering all 16 possible values twice.
- **Expected Result**: $\\sum_{{i=0}}^{{15}} 2 \\times (V_i \\times V_i) = 274.0 \\rightarrow$ `0x00011200`.

| Cycle | `ui_in` (FP4) | `uio_in` (FP4) | `uio_out` | `uo_out` | Description |
|:---:|:---:|:---:|:---:|:---:|---|
| 0 | `0x00` | `0x40` | `0x00` | `0x00` | Packed Mode Enabled (`uio_in[6]=1`) |
| 1 | `0x7F` | `0x04` | `0x00" | `0x00` | Scale A = 1.0, Format A = E2M1 |
| 2 | `0x7F` | `0x04` | `0x00` | `0x00` | Scale B = 1.0, Format B = E2M1 |
{get_fp4_rows(3)}{get_fp4_rows(11, repeat=True)}| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
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
{get_fp4_rows(3)}{get_fp4_rows(11, repeat=True)}| 19 | `0x00` | `0x00` | `0x00` | `0x00` | Pipeline Flush |
| 20 | `0x00` | `0x00` | `0x00` | `0x00` | Internal Result Capture |
| 21 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 3 (`0x00`) |
| 22 | `0x00` | `0x00` | `0x00` | `0x01` | Output Result Byte 2 (`0x01`) |
| 23 | `0x00` | `0x00` | `0x00` | `0x12` | Output Result Byte 1 (`0x12`) |
| 24 | `0x00` | `0x00` | `0x00` | `0x00` | Output Result Byte 0 (`0x00`) |

---
"""
        new_content = content[:idx4] + ts4_new + content[idx6:]
        with open(doc_path, 'w') as f:
            f.write(new_content)

# 2. Update test/TEST_MX_FP4.yaml
yaml_path = 'test/TEST_MX_FP4.yaml'
if os.path.exists(yaml_path):
    with open(yaml_path, 'a') as f:
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
    a_elements: [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]
    b_elements: [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]
  expected_output: 70144
""")

# 3. Update test/test.py
test_py_path = 'test/test.py'
if os.path.exists(test_py_path):
    with open(test_py_path, 'r') as f:
        test_py = f.read()
    if '@cocotb.test()' in test_py and 'async def test_mxfp4_full_range(dut):' not in test_py:
        test_py += """
@cocotb.test()
async def test_mxfp4_full_range(dut):
    # Check if vector packing is supported
    support_packing = get_param(getattr(dut.user_project, "SUPPORT_VECTOR_PACKING", None), "SUPPORT_VECTOR_PACKING", 0)
    if not support_packing:
        dut._log.info("Skipping Full Range Packed FP4 Test (SUPPORT_VECTOR_PACKING=0)")
        return

    dut._log.info("Start Full Range Packed FP4 Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = list(range(16)) * 2
    b_elements = list(range(16)) * 2
    # Expected: 2 * sum(v*v for v in range(16)) = 2 * 137.0 = 274.0.
    # Fixed point (8 bits): 274.0 * 256 = 70144
    await run_mac_test(dut, 4, 4, a_elements, b_elements, packed_mode=1)
"""
        with open(test_py_path, 'w') as f:
            f.write(test_py)
