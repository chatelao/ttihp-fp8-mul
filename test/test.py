# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

def decode_format(bits, format_val):
    if format_val == 0: # E4M3
        sign = (bits >> 7) & 1
        exp = (bits >> 3) & 0xF
        mant = (bits & 0x7)
        bias = 7
        is_int = False
    elif format_val == 1: # E5M2
        sign = (bits >> 7) & 1
        exp = (bits >> 2) & 0x1F
        mant = (bits & 0x3) << 1
        bias = 15
        is_int = False
    elif format_val == 2: # E3M2
        sign = (bits >> 5) & 1
        exp = (bits >> 2) & 0x7
        mant = (bits & 0x3) << 1
        bias = 3
        is_int = False
    elif format_val == 3: # E2M3
        sign = (bits >> 5) & 1
        exp = (bits >> 3) & 0x3
        mant = (bits & 0x7)
        bias = 1
        is_int = False
    elif format_val == 4: # E2M1
        sign = (bits >> 3) & 1
        exp = (bits >> 1) & 0x3
        mant = (bits & 0x1) << 2
        bias = 1
        is_int = False
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
    else: # Default E4M3
        return decode_format(bits, 0)

    return sign, exp, mant, bias, is_int

def align_model(prod, exp_sum, sign, round_mode=0, overflow_wrap=0, width=40, out_width=32):
    shift_amt = exp_sum - 5
    WIDTH = width

    if shift_amt >= 0:
        if not overflow_wrap and shift_amt >= WIDTH:
            aligned = (1 << WIDTH) - 1 if prod != 0 else 0
        else:
            aligned = prod << shift_amt
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
            shifted_out = prod
        else:
            base = prod >> n
            shifted_out = prod & ((1 << n) - 1)

        sticky = 1 if shifted_out != 0 else 0
        round_bit = 1 if (n > 0 and (prod & (1 << (n-1)))) else 0

        if round_mode == 0: # TRN
            aligned = base
        elif round_mode == 1: # CEL
            aligned = base + 1 if (not sign and (shifted_out != 0)) else base
        elif round_mode == 2: # FLR
            aligned = base + 1 if (sign and (shifted_out != 0)) else base
        elif round_mode == 3: # RNE
            if round_bit:
                if sticky or (base & 1): aligned = base + 1
                else: aligned = base
            else:
                aligned = base
        else:
            aligned = base

    pos_max = (1 << (out_width - 1)) - 1
    neg_min = -(1 << (out_width - 1))

    if sign:
        if not overflow_wrap and (huge or (aligned >> (out_width)) != 0 or ( (aligned & (1 << (out_width-1))) != 0 and (aligned & ((1 << (out_width-1)) - 1)) != 0 )):
            res = neg_min
        else:
            res = - (aligned & ((1 << out_width) - 1))
    else:
        if not overflow_wrap and (huge or (aligned >> (out_width - 1)) != 0):
            res = pos_max
        else:
            res = aligned & ((1 << out_width) - 1)

    mask = (1 << out_width) - 1
    res_masked = res & mask
    if res_masked & (1 << (out_width - 1)):
        return res_masked - (1 << out_width)
    return res_masked

def get_param(handle, default=1):
    try:
        return int(handle.value)
    except Exception:
        return default

def align_product_model(a_bits, b_bits, format_a, format_b, round_mode=0, overflow_wrap=0,
                        support_e5m2=1, support_mxfp6=1, support_mxfp4=1,
                        width=40, out_width=32, support_int8=1):
    if not support_e5m2 and format_a == 1: return 0
    if not support_e5m2 and format_b == 1: return 0
    if not support_mxfp6 and format_a in [2, 3]: return 0
    if not support_mxfp6 and format_b in [2, 3]: return 0
    if not support_mxfp4 and format_a == 4: return 0
    if not support_mxfp4 and format_b == 4: return 0
    if not support_int8 and format_a in [5, 6]: return 0
    if not support_int8 and format_b in [5, 6]: return 0

    sa, ea, ma, ba, inta = decode_format(a_bits, format_a)
    sb, eb, mb, bb, intb = decode_format(b_bits, format_b)

    sign = sa ^ sb

    if (not inta and ea == 0) or (not intb and eb == 0): return 0
    if (inta and a_bits == 0) or (intb and b_bits == 0): return 0

    real_ma = (8 + ma) if not inta else ma
    real_mb = (8 + mb) if not intb else mb

    if support_int8: prod = real_ma * real_mb
    else: prod = (real_ma & 0xF) * (real_mb & 0xF)

    exp_sum = ea + eb - (ba + bb - 7)
    return align_model(prod, exp_sum, sign, round_mode, overflow_wrap, width=width, out_width=out_width)

