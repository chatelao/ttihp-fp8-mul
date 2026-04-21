import yaml
import struct

def decode_format(bits, format_val, is_bm=False, support_mxplus=False):
    nan = False
    inf = False
    if format_val == 0: # E4M3
        sign = (bits >> 7) & 1
        bias = 7
        if is_bm and support_mxplus:
            exp = 11
            mant = (1 << 7) | (bits & 0x7F)
        else:
            exp_field = (bits >> 3) & 0xF
            mant_field = (bits & 0x7)
            is_subnormal = (exp_field == 0 and mant_field != 0)
            exp = 1 if is_subnormal else exp_field
            implicit_bit = 0 if (exp_field == 0) else 1
            mant = (implicit_bit << 3) | mant_field
            if (bits & 0x7F) == 0x7F: nan = True
        return sign, exp, mant, bias, False, nan, inf
    elif format_val == 1: # E5M2
        sign = (bits >> 7) & 1
        bias = 15
        if is_bm and support_mxplus:
            exp = 26
            mant = (1 << 7) | (bits & 0x7F)
        else:
            exp_field = (bits >> 2) & 0x1F
            mant_field = (bits & 0x3)
            is_subnormal = (exp_field == 0 and mant_field != 0)
            exp = 1 if is_subnormal else exp_field
            implicit_bit = 0 if (exp_field == 0) else 1
            mant = (implicit_bit << 2) | mant_field
            mant <<= 1
            if exp_field == 0x1F:
                if mant_field == 0: inf = True
                else: nan = True
        return sign, exp, mant, bias, False, nan, inf
    elif format_val == 2: # E3M2
        sign = (bits >> 5) & 1
        bias = 3
        if is_bm and support_mxplus:
            exp = 5
            mant = (1 << 5) | (bits & 0x1F)
        else:
            exp_field = (bits >> 2) & 0x7
            mant_field = (bits & 0x3)
            exp = 1 if (exp_field == 0 and mant_field != 0) else exp_field
            mant = (((0 if exp_field == 0 else 1) << 2) | mant_field) << 1
        return sign, exp, mant, bias, False, False, False
    elif format_val == 3: # E2M3
        sign = (bits >> 5) & 1
        bias = 1
        if is_bm and support_mxplus:
            exp = 1
            mant = (1 << 5) | (bits & 0x1F)
        else:
            exp_field = (bits >> 3) & 0x3
            mant_field = (bits & 0x7)
            exp = 1 if (exp_field == 0 and mant_field != 0) else exp_field
            mant = ((0 if exp_field == 0 else 1) << 3) | mant_field
        return sign, exp, mant, bias, False, False, False
    elif format_val == 4: # E2M1
        sign = (bits >> 3) & 1
        bias = 1
        if is_bm and support_mxplus:
            exp = 3
            mant = (1 << 3) | (bits & 0x7)
        else:
            exp_field = (bits >> 1) & 0x3
            mant_field = (bits & 0x1)
            exp = 1 if (exp_field == 0 and mant_field != 0) else exp_field
            mant = (((0 if exp_field == 0 else 1) << 1) | mant_field) << 2
        return sign, exp, mant, bias, False, False, False
    elif format_val == 5 or format_val == 6: # INT8
        sign = (bits >> 7) & 1
        val = bits if bits < 128 else bits - 256
        if format_val == 6 and val == -128: val = -127
        return sign, 0, abs(val), 3, True, False, False
    return 0,0,0,7,False,False,False

def to_f32_bits(val_fixed, shared_exp_val, sign_bit, nan, inf_p, inf_n, acc_width=40):
    if nan or (inf_p and inf_n): return 0x7FC00000
    if inf_p: return 0x7F800000
    if inf_n: return 0xFF800000
    if val_fixed == 0: return 0x80000000 if sign_bit else 0x00000000
    val_float = (abs(val_fixed) / (2.0**16)) * (2.0 ** shared_exp_val)
    if sign_bit: val_float = -val_float
    try:
        bits = struct.unpack('>I', struct.pack('>f', val_float))[0]
        if (bits & 0x7F800000) == 0: return 0x80000000 if sign_bit else 0x00000000
        return bits
    except: return 0x7F800000 if not sign_bit else 0xFF800000

def cast_to_signed(val, width):
    mask = (1 << width) - 1
    val = val & mask
    if val & (1 << (width - 1)):
        return val - (1 << width)
    return val

