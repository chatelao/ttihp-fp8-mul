# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
import yaml
import os
import struct

def decode_format(bits, format_val, is_bm=False, support_mxplus=False,
                  support_e4m3=True, support_e5m2=True, support_mxfp6=True, support_mxfp4=True):
    nan = False
    inf = False
    if format_val == 0 and support_e4m3: # E4M3
        sign = (bits >> 7) & 1
        bias = 7
        is_int = False
        if is_bm and support_mxplus:
            exp = 11 # 15 - 4
            mant = (1 << 7) | (bits & 0x7F)
        else:
            exp_field = (bits >> 3) & 0xF
            mant_field = (bits & 0x7)
            is_subnormal = (exp_field == 0 and mant_field != 0)
            exp = 1 if is_subnormal else exp_field
            implicit_bit = 0 if (exp_field == 0) else 1
            mant = (implicit_bit << 3) | mant_field
            if bits & 0x7F == 0x7F: nan = True
        return sign, exp, mant, bias, is_int, nan, inf
    elif format_val == 1 and support_e5m2: # E5M2
        sign = (bits >> 7) & 1
        bias = 15
        is_int = False
        if is_bm and support_mxplus:
            exp = 26 # 30 - 4
            mant = (1 << 7) | (bits & 0x7F)
        else:
            exp_field = (bits >> 2) & 0x1F
            mant_field = (bits & 0x3)
            is_subnormal = (exp_field == 0 and mant_field != 0)
            exp = 1 if is_subnormal else exp_field
            implicit_bit = 0 if (exp_field == 0) else 1
            mant = (implicit_bit << 2) | mant_field
            mant <<= 1 # Align to 4 bits
            if exp_field == 0x1F:
                if mant_field == 0: inf = True
                else: nan = True
        return sign, exp, mant, bias, is_int, nan, inf
    elif format_val == 2 and support_mxfp6: # E3M2
        sign = (bits >> 5) & 1
        bias = 3
        is_int = False
        if is_bm and support_mxplus:
            exp = 5 # 7 - 2
            mant = (1 << 5) | (bits & 0x1F)
        else:
            exp_field = (bits >> 2) & 0x7
            mant_field = (bits & 0x3)
            is_subnormal = (exp_field == 0 and mant_field != 0)
            exp = 1 if is_subnormal else exp_field
            implicit_bit = 0 if (exp_field == 0) else 1
            mant = (implicit_bit << 2) | mant_field
            mant <<= 1 # Align to 4 bits
        return sign, exp, mant, bias, is_int, nan, inf
    elif format_val == 3 and support_mxfp6: # E2M3
        sign = (bits >> 5) & 1
        bias = 1
        is_int = False
        if is_bm and support_mxplus:
            exp = 1 # 3 - 2
            mant = (1 << 5) | (bits & 0x1F)
        else:
            exp_field = (bits >> 3) & 0x3
            mant_field = (bits & 0x7)
            is_subnormal = (exp_field == 0 and mant_field != 0)
            exp = 1 if is_subnormal else exp_field
            implicit_bit = 0 if (exp_field == 0) else 1
            mant = (implicit_bit << 3) | mant_field
        return sign, exp, mant, bias, is_int, nan, inf
    elif format_val == 4 and support_mxfp4: # E2M1
        sign = (bits >> 3) & 1
        bias = 1
        is_int = False
        if is_bm and support_mxplus:
            exp = 3 # 3 - 0
            mant = (1 << 3) | (bits & 0x7)
        else:
            exp_field = (bits >> 1) & 0x3
            mant_field = (bits & 0x1)
            is_subnormal = (exp_field == 0 and mant_field != 0)
            exp = 1 if is_subnormal else exp_field
            implicit_bit = 0 if (exp_field == 0) else 1
            mant = (implicit_bit << 1) | mant_field
            mant <<= 2 # Align to 4 bits
        return sign, exp, mant, bias, is_int, nan, inf
    elif format_val == 5: # INT8
        sign = (bits >> 7) & 1
        val = bits if bits < 128 else bits - 256
        mant = abs(val)
        exp = 0
        bias = 3
        is_int = True
    elif format_val == 6: # INT8_SYM
        sign = (bits >> 7) & 1
        val = bits if bits < 128 else bits - 256
        if val == -128: val = -127
        mant = abs(val)
        exp = 0
        bias = 3
        is_int = True
    else: # Default/Unsupported E4M3 fallthrough in HW
        sign = (bits >> 7) & 1
        exp_field = (bits >> 3) & 0xF
        mant_field = (bits & 0x7)
        is_subnormal = (exp_field == 0 and mant_field != 0)
        exp = 1 if is_subnormal else exp_field
        implicit_bit = 0 if (exp_field == 0) else 1
        mant = (implicit_bit << 3) | mant_field
        bias = 7
        is_int = False
        return sign, exp, mant, bias, is_int, False, False

    return sign, exp, mant, bias, is_int, nan, inf

