# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
import yaml
import os

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

def align_model(prod, exp_sum, sign, round_mode=0, overflow_wrap=0, align_width=40):
    shift_amt = exp_sum - 5
    WIDTH = align_width

    if shift_amt >= 0:
        if not overflow_wrap and shift_amt >= WIDTH:
            aligned = (1 << WIDTH) - 1 if prod != 0 else 0
        else:
            aligned = prod << shift_amt
        sticky = 0
        shifted_out = 0
        base = aligned

        # Huge detection: if bits are shifted out of WIDTH-bit window
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

    # The aligner in RTL is hardcoded to 32-bit output with 32-bit saturation logic
    # regardless of ALIGNER_WIDTH.
    if sign:
        if not overflow_wrap and (huge or (aligned >> 32) != 0 or ( (aligned & (1 << 31)) != 0 and (aligned & ((1 << 31) - 1)) != 0 )):
            res = -0x80000000
        else:
            res = -aligned
    else:
        if not overflow_wrap and (huge or (aligned >> 31) != 0):
            res = 0x7FFFFFFF
        else:
            res = aligned

    res_32 = res & 0xFFFFFFFF
    if res_32 & 0x80000000:
        return res_32 - 0x100000000
    return res_32

def get_hw_param(dut, name, default):
    try:
        # Check in the DUT top level (user_project)
        if hasattr(dut.user_project, name):
            return int(getattr(dut.user_project, name).value)
    except:
        pass
    return default

def align_product_model(a_bits, b_bits, format_a, format_b, round_mode=0, overflow_wrap=0,
                        support_e5m2=1, support_mxfp6=1, support_mxfp4=1, support_int8=1, use_lns=0, use_lns_precise=0, align_width=40):
    # Fallback for unsupported formats in hardware
    if not support_e5m2 and (format_a == 1 or format_b == 1): return 0
    if not support_mxfp6 and (format_a in [2, 3] or format_b in [2, 3]): return 0
    if not support_mxfp4 and (format_a == 4 or format_b == 4): return 0
    if not support_int8 and (format_a in [5, 6] or format_b in [5, 6]): return 0

    sa, ea, ma, ba, inta = decode_format(a_bits, format_a)
    sb, eb, mb, bb, intb = decode_format(b_bits, format_b)

    sign = sa ^ sb

    if (not inta and ea == 0) or (not intb and eb == 0):
        return 0
    if (inta and a_bits == 0) or (intb and b_bits == 0):
        return 0

    if use_lns:
        if inta or intb: return 0 # No INT8 support in LNS mode
        if use_lns_precise:
            # Precise LNS LUT logic
            lut = [
                0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7,
                0x1, 0x2, 0x3, 0x4, 0x6, 0x7, 0x8, 0x8,
                0x2, 0x3, 0x4, 0x6, 0x7, 0x8, 0x9, 0x9,
                0x3, 0x4, 0x6, 0x7, 0x8, 0x9, 0xa, 0xa,
                0x4, 0x6, 0x7, 0x8, 0x9, 0xa, 0xa, 0xb,
                0x5, 0x7, 0x8, 0x9, 0xa, 0xb, 0xb, 0xc,
                0x6, 0x8, 0x9, 0xa, 0xa, 0xb, 0xc, 0xd,
                0x7, 0x8, 0x9, 0xa, 0xb, 0xc, 0xd, 0xe
            ]
            m_sum = lut[(ma & 0x7) * 8 + (mb & 0x7)]
        else:
            m_sum = (ma & 0x7) + (mb & 0x7)
        carry = m_sum >> 3
        m_res = m_sum & 0x7
        prod = (8 + m_res) << 3
        exp_sum = ea + eb - (ba + bb - 7) + carry
    else:
        real_ma = (8 + ma) if not inta else ma
        real_mb = (8 + mb) if not intb else mb

        if not support_int8:
            real_ma = real_ma & 0xF
            real_mb = real_mb & 0xF

        prod = real_ma * real_mb
        exp_sum = ea + eb - (ba + bb - 7)

    return align_model(prod, exp_sum, sign, round_mode, overflow_wrap, align_width=align_width)

async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

