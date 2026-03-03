# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
import yaml
import os

def decode_format(bits, format_val, is_bm=False, support_mxplus=False):
    if format_val == 0: # E4M3
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
        return sign, exp, mant, bias, is_int
    elif format_val == 1: # E5M2
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
        return sign, exp, mant, bias, is_int
    elif format_val == 2: # E3M2
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
        return sign, exp, mant, bias, is_int
    elif format_val == 3: # E2M3
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
        return sign, exp, mant, bias, is_int
    elif format_val == 4: # E2M1
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
        return sign, exp, mant, bias, is_int
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

def align_model(prod, exp_sum, sign, round_mode=0, overflow_wrap=0, width=40):
    shift_amt = exp_sum - 5
    WIDTH = width

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

    if sign:
        # Check saturation for negative
        # Magnitude > 2^31 saturates to -2^31
        # In RTL: (huge || |rounded[WIDTH-1:32] || (rounded[31] && |rounded[30:0]))
        if not overflow_wrap and (huge or (aligned >> 32) != 0 or ( (aligned & (1 << 31)) != 0 and (aligned & ((1 << 31) - 1)) != 0 )):
            res = -0x80000000
        else:
            res = -aligned
    else:
        # Magnitude > 2^31-1 saturates to 2^31-1
        # In RTL: (huge || |rounded[WIDTH-1:31])
        if not overflow_wrap and (huge or (aligned >> 31) != 0):
            res = 0x7FFFFFFF
        else:
            res = aligned

    # Return as 32-bit signed integer
    res_32 = res & 0xFFFFFFFF
    if res_32 & 0x80000000:
        return res_32 - 0x100000000
    return res_32

def get_param(dut, name, default=1):
    # 1. Try to get from dut.user_project (RTL) or dut (some TB configs)
    for obj in [getattr(dut, "user_project", None), dut]:
        if obj is None: continue
        try:
            handle = getattr(obj, name)
            return int(handle.value)
        except Exception:
            pass

    # 2. Try to get from COMPILE_ARGS environment variable
    compile_args = os.environ.get("COMPILE_ARGS", "")
    import re
    # Match both -P name=val and -P tb.name=val
    matches = re.findall(r"-P\s+(?:\w+\.)?" + name + r"=(\d+)", compile_args)
    if matches:
        return int(matches[-1]) # Use the last one if multiple

    # 3. Fallback to hardcoded defaults in tb.v (which we just updated to Ultra-Tiny)
    defaults = {
        "ALIGNER_WIDTH": 32,
        "ACCUMULATOR_WIDTH": 24,
        "SUPPORT_E5M2": 0,
        "SUPPORT_MXFP6": 0,
        "SUPPORT_MXFP4": 1,
        "SUPPORT_INT8": 0,
        "SUPPORT_PIPELINING": 0,
        "SUPPORT_ADV_ROUNDING": 0,
        "SUPPORT_MIXED_PRECISION": 0,
    "SUPPORT_VECTOR_PACKING": 0,
    "SUPPORT_PACKED_SERIAL": 0,
    "SUPPORT_MX_PLUS": 0,
    "SUPPORT_SERIAL": 0,
    "SERIAL_K_FACTOR": 1,
        "ENABLE_SHARED_SCALING": 0,
        "USE_LNS_MUL": 0,
        "USE_LNS_MUL_PRECISE": 0,
        "SHORT_PROTOCOL": 0
    }
    return defaults.get(name, default)

