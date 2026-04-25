# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
import yaml
import os

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

def align_model(prod, exp_sum, sign, round_mode=0, overflow_wrap=0, width=40):
    WIDTH = width
    # Normalized for WIDTH, mapping binary point to bit (WIDTH-24).
    # Formula: exp_sum + WIDTH - 37
    shift_amt = exp_sum + WIDTH - 37

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
        # Saturation threshold is -2^(WIDTH-1)
        if not overflow_wrap and (huge or (aligned >> (WIDTH-1)) != 0):
            res = -(1 << (WIDTH - 1))
        else:
            res = -aligned
    else:
        # Check saturation for positive
        # Saturation threshold is 2^(WIDTH-1)-1
        if not overflow_wrap and (huge or (aligned >> (WIDTH-1)) != 0):
            res = (1 << (WIDTH - 1)) - 1
        else:
            res = aligned

    return res

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
    # Parameters can be passed as -Pname=val or -Phierarchy.name=val
    compile_args = " " + os.environ.get("COMPILE_ARGS", "")
    import re
    # Match -Pname=val, -P hierarchy.name=val, etc.
    # regex looks for either whitespace or a dot before the name to avoid partial matches
    pattern = r"[\s\.]" + re.escape(name) + r"=(\d+)"
    match = re.search(pattern, compile_args)
    if match:
        return int(match.group(1))

    # 3. Fallback to hardcoded defaults in tb.v (which we just updated to Full)
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
    # Fallback for unsupported formats in hardware
    if not support_e4m3 and format_a == 0: return 0
    if not support_e4m3 and format_b == 0: return 0
    if not support_e5m2 and format_a == 1: return 0
    if not support_e5m2 and format_b == 1: return 0
    if not support_mxfp6 and format_a in [2, 3]: return 0
    if not support_mxfp6 and format_b in [2, 3]: return 0
    if not support_mxfp4 and format_a == 4: return 0
    if not support_mxfp4 and format_b == 4: return 0
    if not support_int8 and format_a in [5, 6]: return 0
    if not support_int8 and format_b in [5, 6]: return 0

    sa, ea, ma, ba, inta, nana, infa = decode_format(a_bits, format_a, is_bm_a, support_mxplus,
                                                    support_e4m3, support_e5m2, support_mxfp6, support_mxfp4)
    sb, eb, mb, bb, intb, nanb, infb = decode_format(b_bits, format_b, is_bm_b, support_mxplus,
                                                    support_e4m3, support_e5m2, support_mxfp6, support_mxfp4)

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
        # lns_mode: 0=Normal, 1=LNS, 2=Hybrid/Both
        if lns_mode == 0:
            prod = ma * mb
            exp_sum = ea + eb - (ba + bb - 7) - adj_a - adj_b
        elif lns_mode == 2 and support_mxplus and (is_bm_a or is_bm_b):
            # To maintain the precision benefits of MX+, BM elements use a standard multiplier
            prod = ma * mb
            exp_sum = ea + eb - (ba + bb - 7) - adj_a - adj_b
        elif inta or intb:
            return 0 # No INT8 support in LNS/Hybrid mode for non-BM
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