async def run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a=127, scale_b=127, round_mode=0, overflow_wrap=0, expected_override=None):
    # Detect hardware parameters
    # The default values here match the "Ultra-Tiny" configuration
    support_mixed = get_hw_param(dut, "SUPPORT_MIXED_PRECISION", 0)
    support_adv = get_hw_param(dut, "SUPPORT_ADV_ROUNDING", 0)
    support_e5m2 = get_hw_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp6 = get_hw_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_hw_param(dut, "SUPPORT_MXFP4", 0)
    support_int8 = get_hw_param(dut, "SUPPORT_INT8", 0)
    support_pipe = get_hw_param(dut, "SUPPORT_PIPELINING", 0)
    support_shared = get_hw_param(dut, "ENABLE_SHARED_SCALING", 0)
    acc_width = get_hw_param(dut, "ACCUMULATOR_WIDTH", 24)
    align_width = get_hw_param(dut, "ALIGNER_WIDTH", 32)
    use_lns = get_hw_param(dut, "USE_LNS_MUL", 0)
    use_lns_precise = get_hw_param(dut, "USE_LNS_MUL_PRECISE", 0)

    dut._log.info(f"Detected Params: PIPE={support_pipe}, MIX={support_mixed}, ADV={support_adv}, E5M2={support_e5m2}, MXFP6={support_mxfp6}, MXFP4={support_mxfp4}, INT8={support_int8}, SHARED={support_shared}, ACC={acc_width}, ALIGN={align_width}")

    if not support_mixed:
        format_b = format_a

    if not support_adv:
        if round_mode in [1, 2]: # CEL, FLR
            round_mode = 0 # Fallback to TRN in model

    await reset_dut(dut)

    # Cycle 1: Load Scale A and Format/Numerical Control
    dut.ui_in.value = scale_a
    dut.uio_in.value = format_a | (round_mode << 3) | (overflow_wrap << 5)
    await ClockCycles(dut.clk, 1)

    # Cycle 2: Load Scale B and Format B
    dut.ui_in.value = scale_b
    dut.uio_in.value = format_b
    await ClockCycles(dut.clk, 1)

    expected_acc = 0
    # Process elements in groups of 32
    for i in range(32):
        a = a_elements[i]
        b = b_elements[i]
        prod = align_product_model(a, b, format_a, format_b, round_mode, overflow_wrap,
                                   support_e5m2, support_mxfp6, support_mxfp4, support_int8, use_lns, use_lns_precise, align_width=align_width)

        mask = (1 << acc_width) - 1
        acc_masked = expected_acc & mask
        prod_masked = prod & mask

        # Accumulator bit-width truncation of the aligned product
        # The hardware does: data_in(aligned_res[ACCUMULATOR_WIDTH-1:0])
        prod_masked_signed = prod_masked
        if prod_masked_signed & (1 << (acc_width - 1)):
            prod_masked_signed -= (1 << acc_width)

        acc_masked_signed = acc_masked
        if acc_masked_signed & (1 << (acc_width - 1)):
            acc_masked_signed -= (1 << acc_width)

        sum_raw = acc_masked_signed + prod_masked_signed

        # Signed overflow check for the accumulator
        s_acc = (acc_masked >> (acc_width - 1)) & 1
        s_prod = (prod_masked >> (acc_width - 1)) & 1

        sum_masked = sum_raw & mask
        s_res = (sum_masked >> (acc_width - 1)) & 1

        if not overflow_wrap and (s_acc == s_prod) and (s_acc != s_res):
            expected_acc = (1 << (acc_width - 1)) - 1 if s_acc == 0 else -(1 << (acc_width - 1))
        else:
            if sum_masked & (1 << (acc_width - 1)):
                expected_acc = sum_masked - (1 << acc_width)
            else:
                expected_acc = sum_masked

        dut.ui_in.value = a
        dut.uio_in.value = b
        await ClockCycles(dut.clk, 1)

    # Cycle 35: Pipeline flush
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 1)

    # Cycle 36: Shared scaling alignment
    await ClockCycles(dut.clk, 1)

    # Calculate expected final result
    if support_shared:
        shared_exp = scale_a + scale_b - 254
        acc_abs = abs(expected_acc)
        acc_sign = 1 if expected_acc < 0 else 0
        expected_final = align_model(acc_abs, shared_exp + 5, acc_sign, round_mode, overflow_wrap, align_width=align_width)
    else:
        # Sign-extend acc_out to 32 bits
        expected_final = expected_acc

    # Cycle 37-40: Output Serialized Result
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, 1)

    if actual_acc & 0x80000000:
        actual_acc -= 0x100000000

    if expected_override is not None:
        expected_final = expected_override

    format_names = ["E4M3", "E5M2", "E3M2", "E2M3", "E2M1", "INT8", "INT8_SYM"]
    name_a = format_names[format_a] if format_a < len(format_names) else "Unknown"
    name_b = format_names[format_b] if format_b < len(format_names) else "Unknown"
    dut._log.info(f"Format: {name_a}x{name_b}, RM: {round_mode}, Wrap: {overflow_wrap}, Scales: {scale_a},{scale_b}, Expected: {expected_final}, Actual: {actual_acc}")
    assert actual_acc == expected_final