def align_product_model(a_bits, b_bits, format_a, format_b, round_mode=0, overflow_wrap=0,
                        support_e5m2=1, support_mxfp6=1, support_mxfp4=1, support_int8=1, use_lns=0, use_lns_precise=0, aligner_width=40,
                        is_bm_a=False, is_bm_b=False, support_mxplus=False, offset_a=0, offset_b=0):
    # Fallback for unsupported formats in hardware
    if not support_e5m2 and format_a == 1: return 0
    if not support_e5m2 and format_b == 1: return 0
    if not support_mxfp6 and format_a in [2, 3]: return 0
    if not support_mxfp6 and format_b in [2, 3]: return 0
    if not support_mxfp4 and format_a == 4: return 0
    if not support_mxfp4 and format_b == 4: return 0
    if not support_int8 and format_a in [5, 6]: return 0
    if not support_int8 and format_b in [5, 6]: return 0

    sa, ea, ma, ba, inta = decode_format(a_bits, format_a, is_bm_a, support_mxplus)
    sb, eb, mb, bb, intb = decode_format(b_bits, format_b, is_bm_b, support_mxplus)

    sign = sa ^ sb

    # Updated: zero check now correctly handles subnormals
    # For MX+, zero_out is forced to 0 for BM elements
    if not (is_bm_a and support_mxplus):
        if (not inta and ea == 0 and (ma & 0x7) == 0): return 0
    if not (is_bm_b and support_mxplus):
        if (not intb and eb == 0 and (mb & 0x7) == 0): return 0
    if (inta and a_bits == 0) or (intb and b_bits == 0):
        return 0

    adj_a = 0 if is_bm_a else offset_a
    adj_b = 0 if is_bm_b else offset_b

    if use_lns:
        if inta or intb: return 0 # No INT8 support in LNS mode
        if support_mxplus and (is_bm_a or is_bm_b):
            # To maintain the precision benefits of MX+, BM elements use a standard multiplier
            prod = ma * mb
            exp_sum = ea + eb - (ba + bb - 7) - adj_a - adj_b
        else:
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
            exp_sum = ea + eb - (ba + bb - 7) + carry - adj_a - adj_b
    else:
        real_ma = ma if not inta else ma
        real_mb = mb if not intb else mb

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