async def run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a=127, scale_b=127, round_mode=0, overflow_wrap=0, expected_override=None, packed_mode=0, bm_index_a=0, bm_index_b=0, nbm_offset_a=0, nbm_offset_b=0, mx_plus_mode=0, lns_mode=0):
    # Enforce parameter constraints in model
    support_mixed = get_param(dut, "SUPPORT_MIXED_PRECISION", 0)
    if not support_mixed:
        format_b = format_a

    support_mxplus_hw = get_param(dut, "SUPPORT_MX_PLUS", 0)
    support_mxplus = support_mxplus_hw and mx_plus_mode
    support_packing = get_param(dut, "SUPPORT_VECTOR_PACKING", 0)
    support_serial = get_param(dut, "SUPPORT_PACKED_SERIAL", 0)
    support_buffering = get_param(dut, "SUPPORT_INPUT_BUFFERING", 0)
    actual_packed = support_packing and packed_mode and (format_a == 4) and (format_b == 4)
    actual_buffering = support_buffering and not support_packing and packed_mode and (format_a == 4) and (format_b == 4)
    actual_serial = support_serial and not support_packing and not actual_buffering and packed_mode and (format_a == 4) and (format_b == 4)

    # Tiny-Serial timing parameters
    support_serial_hw = get_param(dut, "SUPPORT_SERIAL", 0)
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1) if support_serial_hw else 1
    cycles_per_element = k_factor

    support_adv = get_param(dut, "SUPPORT_ADV_ROUNDING", 0)
    if not support_adv:
        if round_mode in [1, 2]: # CEL, FLR
            round_mode = 0 # Fallback to TRN in model to match hardware fallback

    support_e4m3 = get_param(dut, "SUPPORT_E4M3", 1)
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp6 = get_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    support_int8 = get_param(dut, "SUPPORT_INT8", 0)
    use_lns = get_param(dut, "USE_LNS_MUL", 0)
    use_lns_precise = get_param(dut, "USE_LNS_MUL_PRECISE", 0)
    acc_width = get_param(dut, "ACCUMULATOR_WIDTH", 32)
    aligner_width = get_param(dut, "ALIGNER_WIDTH", 40)

    # Custom reset to handle Cycle 0 sampling
    dut.ena.value = 1
    # Cycle 0: Initial Metadata
    # ui_in[2:0]: NBM Offset A
    # ui_in[4:3]: LNS Mode
    # uio_in[2:0]: NBM Offset B
    # uio_in[4:3]: Rounding Mode
    # uio_in[5]: Overflow Mode
    # uio_in[6]: Packed Mode
    # uio_in[7]: MX+ Enable
    dut.ui_in.value = (nbm_offset_a & 0x7) | (lns_mode << 3)
    dut.uio_in.value = (nbm_offset_b & 0x7) | (round_mode << 3) | (overflow_wrap << 5) | (packed_mode << 6) | (mx_plus_mode << 7)

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1) # This edge samples metadata and moves to Cycle 1

    # Cycle 1: Load Scale A and BM Index A
    dut.ui_in.value = scale_a
    dut.uio_in.value = (format_a & 0x7) | ((bm_index_a & 0x1F) << 3)
    await ClockCycles(dut.clk, cycles_per_element)

    # Cycle 2: Load Scale B and BM Index B
    dut.ui_in.value = scale_b
    dut.uio_in.value = (format_b & 0x7) | ((bm_index_b & 0x1F) << 3)
    await ClockCycles(dut.clk, cycles_per_element)

    expected_acc = 0
    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    nan_sticky = support_shared and (scale_a == 0xFF or scale_b == 0xFF)
    inf_pos_sticky = False
    inf_neg_sticky = False

    # Process elements in groups of 32
    for i, (a, b) in enumerate(zip(a_elements, b_elements)):
        is_bm_a_cur = (i == bm_index_a)
        is_bm_b_cur = (i == bm_index_b)

        sa, ea, ma, ba, inta, nana, infa = decode_format(a, format_a, is_bm_a_cur, support_mxplus,
                                                        support_e4m3, support_e5m2, support_mxfp6, support_mxfp4)
        sb, eb, mb, bb, intb, nanb, infb = decode_format(b, format_b, is_bm_b_cur, support_mxplus,
                                                        support_e4m3, support_e5m2, support_mxfp6, support_mxfp4)

        # Basic NaN/Inf model for sticky registers
        is_zero_a = (not inta and ea == 0 and (ma & 0x7) == 0) or (inta and a == 0)
        is_zero_b = (not intb and eb == 0 and (mb & 0x7) == 0) or (intb and b == 0)

        nan_el = nana or nanb or (infa and is_zero_b) or (infb and is_zero_a)
        inf_el = (infa or infb) and not nan_el
        sign_el = sa ^ sb

        if nan_el: nan_sticky = True
        if inf_el:
            if sign_el: inf_neg_sticky = True
            else:      inf_pos_sticky = True

        prod = align_product_model(a, b, format_a, format_b, round_mode, overflow_wrap,
                                   support_e4m3, support_e5m2, support_mxfp6, support_mxfp4, support_int8, use_lns, use_lns_precise, aligner_width=aligner_width,
                                   is_bm_a=is_bm_a_cur, is_bm_b=is_bm_b_cur, support_mxplus=support_mxplus,
                                   offset_a=nbm_offset_a if mx_plus_mode else 0,
                                   offset_b=nbm_offset_b if mx_plus_mode else 0,
                                   lns_mode=lns_mode)

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
    elif actual_buffering:
        for i in range(16):
            dut.ui_in.value = (a_elements[2*i+1] << 4) | a_elements[2*i]
            dut.uio_in.value = (b_elements[2*i+1] << 4) | b_elements[2*i]
            await ClockCycles(dut.clk, cycles_per_element)
        # Next 16 cycles, values are ignored
        dut.ui_in.value = 0
        dut.uio_in.value = 0
        await ClockCycles(dut.clk, 16 * cycles_per_element)
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
    if nan_sticky or (inf_pos_sticky and inf_neg_sticky):
        expected_final = 0x7FC00000
    elif inf_pos_sticky:
        expected_final = 0x7F800000
    elif inf_neg_sticky:
        expected_final = 0xFF800000
    elif support_shared:
        shared_exp = scale_a + scale_b - 254
        acc_abs = abs(expected_acc)
        acc_sign = 1 if expected_acc < 0 else 0
        # Formula for shared scaling: shared_exp - (ALIGNER_WIDTH - 37)
        offset = -(aligner_width - 37)
        expected_final_full = align_model(acc_abs, shared_exp + offset, acc_sign, round_mode, overflow_wrap, width=aligner_width)
        # Extract the S23.8 window (top 32 bits of 40-bit result)
        expected_final = expected_final_full >> (aligner_width - 32)
    else:
        # If no shared scaling, extract the S23.8 window from the accumulator
        if acc_width >= 40:
            expected_final = expected_acc >> (acc_width - 32)
        else:
            expected_final = expected_acc

    # Return as 32-bit signed integer
    expected_final = expected_final & 0xFFFFFFFF
    if expected_final & 0x80000000:
        expected_final -= 0x100000000

    # Cycle 37-40 (or 21-24): Output Serialized Result
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        # uo_out bit-serial or parallel
        val = dut.uo_out.value
        try:
            val_int = int(val)
        except ValueError:
            # Handle 'x' or 'z' during simulation if necessary
            val_int = 0
        actual_acc = (actual_acc << 8) | val_int
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
    # Check if E5M2 is supported
    support_e5m2 = get_param(getattr(dut.user_project, "SUPPORT_E5M2", None), "SUPPORT_E5M2", 0)
    if not support_e5m2:
        dut._log.info("Skipping E5M2 Overflow Saturation Test (SUPPORT_E5M2=0)")
        return

    dut._log.info("Start Overflow Saturation Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = [0x78] * 32 # Large finite E5M2 (ea=30)
    b_elements = [0x78] * 32

    # Saturation
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=0)

