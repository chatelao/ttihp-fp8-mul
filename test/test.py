# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
import yaml
import os

def decode_format(bits, format_val, is_bm=False, support_mxplus=False,
                  support_e4m3=True, support_e5m2=True, support_mxfp6=True,
                  support_mxfp4=True, support_int8=True):
    # Matches hardware initializations in decode_operand task in src/fp8_mul.v
    sign, exp, mant, bias, is_int, nan, inf = 0, 0, 0, 0, False, False, False

    if format_val == 0: # FMT_E4M3
        if support_e4m3:
            sign, bias = (bits >> 7) & 1, 7
            if is_bm and support_mxplus:
                exp, mant = 11, (1 << 7) | (bits & 0x7F)
            else:
                if (bits & 0x7F) == 0x7F: nan = True
                exp_field, mant_field = (bits >> 3) & 0xF, (bits & 0x7)
                exp = 1 if (exp_field == 0 and mant_field != 0) else exp_field
                mant = ((0 if exp_field == 0 else 1) << 3) | mant_field
    elif format_val == 1: # FMT_E5M2
        if support_e5m2:
            sign, bias = (bits >> 7) & 1, 15
            if is_bm and support_mxplus:
                exp, mant = 26, (1 << 7) | (bits & 0x7F)
            else:
                exp_field, mant_field = (bits >> 2) & 0x1F, (bits & 0x3)
                if exp_field == 0x1F:
                    if mant_field == 0: inf = True
                    else: nan = True
                exp = 1 if (exp_field == 0 and mant_field != 0) else exp_field
                mant = (((0 if exp_field == 0 else 1) << 2) | mant_field) << 1
    elif format_val == 2: # FMT_E3M2
        if support_mxfp6:
            sign, bias = (bits >> 5) & 1, 3
            if is_bm and support_mxplus:
                exp, mant = 5, (1 << 5) | (bits & 0x1F)
            else:
                exp_field, mant_field = (bits >> 2) & 0x7, (bits & 0x3)
                exp = 1 if (exp_field == 0 and mant_field != 0) else exp_field
                mant = (((0 if exp_field == 0 else 1) << 2) | mant_field) << 1
    elif format_val == 3: # FMT_E2M3
        if support_mxfp6:
            sign, bias = (bits >> 5) & 1, 1
            if is_bm and support_mxplus:
                exp, mant = 1, (1 << 5) | (bits & 0x1F)
            else:
                exp_field, mant_field = (bits >> 3) & 0x3, (bits & 0x7)
                exp = 1 if (exp_field == 0 and mant_field != 0) else exp_field
                mant = ((0 if exp_field == 0 else 1) << 3) | mant_field
    elif format_val == 4: # FMT_E2M1
        if support_mxfp4:
            sign, bias = (bits >> 3) & 1, 1
            if is_bm and support_mxplus:
                exp, mant = 3, (1 << 3) | (bits & 0x7)
            else:
                exp_field, mant_field = (bits >> 1) & 0x3, (bits & 0x1)
                exp = 1 if (exp_field == 0 and mant_field != 0) else exp_field
                mant = (((0 if exp_field == 0 else 1) << 1) | mant_field) << 2
    elif format_val == 5: # FMT_INT8
        if support_int8:
            sign, bias, is_int = (bits >> 7) & 1, 3, True
            mant = abs(bits if bits < 128 else bits - 256)
    elif format_val == 6: # FMT_INT8_SYM
        if support_int8:
            sign, bias, is_int = (bits >> 7) & 1, 3, True
            val = bits if bits < 128 else bits - 256
            mant = abs(-127 if val == -128 else val)
    else: # Hardware default case
        sign, bias = (bits >> 7) & 1, 7
        exp_field, mant_field = (bits >> 3) & 0xF, (bits & 0x7)
        exp = 1 if (exp_field == 0 and mant_field != 0) else exp_field
        mant = ((0 if exp_field == 0 else 1) << 3) | mant_field

    return sign, exp, mant, bias, is_int, nan, inf

