# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
import yaml
import os
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
        # Underflow to zero with sign
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

def get_param(dut, name, default=1):
    # Check environment variable overrides (e.g., from CI)
    compile_args = os.environ.get("COMPILE_ARGS", "")
    import re
    # Match both decimal and hex: -P tb.PARAM=123 or -P tb.PARAM=0x7B
    match = re.search(fr"-P\s+tb\.{name}=(\w+)", compile_args)
    if match:
        val_str = match.group(1)
        try:
            return int(val_str, 0)
        except ValueError:
            pass

    # Check DUT handles
    for obj in [getattr(dut, "user_project", None), dut]:
        if obj is None: continue
        try:
            val = getattr(obj, name).value
            return int(val)
        except:
            pass
    return default

def align_product_model(a_bits, b_bits, format_a, format_b, round_mode=0, overflow_wrap=0, is_bm_a=False, is_bm_b=False, support_mxplus=False, offset_a=0, offset_b=0, lns_mode=0, aligner_width=40):
    # support_mxplus from caller is a boolean (mode enabled)
    # But we also need to check the hardware global parameter
    sa, ea, ma, ba, inta, nana, infa = decode_format(a_bits, format_a, is_bm_a, support_mxplus)
    sb, eb, mb, bb, intb, nanb, infb = decode_format(b_bits, format_b, is_bm_b, support_mxplus)
    if not (is_bm_a and support_mxplus) and not inta and ea == 0 and (ma & 0x7) == 0: return 0
    if not (is_bm_b and support_mxplus) and not intb and eb == 0 and (mb & 0x7) == 0: return 0
    if (inta and a_bits == 0) or (intb and b_bits == 0): return 0
    prod = ma * mb
    exp_sum = ea + eb - (ba + bb - 7) - (0 if is_bm_a else offset_a) - (0 if is_bm_b else offset_b)
    return align_model(prod, exp_sum, sa ^ sb, round_mode, overflow_wrap, width=aligner_width)

async def reset_dut(dut):
    dut.ena.value = 1; dut.ui_in.value = 0; dut.uio_in.value = 0; dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10); dut.rst_n.value = 1; await ClockCycles(dut.clk, 1)