@cocotb.test()
async def test_accumulator_saturation(dut):
    # Check if E5M2 is supported
    support_e5m2 = get_param(getattr(dut.user_project, "SUPPORT_E5M2", None), "SUPPORT_E5M2", 0)
    if not support_e5m2:
        dut._log.info("Skipping E5M2 Accumulator Saturation Test (SUPPORT_E5M2=0)")
        return

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

    a_elements = [0x02] * 32 # 1.0 in E2M1
    b_elements = [0x02] * 32
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

    a_elements = [0x02] * 32 # 1.0 in E2M1
    b_elements = [0x02] * 32
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

    support_e4m3 = get_param(dut, "SUPPORT_E4M3", 1)
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 1)
    support_mxfp6 = get_param(dut, "SUPPORT_MXFP6", 1)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    support_adv = get_param(dut, "SUPPORT_ADV_ROUNDING", 1)
    support_mixed = get_param(dut, "SUPPORT_MIXED_PRECISION", 1)

    dut._log.info(f"Start Randomized MXFP MAC Test (E4M3={support_e4m3}, E5M2={support_e5m2}, MXFP6={support_mxfp6}, MXFP4={support_mxfp4}, ADV={support_adv}, MIX={support_mixed})")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    allowed_formats = [5, 6]
    if support_e4m3: allowed_formats.append(0)
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
    dut._log.info("Start Fast Start (Scale Compression) Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    format_a = 0 # E4M3
    format_b = 0
    round_mode = 0
    overflow_wrap = 0
    packed_mode = 0
    mx_plus_mode = 0
    lns_mode = 0
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
    # Also need to provide metadata in uio_in
    # uio_in[2:0]: Format A, [4:3]: RM, [5]: Overflow, [6]: Packed, [7]: MX+ En
    dut.ui_in.value = 0x80
    dut.uio_in.value = (format_a & 0x7) | (round_mode << 3) | (overflow_wrap << 5) | (packed_mode << 6) | (mx_plus_mode << 7)
    support_serial_hw = get_param(dut, "SUPPORT_SERIAL", 0)
    k_factor_eff = k_factor if support_serial_hw else 1
    await ClockCycles(dut.clk, k_factor_eff)

    # Now at Cycle 3
    support_e4m3 = get_param(dut, "SUPPORT_E4M3", 1)
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp6 = get_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    use_lns = get_param(dut, "USE_LNS_MUL", 0)
    aligner_width = get_param(dut, "ALIGNER_WIDTH", 40)

    expected_acc = 0
    for a, b in zip(a_elements, b_elements):
        prod = align_product_model(a, b, format_a, format_b,
                                   support_e4m3=support_e4m3, support_e5m2=support_e5m2, support_mxfp6=support_mxfp6, support_mxfp4=support_mxfp4, support_int8=support_int8, use_lns=use_lns, use_lns_precise=use_lns_precise, aligner_width=aligner_width, lns_mode=lns_mode)

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
        offset = -(aligner_width - 37)
        expected_final_full = align_model(acc_abs, shared_exp + offset, acc_sign, width=aligner_width)
        expected_final = expected_final_full >> (aligner_width - 32)
    else:
        if acc_width >= 40:
            expected_final = expected_acc >> (acc_width - 32)
        else:
            expected_final = expected_acc

    expected_final = expected_final & 0xFFFFFFFF
    if expected_final & 0x80000000:
        expected_final -= 0x100000000

    for i in range(32):
        dut.ui_in.value = a_elements[i]
        dut.uio_in.value = b_elements[i]
        await ClockCycles(dut.clk, k_factor_eff)

    await ClockCycles(dut.clk, 2 * k_factor_eff) # Flush + Shared Scale

    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor_eff)

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
        lns_mode_case = inputs.get('lns_mode', 0)
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
                           mx_plus_mode=inputs.get('mx_plus_mode', 0),
                           lns_mode=lns_mode_case)