async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

async def run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a=127, scale_b=127, round_mode=0, overflow_wrap=0):
    support_mixed = get_param(getattr(dut.user_project, "SUPPORT_MIXED_PRECISION", None), 1)
    if not support_mixed: format_b = format_a

    support_adv = get_param(getattr(dut.user_project, "SUPPORT_ADV_ROUNDING", None), 1)
    if not support_adv:
        if round_mode in [1, 2]: round_mode = 0

    support_e5m2 = get_param(getattr(dut.user_project, "SUPPORT_E5M2", None), 1)
    support_mxfp6 = get_param(getattr(dut.user_project, "SUPPORT_MXFP6", None), 1)
    support_mxfp4 = get_param(getattr(dut.user_project, "SUPPORT_MXFP4", None), 1)
    support_int8 = get_param(getattr(dut.user_project, "SUPPORT_INT8", None), 1)
    aligner_width = get_param(getattr(dut.user_project, "ALIGNER_WIDTH", None), 40)
    acc_width = get_param(getattr(dut.user_project, "ACCUMULATOR_WIDTH", None), 32)

    await reset_dut(dut)

    dut.ui_in.value = scale_a
    dut.uio_in.value = format_a | (round_mode << 3) | (overflow_wrap << 5)
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value = format_b
    dut.uio_in.value = scale_b
    await ClockCycles(dut.clk, 1)

    expected_acc = 0
    for a, b in zip(a_elements, b_elements):
        prod = align_product_model(a, b, format_a, format_b, round_mode, overflow_wrap,
                                   support_e5m2, support_mxfp6, support_mxfp4,
                                   width=aligner_width, out_width=acc_width, support_int8=support_int8)
        mask = (1 << acc_width) - 1
        acc_masked = expected_acc & mask
        prod_masked = prod & mask
        sum_masked = (acc_masked + prod_masked) & mask
        s_acc = (acc_masked >> (acc_width - 1)) & 1
        s_prod = (prod_masked >> (acc_width - 1)) & 1
        s_res = (sum_masked >> (acc_width - 1)) & 1
        if not overflow_wrap and (s_acc == s_prod) and (s_acc != s_res):
            expected_acc_raw = -(1 << (acc_width - 1)) if s_acc == 1 else (1 << (acc_width - 1)) - 1
        else:
            expected_acc_raw = sum_masked - (1 << acc_width) if sum_masked & (1 << (acc_width - 1)) else sum_masked
        expected_acc = expected_acc_raw

    for i in range(32):
        dut.ui_in.value = a_elements[i]
        dut.uio_in.value = b_elements[i]
        await ClockCycles(dut.clk, 1)

    await ClockCycles(dut.clk, 2)

    support_shared = get_param(getattr(dut.user_project, "ENABLE_SHARED_SCALING", None), 1)
    if support_shared:
        shared_exp = scale_a + scale_b - 254
        acc_abs = abs(expected_acc)
        acc_sign = 1 if expected_acc < 0 else 0
        expected_final = align_model(acc_abs, shared_exp + 5, acc_sign, round_mode, overflow_wrap, width=aligner_width, out_width=32)
    else:
        expected_final = expected_acc

    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, 1)

    if actual_acc & 0x80000000: actual_acc -= 0x100000000
    assert actual_acc == expected_final

@cocotb.test()
async def test_mxfp8_mac_shared_scale(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x38] * 32
    b_elements = [0x38] * 32
    await run_mac_test(dut, 0, 0, a_elements, b_elements, scale_a=128, scale_b=127)
    await run_mac_test(dut, 0, 0, a_elements, b_elements, scale_a=126, scale_b=127)