async def run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a=127, scale_b=127, round_mode=0, overflow_wrap=0, expected_override=None, packed_mode=0, bm_index_a=0, bm_index_b=0, nbm_offset_a=0, nbm_offset_b=0, mx_plus_mode=0, lns_mode=0):
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1) if get_param(dut, "SUPPORT_SERIAL", 0) else 1
    acc_width = get_param(dut, "ACCUMULATOR_WIDTH", 40)
    enable_shared = get_param(dut, "ENABLE_SHARED_SCALING", 1)
    support_mxplus = get_param(dut, "SUPPORT_MX_PLUS", 1)

    if not enable_shared:
        scale_a = 127
        scale_b = 127

    mx_plus_mode = mx_plus_mode if support_mxplus else 0

    dut.ena.value = 1
    # Driving Metadata for Cycle 0
    dut.ui_in.value = (nbm_offset_a & 0x7) | (lns_mode << 3)
    dut.uio_in.value = (nbm_offset_b & 0x7) | (round_mode << 3) | (overflow_wrap << 5) | (packed_mode << 6) | (mx_plus_mode << 7)
    dut.rst_n.value = 0; await ClockCycles(dut.clk, 10); dut.rst_n.value = 1;
    await ClockCycles(dut.clk, 1) # Release reset, Metadata is sampled at this edge.

    # Cycle 1: Scale A
    dut.ui_in.value, dut.uio_in.value = scale_a, (format_a & 0x7) | ((bm_index_a & 0x1F) << 3)
    await ClockCycles(dut.clk, k_factor)
    # Cycle 2: Scale B
    dut.ui_in.value, dut.uio_in.value = scale_b, (format_b & 0x7) | ((bm_index_b & 0x1F) << 3)
    await ClockCycles(dut.clk, k_factor)
    expected_acc, nan_sticky, inf_pos_sticky, inf_neg_sticky = 0, (enable_shared and (scale_a == 0xFF or scale_b == 0xFF)), False, False
    max_val = (1 << (acc_width - 1)) - 1
    min_val = -(1 << (acc_width - 1))

    for i, (a, b) in enumerate(zip(a_elements, b_elements)):
        sa, ea, ma, ba, inta, nana, infa = decode_format(a, format_a, i == bm_index_a, mx_plus_mode)
        sb, eb, mb, bb, intb, nanb, infb = decode_format(b, format_b, i == bm_index_b, mx_plus_mode)
        is_zero_a, is_zero_b = (not inta and ea == 0 and (ma & 0x7) == 0) or (inta and a == 0), (not intb and eb == 0 and (mb & 0x7) == 0) or (intb and b == 0)
        nan_el = nana or nanb or (infa and is_zero_b) or (infb and is_zero_a)
        if nan_el: nan_sticky = True
        elif infa or infb:
            if sa ^ sb: inf_neg_sticky = True
            else: inf_pos_sticky = True
        prod = align_product_model(a, b, format_a, format_b, round_mode, overflow_wrap, i == bm_index_a, i == bm_index_b, mx_plus_mode, nbm_offset_a if mx_plus_mode else 0, nbm_offset_b if mx_plus_mode else 0, lns_mode, acc_width)

        full_sum = expected_acc + prod
        if not overflow_wrap:
            if full_sum > max_val:
                expected_acc = max_val
            elif full_sum < min_val:
                expected_acc = min_val
            else:
                expected_acc = full_sum
        else:
            expected_acc = cast_to_signed(full_sum, acc_width)
    if packed_mode and format_a == 4:
        for i in range(16):
            dut.ui_in.value, dut.uio_in.value = (a_elements[2*i+1] << 4) | a_elements[2*i], (b_elements[2*i+1] << 4) | b_elements[2*i]; await ClockCycles(dut.clk, k_factor)
    else:
        for i in range(32):
            dut.ui_in.value, dut.uio_in.value = a_elements[i], b_elements[i]; await ClockCycles(dut.clk, k_factor)

    # After driving elements, we are at Cycle 35 (Standard) or Cycle 19 (Packed).
    # capture_cycle is 36 (Standard) or 20 (Packed).
    # The first result byte is available at capture_cycle + 1.

    ebits = to_f32_bits(expected_acc, scale_a + scale_b - 254, expected_acc < 0, nan_sticky, inf_pos_sticky, inf_neg_sticky, acc_width)
    expected_final = ebits - 0x100000000 if ebits & 0x80000000 else ebits

    actual_acc = 0
    # Wait for capture cycle (Cycle 36 or 20)
    # We are currently at Cycle 35 (Standard) or 19 (Packed)
    await ClockCycles(dut.clk, k_factor) # Advance to Cycle 36 or 20

    actual_acc = 0
    for i in range(4):
        # Data for byte i is available during logical cycle (capture_cycle + 1 + i)
        # We are at (capture_cycle + i).
        # The next edge takes us to (capture_cycle + 1 + i).
        await ClockCycles(dut.clk, k_factor)
        await Timer(1, "ns") # Sample after the edge
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)

    # Extra cycle to ensure we finish at Cycle 0 of the next block
    await ClockCycles(dut.clk, k_factor)

    if actual_acc & 0x80000000: actual_acc -= 0x100000000
    if expected_override is not None: expected_final = expected_override - 0x100000000 if expected_override & 0x80000000 else expected_override
    dut._log.info(f"Expected: {expected_final}, Actual: {actual_acc}"); assert actual_acc == expected_final

@cocotb.test()
async def test_mxfp8_mac_shared_scale(dut):
    if not get_param(dut, "ENABLE_SHARED_SCALING", 1): return
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32, scale_a=128, scale_b=127)
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32, scale_a=126, scale_b=127)
@cocotb.test()
async def test_mxfp8_mac_e4m3(dut):
    if not get_param(dut, "SUPPORT_E4M3", 1): return
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32)
@cocotb.test()
async def test_mxfp8_mac_e5m2(dut):
    if not get_param(dut, "SUPPORT_E5M2", 1): return
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 1, 1, [0x3C]*32, [0x3C]*32)
@cocotb.test()
async def test_rounding_modes(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    for rm in range(4): await run_mac_test(dut, 0, 0, [0x29]*32, [0x31]*32, round_mode=rm)
@cocotb.test()
async def test_fast_start_scale_compression(dut):
    if not get_param(dut, "ENABLE_SHARED_SCALING", 1): return
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32, scale_a=128, scale_b=127)
    # Cycle 0: drive 0x80 (Fast start)
    dut.ui_in.value, dut.uio_in.value = 0x80, 0; await ClockCycles(dut.clk, 1)
    # Now at Cycle 3.
    expected = 1115684864
    for i in range(32): dut.ui_in.value, dut.uio_in.value = 0x38, 0x38; await ClockCycles(dut.clk, 1)
    # Now at Cycle 35.
    dut.ui_in.value = dut.uio_in.value = 0; await ClockCycles(dut.clk, 1)
    # Now at Cycle 36 (capture_cycle).
    actual = 0
    for i in range(4):
        await ClockCycles(dut.clk, 1) # To Cycle 37, 38, 39, 40
        await Timer(1, "ns"); actual = (actual << 8) | int(dut.uo_out.value)
    if actual & 0x80000000: actual -= 0x100000000
    assert actual == expected

