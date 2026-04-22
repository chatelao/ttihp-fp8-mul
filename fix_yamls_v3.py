import yaml
import struct
import os
import sys

# Add test dir to path to import the actual model
sys.path.append('test')
from test import decode_format, align_product_model, fixed_to_float_model

def process_yaml(filename):
    print(f"Processing {filename}...")
    with open(filename, 'r') as f:
        cases = yaml.safe_load(f)

    for case in cases:
        inputs = case['inputs']
        a_els = inputs['a_elements']
        b_els = inputs.get('b_elements', a_els)
        fmt_a = inputs['format_a']
        fmt_b = inputs.get('format_b', fmt_a)
        scale_a = inputs.get('scale_a', 127)
        scale_b = inputs.get('scale_b', 127)
        round_mode = inputs.get('round_mode', 0)
        overflow_wrap = inputs.get('overflow_mode', 0)

        # We need to replicate the run_mac_test logic exactly
        acc_width = 40
        frac_bits = 16
        expected_acc = 0

        # Element loop
        for a, b in zip(a_els, b_els):
            prod = align_product_model(a, b, fmt_a, fmt_b, round_mode, overflow_wrap, aligner_width=40)

            mask = (1 << acc_width) - 1
            acc_masked = expected_acc & mask
            prod_masked = prod & mask
            sum_masked = (acc_masked + prod_masked) & mask

            s_acc = (acc_masked >> (acc_width - 1)) & 1
            s_prod = (prod_masked >> (acc_width - 1)) & 1
            s_res = (sum_masked >> (acc_width - 1)) & 1

            if not overflow_wrap and (s_acc == s_prod) and (s_acc != s_res):
                expected_acc_raw = (1 << (acc_width - 1)) if s_acc == 1 else (1 << (acc_width - 1)) - 1
            else:
                expected_acc_raw = sum_masked

            if expected_acc_raw & (1 << (acc_width - 1)):
                expected_acc = expected_acc_raw - (1 << acc_width)
            else:
                expected_acc = expected_acc_raw

        # F2F logic
        shared_exp = scale_a + scale_b - 254
        # Assuming no NaNs/Infs for standard YAML cases unless specified
        res = fixed_to_float_model(expected_acc, shared_exp, frac_bits)

        # Convert to signed 32-bit int for YAML
        if res & 0x80000000:
            res -= 0x100000000

        case['expected_output'] = res

    with open(filename, 'w') as f:
        yaml.dump(cases, f, sort_keys=False)

yaml_files = [
    'test/TEST_MX_E2E.yaml',
    'test/TEST_MX_FP4.yaml',
    'test/TEST_MIN_MAX_ZERO.yaml',
    'test/TEST_MXPLUS.yaml'
]

for yf in yaml_files:
    if os.path.exists(yf):
        process_yaml(yf)
