import yaml
import os
import sys
import struct

# Add test directory to path
sys.path.append(os.path.join(os.getcwd(), 'test'))
from test import decode_format, to_f32_bits, align_product_model

def process_case(case):
    inputs = case['inputs']
    fa, fb = inputs['format_a'], inputs.get('format_b', inputs['format_a'])
    ae, be = inputs['a_elements'], inputs['b_elements']
    sa, sb = inputs.get('scale_a', 127), inputs.get('scale_b', 127)
    mx = inputs.get('mx_plus_mode', 0)
    ba, bb = inputs.get('bm_index_a', 0), inputs.get('bm_index_b', 0)
    oa, ob = inputs.get('nbm_offset_a', 0), inputs.get('nbm_offset_b', 0)
    lns = inputs.get('lns_mode', 0)

    acc = 0
    for i, (a, b) in enumerate(zip(ae, be)):
        prod = align_product_model(a, b, fa, fb, 0, 0, mx and i==ba, mx and i==bb, mx, oa if mx else 0, ob if mx else 0, lns, 40)
        acc += prod
        if i == 0 or i == 31:
            print(f"Index {i}: a={a}, b={b}, is_bm_a={mx and i==ba}, is_bm_b={mx and i==bb}, prod={prod}")

    print(f"Final Acc: {acc}")
    ebits = to_f32_bits(acc, sa + sb - 254, acc < 0, False, False, False, 40)
    print(f"Float32 Bits: {hex(ebits)}")

filename = "test/TEST_MXPLUS.yaml"
with open(filename, 'r') as f: cases = yaml.safe_load(f)
print("--- Case 1 ---")
process_case(cases[0])