def align_model(prod, exp_sum, sign, round_mode=0, overflow_wrap=0, width=40):
    shift_amt = exp_sum + 3
    max_pos = (1 << (width - 1)) - 1
    min_neg = -(1 << (width - 1))

    huge = False
    if shift_amt >= 0:
        if shift_amt >= width:
            huge = (prod != 0)
            rounded = 0
        else:
            if shift_amt > 0 and (prod >> (width - shift_amt)) != 0:
                huge = True
            rounded = (prod << shift_amt) & ((1 << width) - 1)
    else:
        n = -shift_amt
        if n >= width:
            base = 0
            sticky = (prod != 0)
            round_bit = 0
        else:
            base = prod >> n
            round_bit = (prod >> (n - 1)) & 1 if n > 0 else 0
            sticky = (prod & ((1 << (n - 1)) - 1)) != 0 if n > 1 else 0

        do_inc = 0
        if round_mode == 3: # RNE
            if round_bit:
                if sticky or (base & 1):
                    do_inc = 1
        rounded = base + do_inc

    if sign:
        if not overflow_wrap and (huge or rounded > (1 << (width - 1))):
            res = min_neg
        else:
            res = cast_to_signed(-rounded, width)
    else:
        if not overflow_wrap and (huge or rounded > max_pos):
            res = max_pos
        else:
            res = cast_to_signed(rounded, width)

    return res

def process_file(filename):
    with open(filename, 'r') as f: cases = yaml.safe_load(f)
    for case in cases:
        inputs = case['inputs']
        fa, fb = inputs['format_a'], inputs.get('format_b', inputs['format_a'])
        ae, be = inputs['a_elements'], inputs['b_elements']
        sa, sb = inputs.get('scale_a', 127), inputs.get('scale_b', 127)
        mx = inputs.get('mx_plus_mode', 0)
        ba, bb = inputs.get('bm_index_a', 0), inputs.get('bm_index_b', 0)
        oa, ob = inputs.get('nbm_offset_a', 0), inputs.get('nbm_offset_b', 0)
        rm = inputs.get('round_mode', 0)
        ow = inputs.get('overflow_mode', 0)

        acc, ns, ip, in_ = 0, (sa==0xFF or sb==0xFF), False, False
        max_val_acc = (1 << 39) - 1
        min_val_acc = -(1 << 39)
        for i, (a, b) in enumerate(zip(ae, be)):
            s_a, e_a, m_a, b_a, i_a, n_a, f_a = decode_format(a, fa, mx and i==ba, mx)
            s_b, e_b, m_b, b_b, i_b, n_b, f_b = decode_format(b, fb, mx and i==bb, mx)
            is_z_a = (not i_a and e_a==0 and (m_a&7)==0) or (i_a and a==0)
            is_z_b = (not i_b and e_b==0 and (m_b&7)==0) or (i_b and b==0)
            if n_a or n_b or (f_a and is_z_b) or (f_b and is_z_a): ns=True
            elif f_a or f_b:
                if s_a^s_b: in_=True
                else: ip=True

            prod_val = m_a * m_b
            es = e_a + e_b - (b_a + b_b - 7) - (0 if (mx and i==ba) else oa if mx else 0) - (0 if (mx and i==bb) else ob if mx else 0)
            acc_term = align_model(prod_val, es, s_a^s_b, round_mode=rm, overflow_wrap=ow)

            full_sum = acc + acc_term
            if not ow:
                if full_sum > max_val_acc:
                    acc = max_val_acc
                elif full_sum < min_val_acc:
                    acc = min_val_acc
                else:
                    acc = full_sum
            else:
                acc = cast_to_signed(full_sum, 40)

        res_bits = to_f32_bits(acc, sa + sb - 254, acc < 0, ns, ip, in_)
        # print(f"Acc: {acc}, SharedExp: {sa+sb-254}, Sign: {acc<0}, Res: {hex(int(res_bits))}")
        case['expected_output'] = int(res_bits)

    with open(filename, 'w') as f: yaml.dump(cases, f, default_flow_style=False)

for f in ["test/TEST_MX_E2E.yaml", "test/TEST_MX_FP4.yaml", "test/TEST_MIN_MAX_ZERO.yaml", "test/TEST_MXPLUS.yaml"]:
    print(f"Updating {f}")
    process_file(f)