def to_f32_bits(val_fixed, shared_exp_val, sign_bit, nan, inf_p, inf_n, acc_width=40):
    if nan or (inf_p and inf_n): return 0x7FC00000
    if inf_p: return 0x7F800000
    if inf_n: return 0xFF800000
    if val_fixed == 0: return 0x00000000

    # Internal bit 16 = 2^0 if width=40, else bit 8 = 2^0
    divisor = (2.0 ** 16) if acc_width == 40 else 256.0
    val_float = (abs(val_fixed) / divisor) * (2.0 ** shared_exp_val)
    if sign_bit: val_float = -val_float

    try:
        packed = struct.pack('>f', val_float)
        bits = struct.unpack('>I', packed)[0]
        # Hardware flushes subnormals to zero
        if (bits & 0x7F800000) == 0 and (bits & 0x007FFFFF) != 0:
            return 0x00000000 if not sign_bit else 0x80000000
        return bits
    except (OverflowError, struct.error):
        return 0x7F800000 if not sign_bit else 0xFF800000

def align_model(prod, exp_sum, sign, round_mode=0, overflow_wrap=0, width=40):
    # Default shift aligns bit 8 to 2^0 (legacy)
    shift_amt = exp_sum - 5

    # If using 40-bit internal accumulation, shift aligns bit 16 to 2^0
    if width == 40:
        shift_amt = exp_sum + 3

    WIDTH = width

    if shift_amt >= 0:
        if not overflow_wrap and shift_amt >= WIDTH:
            aligned = (1 << (WIDTH - 1)) - 1 if prod != 0 else 0
        else:
            aligned = prod << shift_amt
        sticky = 0
        shifted_out = 0
        base = aligned
        huge = False
        if shift_amt >= WIDTH:
            if prod != 0: huge = True
        elif shift_amt > 0:
            if (prod >> (WIDTH - shift_amt)) != 0: huge = True
    else:
        n = -shift_amt
        huge = False
        if n >= WIDTH:
            base = 0
            sticky = 1 if prod != 0 else 0
            shifted_out = prod
        else:
            base = prod >> n
            shifted_out = prod & ((1 << n) - 1)
            sticky = 1 if shifted_out != 0 else 0

        if round_mode == 0: # TRN
            aligned = base
        elif round_mode == 1: # CEL
            aligned = base + 1 if (not sign and (shifted_out != 0 or sticky)) else base
        elif round_mode == 2: # FLR
            aligned = base + 1 if (sign and (shifted_out != 0 or sticky)) else base
        elif round_mode == 3: # RNE
            half = 1 << (n - 1)
            if shifted_out > half:
                aligned = base + 1
            elif shifted_out < half:
                aligned = base
            else: # Tie
                aligned = base + 1 if (base & 1) else base
        else:
            aligned = base

    if sign:
        if not overflow_wrap and (huge or (aligned >> WIDTH) != 0 or ( (aligned & (1 << (WIDTH-1))) != 0 and (aligned & ((1 << (WIDTH-1)) - 1)) != 0 )):
            res = -(1 << (WIDTH - 1))
        else:
            res = -aligned
    else:
        if not overflow_wrap and (huge or (aligned >> (WIDTH-1)) != 0):
            res = (1 << (WIDTH - 1)) - 1
        else:
            res = aligned

    mask = (1 << WIDTH) - 1
    res_masked = res & mask
    if res_masked & (1 << (WIDTH - 1)):
        return res_masked - (1 << WIDTH)
    return res_masked

