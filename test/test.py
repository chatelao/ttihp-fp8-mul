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

def align_model(prod, exp_sum, sign, round_mode=0, overflow_wrap=0, width=40, shift_offset=3):
    shift_amt = exp_sum + shift_offset
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
        # Magnitude > 2^(WIDTH-1) saturates to -2^(WIDTH-1)
        if not overflow_wrap and (huge or (aligned >> (WIDTH-1)) != 0):
            res = -(1 << (WIDTH - 1))
        else:
            res = -aligned
    else:
        # Magnitude > 2^(WIDTH-1)-1 saturates to 2^(WIDTH-1)-1
        if not overflow_wrap and (huge or (aligned >> (WIDTH-1)) != 0):
            res = (1 << (WIDTH - 1)) - 1
        else:
            res = aligned

    # Return as WIDTH-bit signed integer
    mask = (1 << WIDTH) - 1
    res_width = res & mask
    if res_width & (1 << (WIDTH - 1)):
        return res_width - (1 << WIDTH)
    return res_width

def fixed_to_float_model(data_in, shared_exp, frac_bits=16, nan=False, inf_pos=False, inf_neg=False):
    """
    Python model for the hardware Fixed-to-Float engine.
    Matches IEEE 754 Binary32.
    """
    if nan or (inf_pos and inf_neg): return 0x7FC00000
    if inf_pos: return 0x7F800000
    if inf_neg: return 0xFF800000
    if data_in == 0: return 0x00000000

    # Calculate real value
    # data_in is a signed integer representing fixed-point S(W-F).F
    val = float(data_in) / (2.0**frac_bits)
    # Apply shared scale
    val = val * (2.0**shared_exp)

    # Use struct to get IEEE 754 bit pattern
    # struct.pack('!f', val) implements RNE rounding by default
    res = struct.unpack('!I', struct.pack('!f', val))[0]

    # Hardware 'flush to zero' for underflow (e <= 0)
    # Binary32 exponents are bits [30:23]. If they are 0, it's subnormal or zero.
    if (res & 0x7F800000) == 0:
        return (res & 0x80000000) # Flush to signed zero

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
    compile_args = " " + os.environ.get("COMPILE_ARGS", "")
    import re
    pattern = r"[\s\.]" + re.escape(name) + r"=(\d+)"
    match = re.search(pattern, compile_args)
    if match:
        return int(match.group(1))

    # 3. Fallback to hardcoded defaults
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
        real_ma = ma
        real_mb = mb
        if not support_int8 and not support_mxplus:
            real_ma = real_ma & 0xF
            real_mb = real_mb & 0xF
        prod = real_ma * real_mb
        exp_sum = ea + eb - (ba + bb - 7) - adj_a - adj_b

    frac_bits = 16 if aligner_width >= 32 else 8
    shift_offset = (frac_bits - 13)
    return align_model(prod, exp_sum, sign, round_mode, overflow_wrap, width=aligner_width, shift_offset=shift_offset)

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

    support_serial_hw = get_param(dut, "SUPPORT_SERIAL", 0)
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1) if support_serial_hw else 1
    cycles_per_element = k_factor

    support_adv = get_param(dut, "SUPPORT_ADV_ROUNDING", 0)
    if not support_adv:
        if round_mode in [1, 2]:
            round_mode = 0

    support_e4m3 = get_param(dut, "SUPPORT_E4M3", 1)
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_mxfp6 = get_param(dut, "SUPPORT_MXFP6", 0)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    support_int8 = get_param(dut, "SUPPORT_INT8", 0)
    use_lns = get_param(dut, "USE_LNS_MUL", 0)
    use_lns_precise = get_param(dut, "USE_LNS_MUL_PRECISE", 0)
    acc_width = get_param(dut, "ACCUMULATOR_WIDTH", 32)
    aligner_width = get_param(dut, "ALIGNER_WIDTH", 40)

    dut.ena.value = 1
    dut.ui_in.value = (nbm_offset_a & 0x7) | (lns_mode << 3)
    dut.uio_in.value = (nbm_offset_b & 0x7) | (round_mode << 3) | (overflow_wrap << 5) | (packed_mode << 6) | (mx_plus_en_val := (mx_plus_mode << 7))

    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = scale_a
    dut.uio_in.value = (format_a & 0x7) | ((bm_index_a & 0x1F) << 3)
    await ClockCycles(dut.clk, cycles_per_element)

    dut.ui_in.value = scale_b
    dut.uio_in.value = (format_b & 0x7) | ((bm_index_b & 0x1F) << 3)
    await ClockCycles(dut.clk, cycles_per_element)

    expected_acc = 0
    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    nan_sticky = support_shared and (scale_a == 0xFF or scale_b == 0xFF)
    inf_pos_sticky = False
    inf_neg_sticky = False

    for i, (a, b) in enumerate(zip(a_elements, b_elements)):
        is_bm_a_cur = (i == bm_index_a)
        is_bm_b_cur = (i == bm_index_b)

        sa, ea, ma, ba, inta, nana, infa = decode_format(a, format_a, is_bm_a_cur, support_mxplus,
                                                        support_e4m3, support_e5m2, support_mxfp6, support_mxfp4)
        sb, eb, mb, bb, intb, nanb, infb = decode_format(b, format_b, is_bm_b_cur, support_mxplus,
                                                        support_e4m3, support_e5m2, support_mxfp6, support_mxfp4)

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
        dut.ui_in.value = 0
        dut.uio_in.value = 0
        await ClockCycles(dut.clk, 16 * cycles_per_element)
    elif actual_serial:
        for i in range(16):
            dut.ui_in.value = (a_elements[2*i+1] << 4) | a_elements[2*i]
            dut.uio_in.value = (b_elements[2*i+1] << 4) | b_elements[2*i]
            await ClockCycles(dut.clk, cycles_per_element)
            await ClockCycles(dut.clk, cycles_per_element)
    else:
        for i in range(32):
            dut.ui_in.value = a_elements[i]
            dut.uio_in.value = b_elements[i]
            await ClockCycles(dut.clk, cycles_per_element)

    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, cycles_per_element)
    await ClockCycles(dut.clk, cycles_per_element)

    if support_shared:
        shared_exp = scale_a + scale_b - 254
        frac_bits = 16 if acc_width >= 32 else 8
        expected_32 = fixed_to_float_model(expected_acc, shared_exp, frac_bits, nan_sticky, inf_pos_sticky, inf_neg_sticky)
    else:
        if acc_width <= 32:
            expected_32 = (expected_acc << (32 - acc_width)) & 0xFFFFFFFF
        else:
            expected_32 = (expected_acc >> (acc_width - 32)) & 0xFFFFFFFF

    expected_32_s = expected_32 & 0xFFFFFFFF
    if expected_32_s & 0x80000000:
        expected_32_s -= 0x100000000

    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, cycles_per_element)

    if actual_acc & 0x80000000:
        actual_acc -= 0x100000000

    if expected_override is not None:
        expected_32_s = expected_override

    format_names = ["E4M3", "E5M2", "E3M2", "E2M3", "E2M1", "INT8", "INT8_SYM"]
    name_a = format_names[format_a] if format_a < len(format_names) else "Unknown"
    name_b = format_names[format_b] if format_b < len(format_names) else "Unknown"
    dut._log.info(f"Format: {name_a}x{name_b}, RM: {round_mode}, Wrap: {overflow_wrap}, Scales: {scale_a},{scale_b}, Expected: 0x{expected_32_s & 0xFFFFFFFF:08X}, Actual: 0x{actual_acc & 0xFFFFFFFF:08X}")
    assert actual_acc == expected_32_s