async def run_yaml_file(dut, filename):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    with open(filename, 'r') as f: cases = yaml.safe_load(f)
    for case in cases:
        if case.get('disabled'): continue
        inputs = case['inputs']
        await run_mac_test(dut, inputs['format_a'], inputs.get('format_b', inputs['format_a']), inputs['a_elements'], inputs['b_elements'], inputs.get('scale_a', 127), inputs.get('scale_b', 127), inputs.get('round_mode', 0), inputs.get('overflow_mode', 0), expected_override=case['expected_output'], packed_mode=inputs.get('packed_mode', 0), bm_index_a=inputs.get('bm_index_a', 0), bm_index_b=inputs.get('bm_index_b', 0), nbm_offset_a=inputs.get('nbm_offset_a', 0), nbm_offset_b=inputs.get('nbm_offset_b', 0), mx_plus_mode=inputs.get('mx_plus_mode', 0), lns_mode=inputs.get('lns_mode', 0))

@cocotb.test()
async def test_yaml_cases(dut):
    if not get_param(dut, "SUPPORT_E4M3", 1): return
    await run_yaml_file(dut, "TEST_MX_E2E.yaml")
@cocotb.test()
async def test_mx_fp4_yaml(dut):
    if not get_param(dut, "SUPPORT_MXFP4", 1): return
    await run_yaml_file(dut, "TEST_MX_FP4.yaml")
@cocotb.test()
async def test_min_max_zero_yaml(dut):
    await run_yaml_file(dut, "TEST_MIN_MAX_ZERO.yaml")
@cocotb.test()
async def test_mxplus_yaml(dut):
    if not get_param(dut, "SUPPORT_MX_PLUS", 1): return
    await run_yaml_file(dut, "TEST_MXPLUS.yaml")

@cocotb.test()
async def test_mxfp4_input_buffering(dut):
    if not get_param(dut, "SUPPORT_INPUT_BUFFERING", 1): return
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await reset_dut(dut)
    dut.ena.value, dut.uio_in.value, dut.rst_n.value = 1, 0x40, 0; await ClockCycles(dut.clk, 10); dut.rst_n.value = 1; await ClockCycles(dut.clk, 1)
    dut.ui_in.value, dut.uio_in.value = 127, 4; await ClockCycles(dut.clk, 1)
    dut.ui_in.value, dut.uio_in.value = 127, 4; await ClockCycles(dut.clk, 1)
    for i in range(16): dut.ui_in.value, dut.uio_in.value = 0x22, 0x22; await ClockCycles(dut.clk, 1)
    # At Cycle 19. Capture is 20. Output starts at 21.
    await ClockCycles(dut.clk, 1); # To 20.
    actual = 0
    for i in range(4):
        await ClockCycles(dut.clk, 1) # To 21, 22, 23, 24
        await Timer(1, "ns")
        actual = (actual << 8) | int(dut.uo_out.value)

    await ClockCycles(dut.clk, 1) # to 0
    if actual & 0x80000000: actual -= 0x100000000
    assert actual == 1107296256

@cocotb.test()
async def test_mxfp8_sticky_flags(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32, scale_a=0xFF)
    await run_mac_test(dut, 0, 0, [0x7F]*32, [0x38]*32)

@cocotb.test()
async def test_lns_modes(dut):
    if not get_param(dut, "USE_LNS_MUL", 0): return
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x39]*32, [0x3A]*32, lns_mode=1)

@cocotb.test()
async def test_mxfp8_subnormals(dut):
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 0, 0, [0x01]*32, [0x38]*32)

@cocotb.test()
async def test_lane_overflow(dut):
    if not get_param(dut, "SUPPORT_VECTOR_PACKING", 1): return
    clock = Clock(dut.clk, 10, unit="ns"); cocotb.start_soon(clock.start())
    await run_mac_test(dut, 4, 4, [0x02]*32, [0x02]*32, scale_a=157, scale_b=127, packed_mode=1)