async def run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a=127, scale_b=127, round_mode=0, overflow_wrap=0, expected_override=None, packed_mode=0, bm_index_a=0, bm_index_b=0, nbm_offset_a=0, nbm_offset_b=0, mx_plus_mode=0):
    # Enforce parameter constraints in model
    support_mixed = get_param(dut, "SUPPORT_MIXED_PRECISION", 0)
    if not support_mixed:
        format_b = format_a

    support_mxplus_hw = get_param(dut, "SUPPORT_MX_PLUS", 0)
    support_mxplus = support_mxplus_hw and mx_plus_mode
    support_packing = get_param(dut, "SUPPORT_VECTOR_PACKING", 0)
    support_serial = get_param(dut, "SUPPORT_PACKED_SERIAL", 0)
    actual_packed = support_packing and packed_mode and (format_a == 4) and (format_b == 4)
    actual_serial = support_serial and not support_packing and packed_mode and (format_a == 4) and (format_b == 4)

    # Tiny-Serial timing parameters
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1)
    cycles_per_element = k_factor

    support_adv = get_param(dut, "SUPPORT_ADV_ROUNDING", 0)
    if not support_adv:
        if round_mode in [1, 2]: # CEL, FLR
            round_mode = 0 # Fallback to TRN in model to match hardware fallback

    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp6 = get_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    support_int8 = get_param(dut, "SUPPORT_INT8", 0)
    use_lns = get_param(dut, "USE_LNS_MUL", 0)
    use_lns_precise = get_param(dut, "USE_LNS_MUL_PRECISE", 0)
    acc_width = get_param(dut, "ACCUMULATOR_WIDTH", 32)
    aligner_width = get_param(dut, "ALIGNER_WIDTH", 40)
    short_protocol = get_param(dut, "SHORT_PROTOCOL", 0)

    # Custom reset to handle Cycle 0 sampling
    dut.ena.value = 1
    if short_protocol:
        # SHORT_PROTOCOL captures metadata in Cycle 0
        dut.ui_in.value = 0
        dut.uio_in.value = format_a | (round_mode << 3) | (overflow_wrap << 5) | (packed_mode << 6) | (mx_plus_mode << 7)
    elif support_mxplus_hw:
        dut.ui_in.value = (nbm_offset_b & 0x7)
        dut.uio_in.value = (bm_index_a & 0x1F) | ((nbm_offset_a & 0x7) << 5)
    else:
        dut.ui_in.value = 0
        dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1) # This edge samples Cycle 0 and moves to Cycle 1

    if not short_protocol:
        # Cycle 1: Load Scale A and Format/Numerical Control
        dut.ui_in.value = scale_a
        # For MX+, we use bit 7 of Cycle 1 to enable the extension semantics.
        dut.uio_in.value = format_a | (round_mode << 3) | (overflow_wrap << 5) | (packed_mode << 6) | (mx_plus_mode << 7)
        await ClockCycles(dut.clk, cycles_per_element)

        # Cycle 2: Load Scale B and Format B
        dut.ui_in.value = scale_b
        if support_mxplus:
            dut.uio_in.value = (format_b & 0x7) | ((bm_index_b & 0x1F) << 3)
        else:
            dut.uio_in.value = format_b
        await ClockCycles(dut.clk, cycles_per_element)

    expected_acc = 0
    # Process elements in groups of 32
    for i, (a, b) in enumerate(zip(a_elements, b_elements)):
        is_bm_a_cur = (i == bm_index_a)
        is_bm_b_cur = (i == bm_index_b)

        prod = align_product_model(a, b, format_a, format_b, round_mode, overflow_wrap,
                                   support_e5m2, support_mxfp6, support_mxfp4, support_int8, use_lns, use_lns_precise, aligner_width=aligner_width,
                                   is_bm_a=is_bm_a_cur, is_bm_b=is_bm_b_cur, support_mxplus=support_mxplus,
                                   offset_a=nbm_offset_a if mx_plus_mode else 0,
                                   offset_b=nbm_offset_b if mx_plus_mode else 0)

        mask = (1 << acc_width) - 1
        acc_masked = expected_acc & mask
        prod_masked = prod & mask
        sum_masked = (acc_masked + prod_masked) & mask

        # Signed overflow check
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

    if actual_packed:
        for i in range(16):
            dut.ui_in.value = (a_elements[2*i+1] << 4) | a_elements[2*i]
            dut.uio_in.value = (b_elements[2*i+1] << 4) | b_elements[2*i]
            await ClockCycles(dut.clk, cycles_per_element)
    elif actual_serial:
        for i in range(16):
            # Odd cycle: send packed byte
            dut.ui_in.value = (a_elements[2*i+1] << 4) | a_elements[2*i]
            dut.uio_in.value = (b_elements[2*i+1] << 4) | b_elements[2*i]
            await ClockCycles(dut.clk, cycles_per_element)
            # Even cycle: wait (hardware uses buffer)
            # ui_in/uio_in can be anything, they are ignored
            await ClockCycles(dut.clk, cycles_per_element)
    else:
        for i in range(32):
            dut.ui_in.value = a_elements[i]
            dut.uio_in.value = b_elements[i]
            await ClockCycles(dut.clk, cycles_per_element)

    # Pipeline flush for last element
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, cycles_per_element)

    # Shared scaling alignment
    await ClockCycles(dut.clk, cycles_per_element)

    # Calculate expected final result after shared scaling
    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    if support_shared:
        shared_exp = scale_a + scale_b - 254
        acc_abs = abs(expected_acc)
        acc_sign = 1 if expected_acc < 0 else 0
        expected_final = align_model(acc_abs, shared_exp + 5, acc_sign, round_mode, overflow_wrap, width=aligner_width)
    else:
        # If no shared scaling, the result is sign-extended to 32-bit in hardware
        if expected_acc < 0:
            expected_final = (expected_acc & 0xFFFFFFFF) - 0x100000000
        else:
            expected_final = expected_acc

    # Cycle 37-40 (or 21-24): Output Serialized Result
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, cycles_per_element)

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

    a_elements = [0x38] * 32 # 1.0 in E4M3
    b_elements = [0x38] * 32

    # Scale A = 128 (2^1), Scale B = 127 (2^0) -> Total scale 2^1
    # Expected: 32 * 1.0 * 2^1 = 64
    # In fixed point (bit 8=1), 64 is 64*256 = 16384
    await run_mac_test(dut, 0, 0, a_elements, b_elements, scale_a=128, scale_b=127)

    # Scale A = 126 (2^-1), Scale B = 127 (2^0) -> Total scale 2^-1
    # Expected: 32 * 1.0 * 2^-1 = 16
    # In fixed point, 16 is 16*256 = 4096
    await run_mac_test(dut, 0, 0, a_elements, b_elements, scale_a=126, scale_b=127)