@cocotb.test()
async def test_yaml_cases(dut):
    await run_yaml_file(dut, "TEST_MX_E2E.yaml")

@cocotb.test()
async def test_mx_fp4_yaml(dut):
    await run_yaml_file(dut, "TEST_MX_FP4.yaml")

@cocotb.test()
async def test_min_max_zero_yaml(dut):
    await run_yaml_file(dut, "TEST_MIN_MAX_ZERO.yaml")

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
async def test_mxfp4_input_buffering(dut):
    # Check if input buffering is supported
    support_buffering = get_param(getattr(dut.user_project, "SUPPORT_INPUT_BUFFERING", None), "SUPPORT_INPUT_BUFFERING", 0)
    support_packing = get_param(getattr(dut.user_project, "SUPPORT_VECTOR_PACKING", None), "SUPPORT_VECTOR_PACKING", 0)

    if not support_buffering or support_packing:
        reason = "SUPPORT_INPUT_BUFFERING=0" if not support_buffering else "SUPPORT_VECTOR_PACKING=1 (takes precedence)"
        dut._log.info(f"Skipping Input Buffering FP4 Test ({reason})")
        return

    dut._log.info("Start Input Buffering FP4 Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = [0x02] * 32 # 1.0 in E2M1
    b_elements = [0x02] * 32
    # Expected: 32 * 1.0 * 1.0 = 32. Fixed bit 8=1 -> 32*256 = 8192

    # Manual protocol to test burst loading
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1)

    # 1. Reset
    await reset_dut(dut)

    # 2. Cycle 0: Load Config (packed_mode=1)
    # We need to redo this because the previous reset_dut used 0
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = (1 << 6) # packed_mode=1
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

    # 3. Cycle 1: Load Scale A
    dut.ui_in.value = 127 # scale_a
    dut.uio_in.value = 4 # format_a=4 (E2M1)
    await ClockCycles(dut.clk, k_factor)

    # 4. Cycle 2: Load Scale B
    dut.ui_in.value = 127
    dut.uio_in.value = 4 # format_b
    await ClockCycles(dut.clk, k_factor)

    # 4. Burst Load (16 cycles)
    for i in range(16):
        dut.ui_in.value = (a_elements[2*i+1] << 4) | a_elements[2*i]
        dut.uio_in.value = (b_elements[2*i+1] << 4) | b_elements[2*i]
        await ClockCycles(dut.clk, k_factor)

    # 5. Idle/Wait (next 16 cycles of streaming phase)
    # The unit should continue processing from internal buffer
    dut.ui_in.value = 0xAA # Dummy values to prove they are ignored
    dut.uio_in.value = 0x55
    await ClockCycles(dut.clk, 16 * k_factor)

    # 6. Pipeline flush + Result collection
    await ClockCycles(dut.clk, 2 * k_factor)

    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor)

    if actual_acc & 0x80000000: actual_acc -= 0x100000000
    assert actual_acc == 8192

