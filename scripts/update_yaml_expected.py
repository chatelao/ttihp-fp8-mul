import yaml
import os
import struct
import sys

# Import functions from test.py
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from test import decode_format, align_product_model, align_model

def to_f32_bits(val_fixed, shared_exp_val, sign_bit, nan, inf_p, inf_n):
    if nan or (inf_p and inf_n): return 0x7FC00000
    if inf_p: return 0x7F800000
    if inf_n: return 0xFF800000
    if val_fixed == 0: return 0x00000000

    val_float = (abs(val_fixed) / 256.0) * (2.0 ** shared_exp_val)
    if sign_bit: val_float = -val_float

    try:
        packed = struct.pack('>f', val_float)
        bits = struct.unpack('>I', packed)[0]
        if (bits & 0x7F800000) == 0 and (bits & 0x007FFFFF) != 0:
            return 0x00000000 if not sign_bit else 0x80000000
        return bits
    except OverflowError:
        return 0x7F800000 if not sign_bit else 0xFF800000

def update_yaml(filename):
    print(f"Updating {filename}...")
    with open(filename, 'r') as f:
        cases = yaml.safe_load(f)

    if not cases: return

    for case in cases:
        inputs = case['inputs']
        fmt_a = inputs['format_a']
        fmt_b = inputs.get('format_b', fmt_a)
        a_elements = inputs['a_elements']
        b_elements = inputs['b_elements']
        scale_a = inputs.get('scale_a', 127)
        scale_b = inputs.get('scale_b', 127)
        round_mode = inputs.get('round_mode', 0)
        overflow_wrap = inputs.get('overflow_mode', 0)
        bm_index_a = inputs.get('bm_index_a', 0)
        bm_index_b = inputs.get('bm_index_b', 0)
        nbm_offset_a = inputs.get('nbm_offset_a', 0)
        nbm_offset_b = inputs.get('nbm_offset_b', 0)
        mx_plus_mode = inputs.get('mx_plus_mode', 0)
        lns_mode = inputs.get('lns_mode', 0)

        expected_acc = 0
        nan_sticky = (scale_a == 0xFF or scale_b == 0xFF)
        inf_pos_sticky = False
        inf_neg_sticky = False

        for i, (a, b) in enumerate(zip(a_elements, b_elements)):
            is_bm_a_cur = (i == bm_index_a)
            is_bm_b_cur = (i == bm_index_b)

            # Use fixed widths from Full variant for model calculation
            sa, ea, ma, ba, inta, nana, infa = decode_format(a, fmt_a, is_bm_a_cur, mx_plus_mode)
            sb, eb, mb, bb, intb, nanb, infb = decode_format(b, fmt_b, is_bm_b_cur, mx_plus_mode)

            is_zero_a = (not inta and ea == 0 and (ma & 0x7) == 0) or (inta and a == 0)
            is_zero_b = (not intb and eb == 0 and (mb & 0x7) == 0) or (intb and b == 0)
            nan_el = nana or nanb or (infa and is_zero_b) or (infb and is_zero_a)
            inf_el = (infa or infb) and not nan_el
            sign_el = sa ^ sb

            if nan_el: nan_sticky = True
            if inf_el:
                if sign_el: inf_neg_sticky = True
                else:      inf_pos_sticky = True

            prod = align_product_model(a, b, fmt_a, fmt_b, round_mode, overflow_wrap,
                                       is_bm_a=is_bm_a_cur, is_bm_b=is_bm_b_cur, support_mxplus=mx_plus_mode,
                                       offset_a=nbm_offset_a if mx_plus_mode else 0,
                                       offset_b=nbm_offset_b if mx_plus_mode else 0,
                                       lns_mode=lns_mode, aligner_width=40)

            # 40-bit accumulation
            mask = (1 << 40) - 1
            acc_masked = expected_acc & mask
            prod_masked = prod & mask
            sum_masked = (acc_masked + prod_masked) & mask

            s_acc = (acc_masked >> 39) & 1
            s_prod = (prod_masked >> 39) & 1
            s_res = (sum_masked >> 39) & 1

            if not overflow_wrap and (s_acc == s_prod) and (s_acc != s_res):
                expected_acc_raw = (1 << 39) if s_acc == 1 else (1 << 39) - 1
            else:
                expected_acc_raw = sum_masked

            if expected_acc_raw & (1 << 39):
                expected_acc = expected_acc_raw - (1 << 40)
            else:
                expected_acc = expected_acc_raw

        shared_exp = scale_a + scale_b - 254
        expected_bits = to_f32_bits(expected_acc, shared_exp, 1 if expected_acc < 0 else 0, nan_sticky, inf_pos_sticky, inf_neg_sticky)

        if expected_bits & 0x80000000:
            case['expected_output'] = expected_bits - 0x100000000
        else:
            case['expected_output'] = expected_bits

    with open(filename, 'w') as f:
        yaml.dump(cases, f, default_flow_style=False, sort_keys=False)

if __name__ == "__main__":
    yaml_files = ["test/TEST_MX_E2E.yaml", "test/TEST_MX_FP4.yaml", "test/TEST_MIN_MAX_ZERO.yaml", "test/TEST_MXPLUS.yaml"]
    for f in yaml_files:
        if os.path.exists(f):
            update_yaml(f)