def align_model(prod, exp_sum, sign, round_mode=0, overflow_wrap=0, width=40):
    shift_amt = exp_sum - 5
    if shift_amt >= 0:
        if not overflow_wrap and shift_amt >= width: rounded = (1 << width) - 1 if prod != 0 else 0
        else: rounded = prod << shift_amt
        huge = (prod != 0 and shift_amt >= width) or (0 < shift_amt < width and (prod >> (width - shift_amt)) != 0)
        shifted_out, sticky = 0, 0
    else:
        n = -shift_amt
        if n >= width: base, s_out, sticky = 0, prod, (1 if prod != 0 else 0)
        else: base, s_out, sticky = prod >> n, prod & ((1 << n) - 1), (1 if (prod & ((1 << n) - 1)) != 0 else 0)
        huge, do_inc = False, False
        if round_mode == 1: do_inc = (not sign and (s_out != 0 or sticky))
        elif round_mode == 2: do_inc = (sign and (s_out != 0 or sticky))
        elif round_mode == 3: do_inc = (s_out > (1 << (n-1))) or (s_out == (1 << (n-1)) and (base & 1))
        rounded = base + (1 if do_inc else 0)

    if sign:
        if not overflow_wrap and (huge or (rounded >> 32) != 0 or ((rounded & (1 << 31)) != 0 and (rounded & 0x7FFFFFFF) != 0)): res = 0x80000000
        else: res = (-(rounded & 0xFFFFFFFF)) & 0xFFFFFFFF
    else:
        if not overflow_wrap and (huge or (rounded >> 31) != 0): res = 0x7FFFFFFF
        else: res = rounded & 0xFFFFFFFF
    return res

def get_param(dut, name, default=1):
    for obj in [getattr(dut, "user_project", None), dut]:
        if obj is None: continue
        try: return int(getattr(obj, name).value)
        except Exception: pass
    compile_args = os.environ.get("COMPILE_ARGS", "")
    import re
    matches = re.findall(r"-P\s+(?:\w+\.)?" + name + r"=(\d+)", compile_args)
    if matches: return int(matches[-1])
    return {"ALIGNER_WIDTH": 32, "ACCUMULATOR_WIDTH": 24, "SUPPORT_E4M3": 1, "SUPPORT_E5M2": 0, "SUPPORT_MXFP6": 0, "SUPPORT_MXFP4": 1, "SUPPORT_INT8": 0, "SUPPORT_PIPELINING": 0, "SUPPORT_ADV_ROUNDING": 0, "SUPPORT_MIXED_PRECISION": 0, "SUPPORT_VECTOR_PACKING": 0, "SUPPORT_PACKED_SERIAL": 0, "SUPPORT_MX_PLUS": 0, "SUPPORT_SERIAL": 0, "SERIAL_K_FACTOR": 1, "ENABLE_SHARED_SCALING": 0, "USE_LNS_MUL": 0, "USE_LNS_MUL_PRECISE": 0}.get(name, default)