@cocotb.test()
async def test_mxfp8_sticky_flags(dut):
    dut._log.info("Start MXFP8 Sticky Flags (NaN/Inf) Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)

    # 1. Shared Scale NaN Rule (Scale=0xFF)
    if support_shared:
        dut._log.info("Testing Shared Scale NaN Rule (0xFF)")
        a_elements = [0x38] * 32
        b_elements = [0x38] * 32
        await run_mac_test(dut, 0, 0, a_elements, b_elements, scale_a=0xFF)

    # 2. Element-level NaN (E4M3: 0x7F)
    support_e4m3 = get_param(dut, "SUPPORT_E4M3", 1)
    if support_e4m3:
        dut._log.info("Testing Element-level NaN (E4M3)")
        a_elements = [0x38] * 32
        a_elements[5] = 0x7F # NaN
        b_elements = [0x38] * 32
        await run_mac_test(dut, 0, 0, a_elements, b_elements)

    # 3. Element-level Inf and NaN (E5M2)
    if support_e5m2:
        dut._log.info("Testing E5M2 Infinity and NaN")
        # Positive Inf
        a_elements = [0x3C] * 32
        a_elements[10] = 0x7C # +Inf
        b_elements = [0x3C] * 32
        await run_mac_test(dut, 1, 1, a_elements, b_elements)

        # Negative Inf
        a_elements[10] = 0xFC # -Inf
        await run_mac_test(dut, 1, 1, a_elements, b_elements)

        # Inf * Zero = NaN
        a_elements[10] = 0x7C # +Inf
        b_elements[10] = 0x00 # Zero
        await run_mac_test(dut, 1, 1, a_elements, b_elements)

@cocotb.test()
async def test_lns_modes(dut):
    dut._log.info("Start LNS Modes Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    use_lns = get_param(dut, "USE_LNS_MUL", 0)
    if not use_lns:
        dut._log.info("Skipping LNS Modes Test (USE_LNS_MUL=0)")
        return

    a_elements = [0x39] * 32 # 1.125 in E4M3
    b_elements = [0x3A] * 32 # 1.25 in E4M3
    # Exact product: 1.125 * 1.25 = 1.40625. Sum of 32 = 45.0. Fixed bit 8=1 -> 45*256 = 11520.
    # LNS (Mitchell): log2(1.125) approx 0.125, log2(1.25) approx 0.25. Sum = 0.375.
    # 2^0.375 approx 1 + 0.375 = 1.375. Sum of 32 = 44.0. Fixed -> 44*256 = 11264.

    # 1. Normal Mode (lns_mode=0)
    await run_mac_test(dut, 0, 0, a_elements, b_elements, lns_mode=0)

    # 2. LNS Mode (lns_mode=1)
    await run_mac_test(dut, 0, 0, a_elements, b_elements, lns_mode=1)

    # 3. Hybrid Mode (lns_mode=2) with MX+
    # Elements are NOT BM, so they use LNS
    await run_mac_test(dut, 0, 0, a_elements, b_elements, lns_mode=2, mx_plus_mode=1, bm_index_a=31, bm_index_b=31)

    # BM element at index 0. It should use exact multiplier.
    # We test this by making it high precision and seeing if it matches exact.
    # But it's hard to isolate one element in a sum of 32.
    # Let's use 1 BM element and 31 zeros.
    a_elements_bm = [0x00] * 32
    b_elements_bm = [0x00] * 32
    a_elements_bm[0] = 0x39
    b_elements_bm[0] = 0x3A
    # Expected: 1.125 * 1.25 = 1.40625. Fixed -> 1.40625 * 256 = 360.
    await run_mac_test(dut, 0, 0, a_elements_bm, b_elements_bm, lns_mode=2, mx_plus_mode=1, bm_index_a=0, bm_index_b=0)

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

@cocotb.test()
async def test_mxfp8_subnormal_precision(dut):
    """
    Test that small subnormal products (e.g., 2^-9) are preserved by the
    16-bit fractional datapath and correctly accumulated.
    With 8-bit fractional precision, 2^-9 would be truncated to 0.
    """
    dut._log.info("Start MXFP8 Subnormal Precision Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # E4M3: 0x01 is subnormal (2^-6 * 0.125 = 2^-9)
    # 0x38 is 1.0
    # Product: 1.0 * 2^-9 = 2^-9
    # Sum of 32: 32 * 2^-9 = 2^-4 = 0.0625
    # Result in S23.8: 0.0625 * 256 = 16

    a_elements = [0x01] * 32
    b_elements = [0x38] * 32

    # We expect 16. If precision was 8-bit, we'd get 0.
    await run_mac_test(dut, 0, 0, a_elements, b_elements)

@cocotb.test()
async def test_lane_overflow(dut):
    """
    Specifically test that dual-lane addition in Packed Mode saturates
    before hitting the accumulator, preventing intermediate 32-bit wrap-around.
    """
    support_packing = get_param(dut, "SUPPORT_VECTOR_PACKING", 0)
    if not support_packing:
        dut._log.info("Skipping Lane Overflow Test (SUPPORT_VECTOR_PACKING=0)")
        return

    dut._log.info("Start Lane Overflow Test (Packed Mode)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # We want each lane to produce a value that, when combined, overflows 32-bit signed.
    # Lane 0 product -> Aligned -> 0x60000000
    # Lane 1 product -> Aligned -> 0x60000000
    # Combined sum = 0xC0000000 (Negative if not saturated)

    # E2M1: 0x02 is 1.0. 1.0 * 1.0 = 1.0.
    # To get 0x60000000: magnitude must be 0x60000000 / 256 = 0x600000 = 6,291,456.
    # 2^22 approx 4 million. 2^23 approx 8 million.
    # exp_sum - 5 = 22 -> exp_sum = 27.
    # Standard exp_sum for E2M1 is 9.
    # We use shared scaling to add 18. scale_a + scale_b - 254 = 18.
    # scale_a = 145, scale_b = 127 -> 145 + 127 - 254 = 18.

    a_elements = [0x02] * 32 # 1.0
    b_elements = [0x02] * 32 # 1.0

    # We only need one cycle of overflow to test it.
    # The model handles this correctly as it saturates at each element addition.
    await run_mac_test(dut, 4, 4, a_elements, b_elements, scale_a=157, scale_b=127, packed_mode=1)

@cocotb.test()
async def test_mxfp4_full_range(dut):
    # Check if vector packing is supported
    support_packing = get_param(getattr(dut.user_project, "SUPPORT_VECTOR_PACKING", None), "SUPPORT_VECTOR_PACKING", 0)
    if not support_packing:
        dut._log.info("Skipping Full Range Packed FP4 Test (SUPPORT_VECTOR_PACKING=0)")
        return

    dut._log.info("Start Full Range Packed FP4 Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = list(range(16)) * 2
    b_elements = list(range(16)) * 2
    # Expected: 2 * sum(v*v for v in range(16)) = 2 * 137.0 = 274.0.
    # Fixed point (8 bits): 274.0 * 256 = 70144
    await run_mac_test(dut, 4, 4, a_elements, b_elements, packed_mode=1)