@cocotb.test()
async def test_mxfp8_mac_e4m3(dut):
    dut._log.info("Start MXFP8 MAC Test (E4M3)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x38] * 32 # 1.0 in E4M3
    b_elements = [0x38] * 32
    await run_mac_test(dut, 0, 0, a_elements, b_elements)

@cocotb.test()
async def test_mxfp8_mac_e5m2(dut):
    dut._log.info("Start MXFP8 MAC Test (E5M2)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x3C] * 32 # 1.0 in E5M2
    b_elements = [0x3C] * 32
    await run_mac_test(dut, 1, 1, a_elements, b_elements)

@cocotb.test()
async def test_rounding_modes(dut):
    # Check if advanced rounding is supported
    support_adv = get_param(getattr(dut.user_project, "SUPPORT_ADV_ROUNDING", None), "SUPPORT_ADV_ROUNDING", 1)
    if not support_adv:
        dut._log.info("Skipping Rounding Modes Test (SUPPORT_ADV_ROUNDING=0)")
        return

    dut._log.info("Start Rounding Modes Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = [0x29] * 32
    b_elements = [0x31] * 32

    # TRN: 40 * 32 = 1280
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=0)
    # CEL: (40+1) * 32 = 1312
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=1)
    # FLR: 40 * 32 = 1280 (positive)
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=2)
    # RNE: 81 >> 1 = 40.5. Ties to even. 40 is even. So 40.
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=3)

    # Negative test
    a_elements = [0xA9] * 32 # -0.28125
    b_elements = [0x31] * 32 # 0.5625
    # a*b = -0.158203125. Fixed point magnitude = 40.5.
    # TRN: -40 * 32 = -1280
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=0)
    # CEL: -40 * 32 = -1280 (negative, ceil towards 0)
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=1)
    # FLR: -(40+1) * 32 = -1312
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=2)
    # RNE: -40 * 32 = -1280
    await run_mac_test(dut, 0, 0, a_elements, b_elements, round_mode=3)

@cocotb.test()
async def test_overflow_saturation(dut):
    dut._log.info("Start Overflow Saturation Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = [0x7C] * 32 # Max finite E5M2
    b_elements = [0x7C] * 32

    # Saturation
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=0)
    # Wrap
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=1)

@cocotb.test()
async def test_accumulator_saturation(dut):
    dut._log.info("Start Accumulator Saturation Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = [0x78] * 32 # E5M2: ea=30
    b_elements = [0x78] * 32

    # Accumulator Saturation
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=0)
    # Accumulator Wrap
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=1)