def get_param(dut, name, default=1):
    for obj in [getattr(dut, "user_project", None), dut]:
        if obj is None: continue
        try:
            handle = getattr(obj, name)
            return int(handle.value)
        except Exception:
            pass
    compile_args = " " + os.environ.get("COMPILE_ARGS", "")
    import re
    pattern = r"[\s\.]" + re.escape(name) + r"=(\d+)"
    match = re.search(pattern, compile_args)
    if match:
        return int(match.group(1))
    defaults = {
        "ALIGNER_WIDTH": 40,
        "ACCUMULATOR_WIDTH": 40,
        "SUPPORT_E4M3": 1,
        "SUPPORT_E5M2": 1,
        "SUPPORT_MXFP6": 1,
        "SUPPORT_MXFP4": 1,
        "SUPPORT_INT8": 1,
        "SUPPORT_PIPELINING": 1,
        "SUPPORT_ADV_ROUNDING": 1,
        "SUPPORT_MIXED_PRECISION": 1,
        "SUPPORT_VECTOR_PACKING": 1,
        "SUPPORT_INPUT_BUFFERING": 1,
        "SUPPORT_PACKED_SERIAL": 0,
        "SUPPORT_MX_PLUS": 1,
        "SUPPORT_SERIAL": 0,
        "SERIAL_K_FACTOR": 8,
        "ENABLE_SHARED_SCALING": 1,
        "USE_LNS_MUL": 0,
        "USE_LNS_MUL_PRECISE": 1,
        "SUPPORT_DEBUG": 1
    }
    return defaults.get(name, default)

def align_product_model(a_bits, b_bits, format_a, format_b, round_mode=0, overflow_wrap=0,
                        support_e4m3=1, support_e5m2=1, support_mxfp6=1, support_mxfp4=1, support_int8=1, use_lns=0, use_lns_precise=0, aligner_width=40,
                        is_bm_a=False, is_bm_b=False, support_mxplus=False, offset_a=0, offset_b=0, lns_mode=0):
    sa, ea, ma, ba, inta, nana, infa = decode_format(a_bits, format_a, is_bm_a, support_mxplus,
                                                    support_e4m3, support_e5m2, support_mxfp6, support_mxfp4)
    sb, eb, mb, bb, intb, nanb, infb = decode_format(b_bits, format_b, is_bm_b, support_mxplus,
                                                    support_e4m3, support_e5m2, support_mxfp6, support_mxfp4)
    sign = sa ^ sb
    if not (is_bm_a and support_mxplus):
        if (not inta and ea == 0 and (ma & 0x7) == 0): return 0
    if not (is_bm_b and support_mxplus):
        if (not intb and eb == 0 and (mb & 0x7) == 0): return 0
    if (inta and a_bits == 0) or (intb and b_bits == 0):
        return 0
    adj_a = 0 if is_bm_a else offset_a
    adj_b = 0 if is_bm_b else offset_b
    if use_lns:
        if lns_mode == 0:
            prod = ma * mb
            exp_sum = ea + eb - (ba + bb - 7) - adj_a - adj_b
        elif lns_mode == 2 and support_mxplus and (is_bm_a or is_bm_b):
            prod = ma * mb
            exp_sum = ea + eb - (ba + bb - 7) - adj_a - adj_b
        elif inta or intb:
            return 0
        else:
            if use_lns_precise:
                lut = [0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x1, 0x2, 0x3, 0x4, 0x6, 0x7, 0x8, 0x8, 0x2, 0x3, 0x4, 0x6, 0x7, 0x8, 0x9, 0x9, 0x3, 0x4, 0x6, 0x7, 0x8, 0x9, 0xa, 0xa, 0x4, 0x6, 0x7, 0x8, 0x9, 0xa, 0xa, 0xb, 0x5, 0x7, 0x8, 0x9, 0xa, 0xb, 0xb, 0xc, 0x6, 0x8, 0x9, 0xa, 0xa, 0xb, 0xc, 0xd, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe]
                m_sum = lut[(ma & 0x7) * 8 + (mb & 0x7)]
            else:
                m_sum = (ma & 0x7) + (mb & 0x7)
            carry = m_sum >> 3
            m_res = m_sum & 0x7
            prod = (8 + m_res) << 3
            exp_sum = ea + eb - (ba + bb - 7) + carry - adj_a - adj_b
    else:
        real_ma = ma
        real_mb = mb
        if not support_int8 and not support_mxplus:
            real_ma = real_ma & 0xF
            real_mb = real_mb & 0xF
        prod = real_ma * real_mb
        exp_sum = ea + eb - (ba + bb - 7) - adj_a - adj_b
    return align_model(prod, exp_sum, sign, round_mode, overflow_wrap, width=aligner_width)