def align_product_model(a_bits, b_bits, format_a, format_b, round_mode=0, overflow_wrap=0,
                        support_e4m3=1, support_e5m2=1, support_mxfp6=1, support_mxfp4=1, support_int8=1, use_lns=0, use_lns_precise=0, aligner_width=40,
                        is_bm_a=False, is_bm_b=False, support_mxplus=False, offset_a=0, offset_b=0):
    sa, ea, ma, ba, inta, na, ia = decode_format(a_bits, format_a, is_bm_a, support_mxplus, support_e4m3, support_e5m2, support_mxfp6, support_mxfp4, support_int8)
    sb, eb, mb, bb, intb, nb, ib = decode_format(b_bits, format_b, is_bm_b, support_mxplus, support_e4m3, support_e5m2, support_mxfp6, support_mxfp4, support_int8)
    # Hardware zero_out logic
    za = (ea == 0 and (ma & 0xF) == 0) and not (is_bm_a and support_mxplus)
    if inta: za = (a_bits == 0)
    if format_a == 0 and not support_e4m3: za = True
    elif format_a == 1 and not support_e5m2: za = True
    elif format_a in [2,3] and not support_mxfp6: za = True
    elif format_a == 4 and not support_mxfp4: za = True
    elif format_a in [5,6] and not support_int8: za = True
    zb = (eb == 0 and (mb & 0xF) == 0) and not (is_bm_b and support_mxplus)
    if intb: zb = (b_bits == 0)
    if format_b == 0 and not support_e4m3: zb = True
    elif format_b == 1 and not support_e5m2: zb = True
    elif format_b in [2,3] and not support_mxfp6: zb = True
    elif format_b == 4 and not support_mxfp4: zb = True
    elif format_b in [5,6] and not support_int8: zb = True
    nan_res = na or nb or (ia and zb) or (ib and za)
    inf_res = (ia or ib) and not nan_res
    if za or zb: return 0, nan_res, inf_res
    adj_a, adj_b = (0 if is_bm_a else offset_a), (0 if is_bm_b else offset_b)
    if use_lns:
        if inta or intb: return 0, False, False
        if support_mxplus and (is_bm_a or is_bm_b): prod, exp_sum = ma * mb, ea + eb - (ba + bb - 7) - adj_a - adj_b
        else:
            if use_lns_precise: m_sum = [0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x1, 0x2, 0x3, 0x4, 0x6, 0x7, 0x8, 0x8, 0x2, 0x3, 0x4, 0x6, 0x7, 0x8, 0x9, 0x9, 0x3, 0x4, 0x6, 0x7, 0x8, 0x9, 0xa, 0xa, 0x4, 0x6, 0x7, 0x8, 0x9, 0xa, 0xa, 0xb, 0x5, 0x7, 0x8, 0x9, 0xa, 0xb, 0xb, 0xc, 0x6, 0x8, 0x9, 0xa, 0xa, 0xb, 0xc, 0xd, 0x7, 0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe][(ma&7)*8+(mb&7)]
            else: m_sum = (ma & 0x7) + (mb & 0x7)
            prod, exp_sum = (8 + (m_sum & 0x7)) << 3, ea + eb - (ba + bb - 7) + (m_sum >> 3) - adj_a - adj_b
    else:
        ma_v, mb_v = ma, mb
        if not support_int8 and not support_mxplus: ma_v, mb_v = ma_v & 0xF, mb_v & 0xF
        prod, exp_sum = ma_v * mb_v, ea + eb - (ba + bb - 7) - adj_a - adj_b
    return align_model(prod, exp_sum, sa ^ sb, round_mode, overflow_wrap, aligner_width), nan_res, inf_res

async def reset_dut(dut):
    dut.ena.value, dut.ui_in.value, dut.uio_in.value, dut.rst_n.value = 1, 0, 0, 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