@cocotb.test()
async def test_mxfp8_mac_shared_scale(dut):
    dut._log.info("Start MXFP8 MAC Shared Scale Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x38] * 32
    b_elements = [0x38] * 32
    await run_mac_test(dut, 0, 0, a_elements, b_elements, scale_a=128, scale_b=127)
    await run_mac_test(dut, 0, 0, a_elements, b_elements, scale_a=126, scale_b=127)

@cocotb.test()
async def test_mxfp8_mac_e4m3(dut):
    dut._log.info("Start MXFP8 MAC Test (E4M3)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x38] * 32
    b_elements = [0x38] * 32
    await run_mac_test(dut, 0, 0, a_elements, b_elements)

@cocotb.test()
async def test_mxfp8_mac_e5m2(dut):
    dut._log.info("Start MXFP8 MAC Test (E5M2)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x3C] * 32
    b_elements = [0x3C] * 32
    await run_mac_test(dut, 1, 1, a_elements, b_elements)

@cocotb.test()
async def test_rounding_modes(dut):
    support_adv = get_hw_param(dut, "SUPPORT_ADV_ROUNDING", 0)
    if not support_adv:
        dut._log.info("Skipping Rounding Modes Test (SUPPORT_ADV_ROUNDING=0)")
        return
    dut._log.info("Start Rounding Modes Test")
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
    dut._log.info("Start Overflow Saturation Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x7C] * 32
    b_elements = [0x7C] * 32
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=0)
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=1)

@cocotb.test()
async def test_accumulator_saturation(dut):
    dut._log.info("Start Accumulator Saturation Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x78] * 32
    b_elements = [0x78] * 32
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=0)
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=1)

@cocotb.test()
async def test_mixed_precision(dut):
    support_mixed = get_hw_param(dut, "SUPPORT_MIXED_PRECISION", 0)
    if not support_mixed:
        dut._log.info("Skipping Mixed-Precision MAC Test (SUPPORT_MIXED_PRECISION=0)")
        return
    dut._log.info("Start Mixed-Precision MAC Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x38] * 32
    b_elements = [0x3C] * 32
    await run_mac_test(dut, 0, 1, a_elements, b_elements)

@cocotb.test()
async def test_mxfp_mac_randomized(dut):
    import random
    support_e5m2 = get_hw_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp6 = get_hw_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_hw_param(dut, "SUPPORT_MXFP4", 0)
    support_adv = get_hw_param(dut, "SUPPORT_ADV_ROUNDING", 0)
    support_mixed = get_hw_param(dut, "SUPPORT_MIXED_PRECISION", 0)
    dut._log.info(f"Start Randomized MXFP MAC Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    allowed_formats = [0, 5, 6]
    if support_e5m2: allowed_formats.append(1)
    if support_mxfp6: allowed_formats.extend([2, 3])
    if support_mxfp4: allowed_formats.append(4)
    for i in range(50):
        format_a = random.choice(allowed_formats)
        format_b = random.choice(allowed_formats) if support_mixed else format_a
        round_mode = random.randint(0, 3) if support_adv else 0
        overflow_wrap = random.randint(0, 1)
        scale_a = random.randint(110, 140)
        scale_b = random.randint(110, 140)
        a_elements = [random.randint(0, 255) for _ in range(32)]
        b_elements = [random.randint(0, 255) for _ in range(32)]
        await run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a, scale_b, round_mode, overflow_wrap)

@cocotb.test()
async def test_fast_start_scale_compression(dut):
    dut._log.info("Start Fast Start (Scale Compression) Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    format_a = 0
    format_b = 0
    scale_a = 127
    scale_b = 127
    a_elements = [0x38] * 32
    b_elements = [0x38] * 32
    # Normal Start
    await run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a, scale_b)
    # Fast Start
    dut.ui_in.value = 0x80
    await ClockCycles(dut.clk, 1)
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
    # Re-calculate expected for this simple case
    expected = 32 * 256 # 8192
    assert actual_acc == expected

@cocotb.test()
async def test_yaml_cases(dut):
    dut._log.info("Start YAML E2E Test Cases")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    yaml_path = os.path.join(os.path.dirname(__file__), "TEST_MX_E2E.YAML")
    if not os.path.exists(yaml_path): return
    with open(yaml_path, 'r') as f: cases = yaml.safe_load(f)
    support_e5m2 = get_hw_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp6 = get_hw_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_hw_param(dut, "SUPPORT_MXFP4", 0)
    support_int8 = get_hw_param(dut, "SUPPORT_INT8", 0)
    support_adv = get_hw_param(dut, "SUPPORT_ADV_ROUNDING", 0)
    support_mixed = get_hw_param(dut, "SUPPORT_MIXED_PRECISION", 0)
    support_shared = get_hw_param(dut, "ENABLE_SHARED_SCALING", 0)
    for case in cases:
        inputs = case['inputs']
        fmt_a = inputs['format_a']
        fmt_b = inputs.get('format_b', fmt_a)
        if not support_e5m2 and (fmt_a == 1 or fmt_b == 1): continue
        if not support_mxfp6 and (fmt_a in [2, 3] or fmt_b in [2, 3]): continue
        if not support_mxfp4 and (fmt_a == 4 or fmt_b == 4): continue
        if not support_int8 and (fmt_a in [5, 6] or fmt_b in [5, 6]): continue
        if not support_mixed and (fmt_a != fmt_b): continue
        if not support_shared and (inputs.get('scale_a', 127) != 127 or inputs.get('scale_b', 127) != 127): continue
        if not support_adv and inputs.get('round_mode', 0) in [1, 2]: continue
        await run_mac_test(dut, fmt_a, fmt_b, inputs['a_elements'], inputs['b_elements'],
                           inputs.get('scale_a', 127), inputs.get('scale_b', 127),
                           inputs.get('round_mode', 0), inputs.get('overflow_mode', 0), expected_override=case['expected_output'])