@cocotb.test()
async def test_mxfp4_packed_serial(dut):
    # Check if serial vector packing is supported
    support_serial = get_param(getattr(dut.user_project, "SUPPORT_PACKED_SERIAL", None), "SUPPORT_PACKED_SERIAL", 0)
    if not support_serial:
        dut._log.info("Skipping Serial Packed FP4 Test (SUPPORT_PACKED_SERIAL=0)")
        return

    dut._log.info("Start Serial Packed FP4 Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = [0x04] * 32 # 1.0 in E2M1
    b_elements = [0x04] * 32
    # Expected: 32 * 1.0 * 1.0 = 32. Fixed bit 8=1 -> 32*256 = 8192
    await run_mac_test(dut, 4, 4, a_elements, b_elements, packed_mode=1)

@cocotb.test()
async def test_mxfp4_packed(dut):
    # Check if vector packing is supported
    support_packing = get_param(getattr(dut.user_project, "SUPPORT_VECTOR_PACKING", None), "SUPPORT_VECTOR_PACKING", 0)
    if not support_packing:
        dut._log.info("Skipping Packed FP4 Test (SUPPORT_VECTOR_PACKING=0)")
        return

    dut._log.info("Start Packed FP4 Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = [0x04] * 32 # 1.0 in E2M1
    b_elements = [0x04] * 32
    # Expected: 32 * 1.0 * 1.0 = 32. Fixed bit 8=1 -> 32*256 = 8192
    await run_mac_test(dut, 4, 4, a_elements, b_elements, packed_mode=1)

@cocotb.test()
async def test_mixed_precision(dut):
    # Check if mixed precision is supported
    support_mixed = get_param(getattr(dut.user_project, "SUPPORT_MIXED_PRECISION", None), "SUPPORT_MIXED_PRECISION", 1)
    if not support_mixed:
        dut._log.info("Skipping Mixed-Precision MAC Test (SUPPORT_MIXED_PRECISION=0)")
        return

    dut._log.info("Start Mixed-Precision MAC Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # E4M3 x E5M2
    a_elements = [0x38] * 32 # 1.0 in E4M3
    b_elements = [0x3C] * 32 # 1.0 in E5M2
    await run_mac_test(dut, 0, 1, a_elements, b_elements)

    # E3M2 x INT8
    a_elements = [0x10] * 32 # 1.0 in E3M2
    b_elements = [0x40] * 32 # 64 in INT8 (which is 1.0 with 2^-6 scale)
    await run_mac_test(dut, 2, 5, a_elements, b_elements)

@cocotb.test()
async def test_mxfp_mac_randomized(dut):
    import random

    support_e5m2 = get_param(getattr(dut.user_project, "SUPPORT_E5M2", None), "SUPPORT_E5M2", 1)
    support_mxfp6 = get_param(getattr(dut.user_project, "SUPPORT_MXFP6", None), "SUPPORT_MXFP6", 1)
    support_mxfp4 = get_param(getattr(dut.user_project, "SUPPORT_MXFP4", None), "SUPPORT_MXFP4", 1)
    support_adv = get_param(getattr(dut.user_project, "SUPPORT_ADV_ROUNDING", None), "SUPPORT_ADV_ROUNDING", 1)
    support_mixed = get_param(getattr(dut.user_project, "SUPPORT_MIXED_PRECISION", None), "SUPPORT_MIXED_PRECISION", 1)

    dut._log.info(f"Start Randomized MXFP MAC Test (E5M2={support_e5m2}, MXFP6={support_mxfp6}, MXFP4={support_mxfp4}, ADV={support_adv}, MIX={support_mixed})")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    allowed_formats = [0, 5, 6]
    if support_e5m2: allowed_formats.append(1)
    if support_mxfp6: allowed_formats.extend([2, 3])
    if support_mxfp4: allowed_formats.append(4)

    for i in range(50):
        format_a = random.choice(allowed_formats)
        format_b = random.choice(allowed_formats) if support_mixed else format_a
        round_mode = random.randint(0, 3) if support_adv else random.choice([0, 3]) # Only TRN and RNE if no ADV
        overflow_wrap = random.randint(0, 1)
        scale_a = random.randint(110, 140) # Keep range reasonable for test
        scale_b = random.randint(110, 140)
        a_elements = [random.randint(0, 255) for _ in range(32)]
        b_elements = [random.randint(0, 255) for _ in range(32)]
        await run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a, scale_b, round_mode, overflow_wrap)

@cocotb.test()
async def test_fast_start_scale_compression(dut):
    # Skip if short protocol is enabled as it uses a different Cycle 0 behavior
    short_protocol = get_param(dut, "SHORT_PROTOCOL", 0)
    if short_protocol:
        dut._log.info("Skipping Fast Start Test (SHORT_PROTOCOL=1)")
        return

    dut._log.info("Start Fast Start (Scale Compression) Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    format_a = 0 # E4M3
    format_b = 0
    scale_a = 128
    scale_b = 127
    a_elements = [0x38] * 32 # 1.0
    b_elements = [0x38] * 32

    support_mxplus_hw = get_param(dut, "SUPPORT_MX_PLUS", 0)
    acc_width = get_param(dut, "ACCUMULATOR_WIDTH", 32)
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1)

    # 1. Normal Start
    await run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a, scale_b)

    # 2. Fast Start (Reuse scales)
    # We can't use run_mac_test as is because it does a reset.
    # Manual protocol for fast start:

    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    support_int8 = get_param(dut, "SUPPORT_INT8", 0)
    use_lns_precise = get_param(dut, "USE_LNS_MUL_PRECISE", 0)

    # Cycle 0: IDLE. Set Fast Start bit ui_in[7]
    dut.ui_in.value = 0x80
    await ClockCycles(dut.clk, k_factor)

    # Now at Cycle 3
    support_mxfp6 = get_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    use_lns = get_param(dut, "USE_LNS_MUL", 0)
    aligner_width = get_param(dut, "ALIGNER_WIDTH", 40)

    expected_acc = 0
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    for a, b in zip(a_elements, b_elements):
        prod = align_product_model(a, b, format_a, format_b,
                                   support_e5m2=support_e5m2, support_mxfp6=support_mxfp6, support_mxfp4=support_mxfp4, support_int8=support_int8, use_lns=use_lns, use_lns_precise=use_lns_precise, aligner_width=aligner_width)

        mask = (1 << acc_width) - 1
        acc_masked = expected_acc & mask
        prod_masked = prod & mask
        sum_masked = (acc_masked + prod_masked) & mask
        if sum_masked & (1 << (acc_width - 1)):
            expected_acc = sum_masked - (1 << acc_width)
        else:
            expected_acc = sum_masked

    if support_shared:
        shared_exp = scale_a + scale_b - 254
        acc_abs = abs(expected_acc)
        acc_sign = 1 if expected_acc < 0 else 0
        expected_final = align_model(acc_abs, shared_exp + 5, acc_sign, width=aligner_width)
    else:
        expected_final = expected_acc

    for i in range(32):
        dut.ui_in.value = a_elements[i]
        dut.uio_in.value = b_elements[i]
        await ClockCycles(dut.clk, k_factor)

    await ClockCycles(dut.clk, 2 * k_factor) # Flush + Shared Scale

    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor)

    if actual_acc & 0x80000000: actual_acc -= 0x100000000
    assert actual_acc == expected_final