async def run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a=127, scale_b=127, round_mode=0, overflow_wrap=0, expected_override=None, packed_mode=0, bm_index_a=0, bm_index_b=0, nbm_offset_a=0, nbm_offset_b=0, mx_plus_mode=0):
    if not get_param(dut, "SUPPORT_MIXED_PRECISION", 0): format_b = format_a
    support_mxplus_hw, support_packing, support_serial = get_param(dut, "SUPPORT_MX_PLUS", 0), get_param(dut, "SUPPORT_VECTOR_PACKING", 0), get_param(dut, "SUPPORT_PACKED_SERIAL", 0)
    support_mxplus = support_mxplus_hw and mx_plus_mode
    actual_packed = support_packing and packed_mode and (format_a == 4) and (format_b == 4)
    actual_serial = support_serial and not support_packing and packed_mode and (format_a == 4) and (format_b == 4)
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1)
    if not get_param(dut, "SUPPORT_ADV_ROUNDING", 0) and round_mode in [1, 2]: round_mode = 0
    s_e4, s_e5, s_6, s_4, s_i8 = get_param(dut, "SUPPORT_E4M3", 1), get_param(dut, "SUPPORT_E5M2", 0), get_param(dut, "SUPPORT_MXFP6", 0), get_param(dut, "SUPPORT_MXFP4", 1), get_param(dut, "SUPPORT_INT8", 0)
    use_lns, use_lns_p, acc_w, align_w = get_param(dut, "USE_LNS_MUL", 0), get_param(dut, "USE_LNS_MUL_PRECISE", 0), get_param(dut, "ACCUMULATOR_WIDTH", 32), get_param(dut, "ALIGNER_WIDTH", 40)
    dut.ena.value = 1
    if support_mxplus_hw:
        dut.ui_in.value, dut.uio_in.value = (nbm_offset_b & 0x7), (bm_index_a & 0x1F) | ((nbm_offset_a & 0x7) << 5)
    else: dut.ui_in.value, dut.uio_in.value = 0, 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)
    dut.ui_in.value, dut.uio_in.value = scale_a, format_a | (round_mode << 3) | (overflow_wrap << 5) | (packed_mode << 6) | (mx_plus_mode << 7)
    await ClockCycles(dut.clk, k_factor)
    dut.ui_in.value = scale_b
    if support_mxplus: dut.uio_in.value = (format_b & 0x7) | ((bm_index_b & 0x1F) << 3)
    else: dut.uio_in.value = format_b
    await ClockCycles(dut.clk, k_factor)
    expected_acc, nan_sticky, inf_sticky = 0, False, False
    for i, (a, b) in enumerate(zip(a_elements, b_elements)):
        prod, n_prod, i_prod = align_product_model(a, b, format_a, format_b, round_mode, overflow_wrap, s_e4, s_e5, s_6, s_4, s_i8, use_lns, use_lns_p, align_w, i == bm_index_a, i == bm_index_b, support_mxplus, nbm_offset_a if mx_plus_mode else 0, nbm_offset_b if mx_plus_mode else 0)
        nan_sticky, inf_sticky = nan_sticky or n_prod, inf_sticky or i_prod
        mask = (1 << acc_w) - 1
        acc_m, p_m = expected_acc & mask, prod & mask
        sum_m = (acc_m + p_m) & mask
        sa, sp, sr = (acc_m >> (acc_w - 1)) & 1, (p_m >> (acc_w - 1)) & 1, (sum_m >> (acc_w - 1)) & 1
        if not overflow_wrap and (sa == sp) and (sa != sr): expected_acc_raw = (1 << (acc_w - 1)) if sa == 1 else (1 << (acc_w - 1)) - 1
        else: expected_acc_raw = sum_m
        expected_acc = expected_acc_raw - (1 << acc_w) if expected_acc_raw & (1 << (acc_w - 1)) else expected_acc_raw
    if actual_packed:
        for i in range(16):
            dut.ui_in.value, dut.uio_in.value = (a_elements[2*i+1] << 4) | a_elements[2*i], (b_elements[2*i+1] << 4) | b_elements[2*i]
            await ClockCycles(dut.clk, k_factor)
    elif actual_serial:
        for i in range(16):
            dut.ui_in.value, dut.uio_in.value = (a_elements[2*i+1] << 4) | a_elements[2*i], (b_elements[2*i+1] << 4) | b_elements[2*i]
            await ClockCycles(dut.clk, 2 * k_factor)
    else:
        for i in range(32):
            dut.ui_in.value, dut.uio_in.value = a_elements[i], b_elements[i]
            await ClockCycles(dut.clk, k_factor)
    dut.ui_in.value, dut.uio_in.value = 0, 0
    await ClockCycles(dut.clk, 2 * k_factor)
    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    block_nan = support_shared and (scale_a == 255 or scale_b == 255)
    final_nan, final_inf = nan_sticky or block_nan, inf_sticky and not (nan_sticky or block_nan)
    if final_nan: expected_final = 0x7FC00000
    elif final_inf: expected_final = 0xFF800000 if expected_acc < 0 else 0x7F800000
    else:
        if support_shared: expected_final = align_model(abs(expected_acc), scale_a+scale_b-254+5, 1 if expected_acc < 0 else 0, round_mode, overflow_wrap, align_w)
        else: expected_final = expected_acc
    if not final_nan and not final_inf:
        # Saturation logic in Python model for 32-bit signed
        ef_s = expected_final if expected_final < 0x80000000 else expected_final - 0x100000000
        if ef_s > 2147483647: expected_final = 0x7FFFFFFF
        elif ef_s < -2147483648: expected_final = 0x80000000
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor)
    if expected_override is not None: expected_final = expected_override
    actual_acc &= 0xFFFFFFFF
    expected_final &= 0xFFFFFFFF
    # Re-normalize to signed for logging/assert
    actual_s = actual_acc if actual_acc < 0x80000000 else actual_acc - 0x100000000
    expected_s = expected_final if expected_final < 0x80000000 else expected_final - 0x100000000
    dut._log.info(f"Expected: {expected_s}, Actual: {actual_s}")
    assert actual_s == expected_s