async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

async def run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a=127, scale_b=127, round_mode=0, overflow_wrap=0, expected_override=None, packed_mode=0, bm_index_a=0, bm_index_b=0, nbm_offset_a=0, nbm_offset_b=0, mx_plus_mode=0, lns_mode=0):
    support_mixed = get_param(dut, "SUPPORT_MIXED_PRECISION", 0)
    if not support_mixed: format_b = format_a
    support_mxplus = get_param(dut, "SUPPORT_MX_PLUS", 0) and mx_plus_mode
    support_packing = get_param(dut, "SUPPORT_VECTOR_PACKING", 0)
    actual_packed = support_packing and packed_mode and (format_a == 4) and (format_b == 4)
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1) if get_param(dut, "SUPPORT_SERIAL", 0) else 1
    acc_width = get_param(dut, "ACCUMULATOR_WIDTH", 40)
    aligner_width = get_param(dut, "ALIGNER_WIDTH", 40)
    dut.ena.value = 1
    dut.ui_in.value = (nbm_offset_a & 0x7) | (lns_mode << 3)
    dut.uio_in.value = (nbm_offset_b & 0x7) | (round_mode << 3) | (overflow_wrap << 5) | (packed_mode << 6) | (mx_plus_mode << 7)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = scale_a
    dut.uio_in.value = (format_a & 0x7) | ((bm_index_a & 0x1F) << 3)
    await ClockCycles(dut.clk, k_factor)
    dut.ui_in.value = scale_b
    dut.uio_in.value = (format_b & 0x7) | ((bm_index_b & 0x1F) << 3)
    await ClockCycles(dut.clk, k_factor)
    expected_acc = 0
    nan_sticky = (scale_a == 0xFF or scale_b == 0xFF)
    inf_pos_sticky = inf_neg_sticky = False
    for i, (a, b) in enumerate(zip(a_elements, b_elements)):
        is_bm_a_cur = (i == bm_index_a)
        is_bm_b_cur = (i == bm_index_b)
        sa, ea, ma, ba, inta, nana, infa = decode_format(a, format_a, is_bm_a_cur, support_mxplus)
        sb, eb, mb, bb, intb, nanb, infb = decode_format(b, format_b, is_bm_b_cur, support_mxplus)
        is_zero_a = (not inta and ea == 0 and (ma & 0x7) == 0) or (inta and a == 0)
        is_zero_b = (not intb and eb == 0 and (mb & 0x7) == 0) or (intb and b == 0)
        nan_el = nana or nanb or (infa and is_zero_b) or (infb and is_zero_a)
        inf_el = (infa or infb) and not nan_el
        if nan_el: nan_sticky = True
        if inf_el:
            if sa ^ sb: inf_neg_sticky = True
            else: inf_pos_sticky = True
        prod = align_product_model(a, b, format_a, format_b, round_mode, overflow_wrap, is_bm_a=is_bm_a_cur, is_bm_b=is_bm_b_cur, support_mxplus=support_mxplus, offset_a=nbm_offset_a if mx_plus_mode else 0, offset_b=nbm_offset_b if mx_plus_mode else 0, lns_mode=lns_mode, aligner_width=aligner_width)
        mask = (1 << acc_width) - 1
        sum_masked = (expected_acc + prod) & mask
        if not overflow_wrap and (expected_acc ^ prod) >= 0 and (sum_masked ^ expected_acc) < 0:
            expected_acc = (1 << (acc_width-1)) - 1 if expected_acc >= 0 else -(1 << (acc_width-1))
        else:
            expected_acc = sum_masked - (1 << acc_width) if sum_masked & (1 << (acc_width-1)) else sum_masked
    if actual_packed:
        for i in range(16):
            dut.ui_in.value = (a_elements[2*i+1] << 4) | a_elements[2*i]
            dut.uio_in.value = (b_elements[2*i+1] << 4) | b_elements[2*i]
            await ClockCycles(dut.clk, k_factor)
    else:
        for i in range(32):
            dut.ui_in.value = a_elements[i]
            dut.uio_in.value = b_elements[i]
            await ClockCycles(dut.clk, k_factor)
    dut.ui_in.value = dut.uio_in.value = 0
    await ClockCycles(dut.clk, 2 * k_factor)
    shared_exp = scale_a + scale_b - 254 if get_param(dut, "ENABLE_SHARED_SCALING", 0) else 0
    expected_final_unsigned = to_f32_bits(expected_acc, shared_exp, expected_acc < 0, nan_sticky, inf_pos_sticky, inf_neg_sticky, acc_width=acc_width)
    expected_final = expected_final_unsigned - 0x100000000 if expected_final_unsigned & 0x80000000 else expected_final_unsigned
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor)
    if actual_acc & 0x80000000: actual_acc -= 0x100000000
    if expected_override is not None: expected_final = expected_override - 0x100000000 if expected_override & 0x80000000 else expected_override
    dut._log.info(f"Fmt: {format_a}x{format_b}, RM: {round_mode}, Expected: {expected_final}, Actual: {actual_acc}")
    assert actual_acc == expected_final