async def run_yaml_file(dut, filename):
    dut._log.info(f"Start YAML Test Cases from {filename}")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    yaml_path = os.path.join(os.path.dirname(__file__), filename)
    if not os.path.exists(yaml_path):
        dut._log.error(f"YAML file not found at {yaml_path}")
        return

    with open(yaml_path, 'r') as f:
        cases = yaml.safe_load(f)

    if not cases:
        dut._log.warning(f"No test cases found in {filename}")
        return

    # Detect hardware support
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp6 = get_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    support_int8 = get_param(dut, "SUPPORT_INT8", 0)
    support_adv = get_param(dut, "SUPPORT_ADV_ROUNDING", 0)
    support_mixed = get_param(dut, "SUPPORT_MIXED_PRECISION", 0)
    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    use_lns = get_param(dut, "USE_LNS_MUL", 0)
    use_lns_precise = get_param(dut, "USE_LNS_MUL_PRECISE", 0)
    for case in cases:
        if case.get('disabled', False):
            dut._log.info(f"Skipping Case {case.get('test_case', 'unknown')}: Disabled in YAML")
            continue

        inputs = case['inputs']
        expected = case['expected_output']
        comment = case.get('comment', '')

        # Skip cases based on hardware support
        fmt_a = inputs['format_a']
        fmt_b = inputs.get('format_b', fmt_a)

        if not support_e5m2 and (fmt_a == 1 or fmt_b == 1):
            dut._log.info(f"Skipping Case {case['test_case']}: E5M2 not supported")
            continue
        if not support_mxfp6 and (fmt_a in [2, 3] or fmt_b in [2, 3]):
            dut._log.info(f"Skipping Case {case['test_case']}: MXFP6 not supported")
            continue
        if not support_mxfp4 and (fmt_a == 4 or fmt_b == 4):
            dut._log.info(f"Skipping Case {case['test_case']}: MXFP4 not supported")
            continue
        if not support_int8 and (fmt_a in [5, 6] or fmt_b in [5, 6]):
            dut._log.info(f"Skipping Case {case['test_case']}: INT8 not supported")
            continue
        if use_lns and (fmt_a in [5, 6] or fmt_b in [5, 6]):
            dut._log.info(f"Skipping Case {case['test_case']}: INT8 not supported in LNS mode")
            continue
        if not support_mixed and (fmt_a != fmt_b):
            dut._log.info(f"Skipping Case {case['test_case']}: Mixed Precision not supported")
            continue
        if not support_shared and (inputs.get('scale_a', 127) != 127 or inputs.get('scale_b', 127) != 127):
            dut._log.info(f"Skipping Case {case['test_case']}: Shared Scaling not supported")
            continue
        if not support_adv and inputs.get('round_mode', 0) in [1, 2]:
            dut._log.info(f"Skipping Case {case['test_case']}: Advanced Rounding not supported")
            continue

        dut._log.info(f"Running Case {case['test_case']}: {comment}")
        await run_mac_test(dut,
                           format_a=fmt_a,
                           format_b=fmt_b,
                           a_elements=inputs['a_elements'],
                           b_elements=inputs['b_elements'],
                           scale_a=inputs.get('scale_a', 127),
                           scale_b=inputs.get('scale_b', 127),
                           round_mode=inputs.get('round_mode', 0),
                           overflow_wrap=inputs.get('overflow_mode', 0),
                           expected_override=expected,
                           packed_mode=inputs.get('packed_mode', 0),
                           bm_index_a=inputs.get('bm_index_a', 0),
                           bm_index_b=inputs.get('bm_index_b', 0),
                           nbm_offset_a=inputs.get('nbm_offset_a', 0),
                           nbm_offset_b=inputs.get('nbm_offset_b', 0),
                           mx_plus_mode=inputs.get('mx_plus_mode', 0))

