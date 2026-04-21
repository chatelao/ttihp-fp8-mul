import yaml
import struct
import os

def to_f32_bits(f):
    if f != f: return 0x7FC00000 # NaN
    if f == float('inf'): return 0x7F800000
    if f == float('-inf'): return 0xFF800000
    return struct.unpack('>I', struct.pack('>f', f))[0]

def update_yaml(filename):
    if not os.path.exists(filename):
        print(f"Skipping {filename}")
        return
    with open(filename, 'r') as f:
        cases = yaml.safe_load(f)
    if not cases: return
    for case in cases:
        if 'expected_output' in case and isinstance(case['expected_output'], int):
            old_expected = case['expected_output']
            # Old model: bit 8 = 1.0. So value = x / 256.0
            # Special case for NaN/Inf bit patterns if they were used (unlikely in old fixed point)
            if old_expected > 0x7F000000: # Probably already a bit pattern or special
                continue
            val = old_expected / 256.0
            new_expected = to_f32_bits(val)
            case['expected_output'] = new_expected
            # print(f"{filename} Case {case.get('test_case')}: {old_expected} -> 0x{new_expected:08X} ({val})")
    with open(filename, 'w') as f:
        yaml.dump(cases, f, default_flow_style=False)

if __name__ == "__main__":
    yaml_files = ['test/TEST_MX_E2E.yaml', 'test/TEST_MX_FP4.yaml', 'test/TEST_MIN_MAX_ZERO.yaml', 'test/TEST_MXPLUS.yaml']
    for yf in yaml_files:
        update_yaml(yf)