@cocotb.test()
async def test_mxfp8_mac_shared_scale(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32, scale_a=128, scale_b=127)
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32, 126, 127)

@cocotb.test()
async def test_mxfp8_mac_e4m3(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32)

@cocotb.test()
async def test_mxfp8_mac_e5m2(dut):
    if not get_param(dut, "SUPPORT_E5M2", 1): return
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await run_mac_test(dut, 1, 1, [0x3C]*32, [0x3C]*32)

@cocotb.test()
async def test_rounding_modes(dut):
    if not get_param(dut, "SUPPORT_ADV_ROUNDING", 1): return
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    for rm in range(4): await run_mac_test(dut, 0, 0, [0x29]*32, [0x31]*32, round_mode=rm)

@cocotb.test()
async def test_overflow_saturation(dut):
    if not get_param(dut, "SUPPORT_E5M2", 1): return
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await run_mac_test(dut, 1, 1, [0x7C]*32, [0x7C]*32, overflow_wrap=0)
    await run_mac_test(dut, 1, 1, [0x7C]*32, [0x7C]*32, overflow_wrap=1)

@cocotb.test()
async def test_accumulator_saturation(dut):
    if not get_param(dut, "SUPPORT_E5M2", 1): return
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await run_mac_test(dut, 1, 1, [0x78]*32, [0x78]*32, overflow_wrap=0)
    await run_mac_test(dut, 1, 1, [0x78]*32, [0x78]*32, overflow_wrap=1)

@cocotb.test()
async def test_mxfp4_packed_serial(dut):
    if not get_param(dut, "SUPPORT_PACKED_SERIAL", 0): return
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await run_mac_test(dut, 4, 4, [0x04]*32, [0x04]*32, packed_mode=1)

@cocotb.test()
async def test_mxfp4_packed(dut):
    if not get_param(dut, "SUPPORT_VECTOR_PACKING", 0): return
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await run_mac_test(dut, 4, 4, [0x04]*32, [0x04]*32, packed_mode=1)

@cocotb.test()
async def test_mixed_precision(dut):
    if not get_param(dut, "SUPPORT_MIXED_PRECISION", 1): return
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 1, [0x38]*32, [0x3C]*32)
    await run_mac_test(dut, 2, 5, [0x10]*32, [0x40]*32)

@cocotb.test()
async def test_mxfp_mac_randomized(dut):
    import random
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    s_e4, s_e5, s_6, s_4, s_i8, s_mixed = get_param(dut, "SUPPORT_E4M3", 1), get_param(dut, "SUPPORT_E5M2", 1), get_param(dut, "SUPPORT_MXFP6", 1), get_param(dut, "SUPPORT_MXFP4", 1), get_param(dut, "SUPPORT_INT8", 1), get_param(dut, "SUPPORT_MIXED_PRECISION", 1)
    allowed = []
    if s_e4: allowed.append(0)
    if s_e5: allowed.append(1)
    if s_6: allowed.extend([2, 3])
    if s_4: allowed.append(4)
    if s_i8: allowed.extend([5, 6])
    if not allowed: allowed = [0]
    for _ in range(50):
        fa = random.choice(allowed)
        fb = random.choice(allowed) if s_mixed else fa
        await run_mac_test(dut, fa, fb, [random.randint(0, 255) for _ in range(32)], [random.randint(0, 255) for _ in range(32)], random.randint(110, 140), random.randint(110, 140))