@cocotb.test()
async def test_yaml_cases(dut):
    await run_yaml_file(dut, "TEST_MX_E2E.YAML")

@cocotb.test()
async def test_mx_fp4_yaml(dut):
    await run_yaml_file(dut, "TEST_MX_FP4.yaml")

@cocotb.test()
async def test_mxplus_yaml(dut):
    if os.environ.get("GATES") == "yes":
        dut._log.info("Skipping MX+ YAML Test in Gate-Level Simulation")
        return
    support_mxplus = get_param(dut, "SUPPORT_MX_PLUS", 0)
    if not support_mxplus:
        dut._log.info("Skipping MX+ YAML Test (SUPPORT_MX_PLUS=0)")
        return
    await run_yaml_file(dut, "TEST_MXPLUS.yaml")

@cocotb.test()
async def test_mxfp4_short_protocol(dut):
    # Check if short protocol is supported
    short_protocol = get_param(dut, "SHORT_PROTOCOL", 0)
    if not short_protocol:
        dut._log.info("Skipping Short Protocol FP4 Test (SHORT_PROTOCOL=0)")
        return

    dut._log.info("Start Short Protocol FP4 Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = [0x04] * 32 # 1.0 in E2M1
    b_elements = [0x04] * 32
    # Expected: 32 * 1.0 * 1.0 = 32. Fixed bit 8=1 -> 32*256 = 8192
    # Packed mode is required for short protocol to achieve the targeted 16-cycle stream phase
    await run_mac_test(dut, 4, 4, a_elements, b_elements, packed_mode=1)

@cocotb.test()
async def test_mxfp8_subnormals(dut):
    dut._log.info("Start MXFP8 Subnormals Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # E4M3: 0x01 is subnormal (2^-6 * 0.125)
    # 0x38 is 1.0
    # Expected product: 1.0 * (2^-6 * 0.125) = 2^-6 * 0.125
    # Sum of 32 such products: 32 * 2^-6 * 0.125 = 2^5 * 2^-6 * 2^-3 = 2^-4 = 0.0625

    # In our fixed-point model (bit 8 = 1.0):
    # 0.0625 * 256 = 16

    a_elements = [0x01] * 32
    b_elements = [0x38] * 32

    await run_mac_test(dut, 0, 0, a_elements, b_elements)