@cocotb.test()
async def test_mxfp8_mac_shared_scale(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32, scale_a=128, scale_b=127)
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32, scale_a=126, scale_b=127)

@cocotb.test()
async def test_mxfp8_mac_e4m3(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32)

@cocotb.test()
async def test_mxfp8_mac_e5m2(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 1, 1, [0x3C]*32, [0x3C]*32)

@cocotb.test()
async def test_rounding_modes(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    a, b = [0x29]*32, [0x31]*32
    for rm in range(4): await run_mac_test(dut, 0, 0, a, b, round_mode=rm)

@cocotb.test()
async def test_fast_start_scale_compression(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    f_a, f_b, scale_a, scale_b, a_elements, b_elements = 0, 0, 128, 127, [0x38]*32, [0x38]*32
    acc_width = get_param(dut, "ACCUMULATOR_WIDTH", 40)
    aligner_width = get_param(dut, "ALIGNER_WIDTH", 40)
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1) if get_param(dut, "SUPPORT_SERIAL", 0) else 1
    await run_mac_test(dut, f_a, f_b, a_elements, b_elements, scale_a, scale_b)
    # Manual short start sequence
    dut.ui_in.value = 0x80
    dut.uio_in.value = f_a & 0x7
    await ClockCycles(dut.clk, k_factor)
    expected_acc = 0
    for a, b in zip(a_elements, b_elements):
        prod = align_product_model(a, b, f_a, f_b, aligner_width=aligner_width)
        mask = (1 << acc_width) - 1
        expected_acc = (expected_acc + prod) & mask
    if expected_acc & (1 << (acc_width-1)): expected_acc -= (1 << acc_width)
    shared_exp = scale_a + scale_b - 254
    expected_final_unsigned = to_f32_bits(expected_acc, shared_exp, expected_acc < 0, False, False, False, acc_width=acc_width)
    expected_final = expected_final_unsigned - 0x100000000 if expected_final_unsigned & 0x80000000 else expected_final_unsigned
    for i in range(32):
        dut.ui_in.value = a_elements[i]
        dut.uio_in.value = b_elements[i]
        await ClockCycles(dut.clk, k_factor)
    dut.ui_in.value = dut.uio_in.value = 0
    await ClockCycles(dut.clk, 2 * k_factor)
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor)
    if actual_acc & 0x80000000: actual_acc -= 0x100000000
    assert actual_acc == expected_final