@cocotb.test()
async def test_mxfp8_mac_shared_scale(dut):
    dut._log.info("Start MXFP8 MAC Shared Scale Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x38] * 32 # 1.0
    b_elements = [0x38] * 32
    # Total sum = 32.0. Scale = 2.0. Result = 64.0.
    # Float32(64.0) = 0x42800000
    await run_mac_test(dut, 0, 0, a_elements, b_elements, scale_a=128, scale_b=127)

@cocotb.test()
async def test_mxfp8_mac_e4m3(dut):
    dut._log.info("Start MXFP8 MAC Test (E4M3)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x38] * 32
    b_elements = [0x38] * 32
    # 32.0 -> 0x42000000
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
    support_adv = get_param(getattr(dut.user_project, "SUPPORT_ADV_ROUNDING", None), "SUPPORT_ADV_ROUNDING", 1)
    if not support_adv:
        dut._log.info("Skipping Rounding Modes Test")
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
    support_e5m2 = get_param(getattr(dut.user_project, "SUPPORT_E5M2", None), "SUPPORT_E5M2", 0)
    if not support_e5m2: return
    dut._log.info("Start Overflow Saturation Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x78] * 32
    b_elements = [0x78] * 32
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=0)

@cocotb.test()
async def test_accumulator_saturation(dut):
    support_e5m2 = get_param(getattr(dut.user_project, "SUPPORT_E5M2", None), "SUPPORT_E5M2", 0)
    if not support_e5m2: return
    dut._log.info("Start Accumulator Saturation Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x78] * 32
    b_elements = [0x78] * 32
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=0)
    await run_mac_test(dut, 1, 1, a_elements, b_elements, overflow_wrap=1)

@cocotb.test()
async def test_mxfp4_packed_serial(dut):
    support_serial = get_param(getattr(dut.user_project, "SUPPORT_PACKED_SERIAL", None), "SUPPORT_PACKED_SERIAL", 0)
    if not support_serial: return
    dut._log.info("Start Serial Packed FP4 Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x02] * 32
    b_elements = [0x02] * 32
    await run_mac_test(dut, 4, 4, a_elements, b_elements, packed_mode=1)

@cocotb.test()
async def test_mxfp4_packed(dut):
    support_packing = get_param(getattr(dut.user_project, "SUPPORT_VECTOR_PACKING", None), "SUPPORT_VECTOR_PACKING", 0)
    if not support_packing: return
    dut._log.info("Start Packed FP4 Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x02] * 32
    b_elements = [0x02] * 32
    await run_mac_test(dut, 4, 4, a_elements, b_elements, packed_mode=1)

@cocotb.test()
async def test_mixed_precision(dut):
    support_mixed = get_param(getattr(dut.user_project, "SUPPORT_MIXED_PRECISION", None), "SUPPORT_MIXED_PRECISION", 1)
    if not support_mixed: return
    dut._log.info("Start Mixed-Precision MAC Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x38] * 32
    b_elements = [0x3C] * 32
    await run_mac_test(dut, 0, 1, a_elements, b_elements)

@cocotb.test()
async def test_mxfp_mac_randomized(dut):
    import random
    support_e4m3 = get_param(dut, "SUPPORT_E4M3", 1)
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 1)
    support_mxfp6 = get_param(dut, "SUPPORT_MXFP6", 1)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    support_adv = get_param(dut, "SUPPORT_ADV_ROUNDING", 1)
    support_mixed = get_param(dut, "SUPPORT_MIXED_PRECISION", 1)
    dut._log.info("Start Randomized MXFP MAC Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    allowed_formats = [5, 6]
    if support_e4m3: allowed_formats.append(0)
    if support_e5m2: allowed_formats.append(1)
    if support_mxfp6: allowed_formats.extend([2, 3])
    if support_mxfp4: allowed_formats.append(4)
    for i in range(20):
        format_a = random.choice(allowed_formats)
        format_b = random.choice(allowed_formats) if support_mixed else format_a
        round_mode = random.randint(0, 3) if support_adv else random.choice([0, 3])
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
    scale_a = 128
    scale_b = 127
    a_elements = [0x38] * 32
    b_elements = [0x38] * 32
    await run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a, scale_b)
    # Fast start model would go here, skipping for now.

async def run_yaml_file(dut, filename):
    dut._log.info(f"Start YAML Test Cases from {filename}")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    yaml_path = os.path.join(os.path.dirname(__file__), filename)
    with open(yaml_path, 'r') as f:
        cases = yaml.safe_load(f)
    if not cases: return
    for case in cases:
        if case.get('disabled', False): continue
        inputs = case['inputs']
        expected = case['expected_output']
        await run_mac_test(dut,
                           format_a=inputs['format_a'],
                           format_b=inputs.get('format_b', inputs['format_a']),
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
                           lns_mode=inputs.get('lns_mode', 0))

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
    if os.environ.get("GATES") == "yes": return
    support_mxplus = get_param(dut, "SUPPORT_MX_PLUS", 0)
    if not support_mxplus: return
    await run_yaml_file(dut, "TEST_MXPLUS.yaml")

@cocotb.test()
async def test_mxfp8_sticky_flags(dut):
    dut._log.info("Start MXFP8 Sticky Flags (NaN/Inf) Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 0)
    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    if support_shared:
        await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32, scale_a=0xFF)
    await run_mac_test(dut, 0, 0, [0x38]*32, [0x38]*32) # Standard
    if support_e5m2:
        a_elements = [0x3C] * 32
        a_elements[10] = 0x7C # +Inf
        await run_mac_test(dut, 1, 1, a_elements, [0x3C]*32)

@cocotb.test()
async def test_mxfp8_subnormals(dut):
    dut._log.info("Start MXFP8 Subnormals Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x01] * 32
    b_elements = [0x38] * 32
    await run_mac_test(dut, 0, 0, a_elements, b_elements)