@cocotb.test()
async def test_fast_start_scale_compression(dut):
    if not get_param(dut, "SUPPORT_E4M3", 1) or not get_param(dut, "ENABLE_SHARED_SCALING", 0): return
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32, 128, 127)
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1)
    dut.ui_in.value = 0x80
    await ClockCycles(dut.clk, k_factor)
    e_acc, n_s, i_s = 0, False, False
    s_e4, s_e5, s_6, s_4, s_i8, aw = get_param(dut, "SUPPORT_E4M3", 1), get_param(dut, "SUPPORT_E5M2", 0), get_param(dut, "SUPPORT_MXFP6", 0), get_param(dut, "SUPPORT_MXFP4", 1), get_param(dut, "SUPPORT_INT8", 0), get_param(dut, "ALIGNER_WIDTH", 40)
    for a, b in zip([0x38]*32, [0x38]*32):
        p, n, i = align_product_model(a, b, 0, 0, 0, 0, s_e4, s_e5, s_6, s_4, s_i8, 0, 0, aw)
        n_s, i_s, e_acc = n_s or n, i_s or i, e_acc + p
    e_f = align_model(abs(e_acc), 128+127-254+5, 1 if e_acc < 0 else 0, 0, 0, aw)
    for i in range(32):
        dut.ui_in.value, dut.uio_in.value = 0x38, 0x38
        await ClockCycles(dut.clk, k_factor)
    await ClockCycles(dut.clk, 2 * k_factor)
    act = 0
    for i in range(4):
        await Timer(1, unit="ns")
        act = (act << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor)
    assert (act & 0xFFFFFFFF) == (e_f & 0xFFFFFFFF)

@cocotb.test()
async def test_nan_inf_yaml(dut): await run_yaml_file(dut, "TEST_NAN_INF.yaml")
@cocotb.test()
async def test_yaml_cases(dut): await run_yaml_file(dut, "TEST_MX_E2E.YAML")
@cocotb.test()
async def test_mx_fp4_yaml(dut): await run_yaml_file(dut, "TEST_MX_FP4.yaml")
@cocotb.test()
async def test_mxplus_yaml(dut):
    if os.environ.get("GATES") == "yes" or not get_param(dut, "SUPPORT_MX_PLUS", 0): return
    await run_yaml_file(dut, "TEST_MXPLUS.yaml")

async def run_yaml_file(dut, filename):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    with open(os.path.join(os.path.dirname(__file__), filename), 'r') as f: cases = yaml.safe_load(f)
    s_e4, s_e5, s_6, s_4, s_i8, s_mixed, s_shared, s_adv = get_param(dut, "SUPPORT_E4M3", 1), get_param(dut, "SUPPORT_E5M2", 1), get_param(dut, "SUPPORT_MXFP6", 1), get_param(dut, "SUPPORT_MXFP4", 1), get_param(dut, "SUPPORT_INT8", 1), get_param(dut, "SUPPORT_MIXED_PRECISION", 1), get_param(dut, "ENABLE_SHARED_SCALING", 1), get_param(dut, "SUPPORT_ADV_ROUNDING", 1)
    for case in cases:
        if case.get('disabled', False): continue
        inputs, expected = case['inputs'], case['expected_output']
        fa, fb = inputs['format_a'], inputs.get('format_b', inputs['format_a'])
        if not s_e4 and (fa == 0 or fb == 0): continue
        if not s_e5 and (fa == 1 or fb == 1): continue
        if not s_6 and (fa in [2, 3] or fb in [2, 3]): continue
        if not s_4 and (fa == 4 or fb == 4): continue
        if not s_i8 and (fa in [5, 6] or fb in [5, 6]): continue
        if not s_mixed and (fa != fb): continue
        if not s_shared and (inputs.get('scale_a', 127) != 127 or inputs.get('scale_b', 127) != 127): continue
        if not s_adv and inputs.get('round_mode', 0) in [1, 2]: continue
        await run_mac_test(dut, fa, fb, inputs['a_elements'], inputs['b_elements'], inputs.get('scale_a', 127), inputs.get('scale_b', 127), inputs.get('round_mode', 0), inputs.get('overflow_mode', 0), expected, inputs.get('packed_mode', 0), inputs.get('bm_index_a', 0), inputs.get('bm_index_b', 0), inputs.get('nbm_offset_a', 0), inputs.get('nbm_offset_b', 0), inputs.get('mx_plus_mode', 0))

@cocotb.test()
async def test_mxfp8_subnormals(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x01]*32, [0x38]*32)