async def run_yaml_file(dut, filename):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    yaml_path = os.path.join(os.path.dirname(__file__), filename)
    with open(yaml_path, 'r') as f: cases = yaml.safe_load(f)
    for case in cases:
        if case.get('disabled', False): continue
        inputs = case['inputs']
        fmt_a = inputs['format_a']
        fmt_b = inputs.get('format_b', fmt_a)
        await run_mac_test(dut, fmt_a, fmt_b, inputs['a_elements'], inputs['b_elements'], inputs.get('scale_a', 127), inputs.get('scale_b', 127), inputs.get('round_mode', 0), inputs.get('overflow_mode', 0), expected_override=case['expected_output'], packed_mode=inputs.get('packed_mode', 0), bm_index_a=inputs.get('bm_index_a', 0), bm_index_b=inputs.get('bm_index_b', 0), nbm_offset_a=inputs.get('nbm_offset_a', 0), nbm_offset_b=inputs.get('nbm_offset_b', 0), mx_plus_mode=inputs.get('mx_plus_mode', 0), lns_mode=inputs.get('lns_mode', 0))

@cocotb.test()
async def test_yaml_cases(dut): await run_yaml_file(dut, "TEST_MX_E2E.yaml")
@cocotb.test()
async def test_mx_fp4_yaml(dut): await run_yaml_file(dut, "TEST_MX_FP4.yaml")
@cocotb.test()
async def test_min_max_zero_yaml(dut): await run_yaml_file(dut, "TEST_MIN_MAX_ZERO.yaml")
@cocotb.test()
async def test_mxplus_yaml(dut): await run_yaml_file(dut, "TEST_MXPLUS.yaml")

@cocotb.test()
async def test_mxfp4_input_buffering(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1)
    await reset_dut(dut)
    dut.ena.value, dut.uio_in.value, dut.rst_n.value = 1, 0x40, 0
    await ClockCycles(dut.clk, 10); dut.rst_n.value = 1; await ClockCycles(dut.clk, 1)
    dut.ui_in.value, dut.uio_in.value = 127, 4; await ClockCycles(dut.clk, k_factor)
    dut.ui_in.value, dut.uio_in.value = 127, 4; await ClockCycles(dut.clk, k_factor)
    for i in range(16):
        dut.ui_in.value, dut.uio_in.value = 0x10, 0x10; await ClockCycles(dut.clk, k_factor)
    await ClockCycles(dut.clk, 18 * k_factor)
    actual_acc = 0
    for i in range(4):
        await Timer(1, "ns"); actual_acc = (actual_acc << 8) | int(dut.uo_out.value); await ClockCycles(dut.clk, k_factor)
    if actual_acc & 0x80000000: actual_acc -= 0x100000000
    # Expected: 32 * 1.0 * 1.0 = 32.0 -> 0x42000000
    assert actual_acc == 1107296256

@cocotb.test()
async def test_mxfp8_sticky_flags(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32, scale_a=0xFF)
    await run_mac_test(dut, 0, 0, [0x7F]*32, [0x38]*32)

@cocotb.test()
async def test_lns_modes(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    if not get_param(dut, "USE_LNS_MUL", 0): return
    await run_mac_test(dut, 0, 0, [0x39]*32, [0x3A]*32, lns_mode=1)

@cocotb.test()
async def test_mxfp8_subnormals(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x01]*32, [0x38]*32)

@cocotb.test()
async def test_lane_overflow(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 4, 4, [0x02]*32, [0x02]*32, scale_a=157, scale_b=127, packed_mode=1)