@cocotb.test()
async def test_mxfp8_mac_e4m3(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x38] * 32
    b_elements = [0x38] * 32
    await run_mac_test(dut, 0, 0, a_elements, b_elements)

@cocotb.test()
async def test_mxfp8_mac_e5m2(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x3C] * 32
    b_elements = [0x3C] * 32
    await run_mac_test(dut, 1, 1, a_elements, b_elements)

@cocotb.test()
async def test_rounding_modes(dut):
    support_adv = get_param(getattr(dut.user_project, "SUPPORT_ADV_ROUNDING", None), 1)
    if not support_adv: return
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x29] * 32
    b_elements = [0x31] * 32
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=0)
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=1)
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=2)
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=3)

@cocotb.test()
async def test_overflow_saturation(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x7C] * 32
    b_elements = [0x7C] * 32
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=0)
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=1)

@cocotb.test()
async def test_accumulator_saturation(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x78] * 32
    b_elements = [0x78] * 32
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=0)
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=1)

@cocotb.test()
async def test_mixed_precision(dut):
    support_mixed = get_param(getattr(dut.user_project, "SUPPORT_MIXED_PRECISION", None), 1)
    if not support_mixed: return
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x38] * 32
    b_elements = [0x3C] * 32
    await run_mac_test(dut, 0, 1, a_elements, b_elements)

@cocotb.test()
async def test_mxfp_mac_randomized(dut):
    import random
    support_e5m2 = get_param(getattr(dut.user_project, "SUPPORT_E5M2", None), 1)
    support_mxfp6 = get_param(getattr(dut.user_project, "SUPPORT_MXFP6", None), 1)
    support_mxfp4 = get_param(getattr(dut.user_project, "SUPPORT_MXFP4", None), 1)
    support_adv = get_param(getattr(dut.user_project, "SUPPORT_ADV_ROUNDING", None), 1)
    support_mixed = get_param(getattr(dut.user_project, "SUPPORT_MIXED_PRECISION", None), 1)
    support_int8 = get_param(getattr(dut.user_project, "SUPPORT_INT8", None), 1)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    allowed_formats = [0]
    if support_e5m2: allowed_formats.append(1)
    if support_mxfp6: allowed_formats.extend([2, 3])
    if support_mxfp4: allowed_formats.append(4)
    if support_int8: allowed_formats.extend([5, 6])
    for _ in range(20):
        fa = random.choice(allowed_formats)
        fb = random.choice(allowed_formats) if support_mixed else fa
        rm = random.randint(0, 3) if support_adv else 0
        ov = random.randint(0, 1)
        sa, sb = random.randint(110, 140), random.randint(110, 140)
        a_els = [random.randint(0, 255) for _ in range(32)]
        b_els = [random.randint(0, 255) for _ in range(32)]
        await run_mac_test(dut, fa, fb, a_els, b_els, sa, sb, rm, ov)

@cocotb.test()
async def test_fast_start_scale_compression(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    format_a, format_b = 0, 0
    scale_a, scale_b = 128, 127
    a_elements, b_elements = [0x38] * 32, [0x38] * 32
    await run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a, scale_b)
    support_shared = get_param(getattr(dut.user_project, "ENABLE_SHARED_SCALING", None), 1)
    aligner_width = get_param(getattr(dut.user_project, "ALIGNER_WIDTH", None), 40)
    acc_width = get_param(getattr(dut.user_project, "ACCUMULATOR_WIDTH", None), 32)
    dut.ui_in.value = 0x80
    await ClockCycles(dut.clk, 1)
    expected_acc = 0
    for a, b in zip(a_elements, b_elements):
        prod = align_product_model(a, b, format_a, format_b, width=aligner_width, out_width=acc_width)
        expected_acc += prod
    if support_shared: expected_final = align_model(abs(expected_acc), scale_a + scale_b - 254 + 5, 1 if expected_acc < 0 else 0, width=aligner_width, out_width=32)
    else: expected_final = expected_acc
    for i in range(32):
        dut.ui_in.value = a_elements[i]
        dut.uio_in.value = b_elements[i]
        await ClockCycles(dut.clk, 1)
    await ClockCycles(dut.clk, 2)
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, 1)
    if actual_acc & 0x80000000: actual_acc -= 0x100000000
    assert actual_acc == expected_final
