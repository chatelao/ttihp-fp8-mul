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
    elif format_val == 2: # INT8
        sign = (bits >> 7) & 1
        val = bits if bits < 128 else bits - 256
        mant = abs(val)
        exp = 0
        bias = 3
        is_int = True
    elif format_val == 3: # INT8_SYM
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

def align_model(prod, exp_sum, sign, round_mode=0, overflow_wrap=0):
    shift_amt = exp_sum - 5

    if shift_amt >= 0:
        if not overflow_wrap and shift_amt > 60:
            aligned = 0xFFFFFFFFFFFFFFFF
        else:
            aligned = prod << shift_amt
        sticky = 0
        shifted_out = 0
        base = aligned
    else:
        n = -shift_amt
        if n >= 64:
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
        # Magnitude > 2^31 saturates to -2^31
        if not overflow_wrap and (aligned > 0x80000000):
            res = -0x80000000
        else:
            res = -aligned
    else:
        # Magnitude > 2^31-1 saturates to 2^31-1
        if not overflow_wrap and aligned > 0x7FFFFFFF:
            res = 0x7FFFFFFF
        else:
            res = aligned

    # Return as 32-bit signed integer
    res_32 = res & 0xFFFFFFFF
    if res_32 & 0x80000000:
        return res_32 - 0x100000000
    return res_32

def align_product_model(a_bits, b_bits, format_a, format_b, round_mode=0, overflow_wrap=0):
    sa, ea, ma, ba, inta = decode_format(a_bits, format_a)
    sb, eb, mb, bb, intb = decode_format(b_bits, format_b)

    sign = sa ^ sb

    if (not inta and ea == 0) or (not intb and eb == 0):
        return 0
    if (inta and a_bits == 0) or (intb and b_bits == 0):
        return 0

    real_ma = (8 + ma) if not inta else ma
    real_mb = (8 + mb) if not intb else mb

    prod = real_ma * real_mb
    exp_sum = ea + eb - (ba + bb - 7)

    return align_model(prod, exp_sum, sign, round_mode, overflow_wrap)

async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

async def run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a=127, scale_b=127, round_mode=0, overflow_wrap=0):
    await reset_dut(dut)

    # Cycle 1: Load Scale A and Format/Numerical Control
    dut.ui_in.value = scale_a
    dut.uio_in.value = format_a | (round_mode << 3) | (overflow_wrap << 5)
    await ClockCycles(dut.clk, 1)

    # Cycle 2: Load Scale B and Format B
    dut.ui_in.value = format_b
    dut.uio_in.value = scale_b
    await ClockCycles(dut.clk, 1)

    expected_acc = 0
    # Process elements in groups of 32
    for a, b in zip(a_elements, b_elements):
        prod = align_product_model(a, b, format_a, format_b, round_mode, overflow_wrap)

        acc_32 = expected_acc & 0xFFFFFFFF
        prod_32 = prod & 0xFFFFFFFF
        sum_32 = (acc_32 + prod_32) & 0xFFFFFFFF

        # Signed overflow check
        s_acc = (acc_32 >> 31) & 1
        s_prod = (prod_32 >> 31) & 1
        s_res = (sum_32 >> 31) & 1

        if not overflow_wrap and (s_acc == s_prod) and (s_acc != s_res):
            expected_acc_raw = 0x80000000 if s_acc == 1 else 0x7FFFFFFF
        else:
            expected_acc_raw = sum_32

        if expected_acc_raw & 0x80000000:
            expected_acc = expected_acc_raw - 0x100000000
        else:
            expected_acc = expected_acc_raw

    for i in range(32):
        dut.ui_in.value = a_elements[i]
        dut.uio_in.value = b_elements[i]
        await ClockCycles(dut.clk, 1)

    # Now at Cycle 35.
    # Elements: in at 3-34, reaches Acc at 5-36. Final Addition end of 36 (edge 37).
    # Shared Scale: acc_abs captures at end of 37 (edge 38).
    # Aligner works Cycle 38, results in aligned_res_reg at end of 38 (edge 39).
    # scaled_acc_reg captures at end of 39 (edge 40).
    # Serialization starts at Cycle 40.
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 5)

    # Now at Cycle 40. read uo_out.
    # Calculate expected final result after shared scaling
    shared_exp = scale_a + scale_b - 254
    acc_abs = abs(expected_acc)
    acc_sign = 1 if expected_acc < 0 else 0

    expected_final = align_model(acc_abs, shared_exp + 5, acc_sign, round_mode, overflow_wrap)

    # Cycle 40-43: Output Serialized Result
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, 1)

    if actual_acc & 0x80000000:
        actual_acc -= 0x100000000

    format_names = ["E4M3", "E5M2", "INT8", "INT8_SYM"]
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
async def test_mixed_precision(dut):
    dut._log.info("Start Mixed-Precision MAC Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # E4M3 x E5M2
    a_elements = [0x38] * 32 # 1.0 in E4M3
    b_elements = [0x3C] * 32 # 1.0 in E5M2
    await run_mac_test(dut, 0, 1, a_elements, b_elements)

    # E5M2 x INT8
    a_elements = [0x3C] * 32 # 1.0 in E5M2
    b_elements = [0x40] * 32 # 64 in INT8 (which is 1.0 with 2^-6 scale)
    await run_mac_test(dut, 1, 2, a_elements, b_elements)

@cocotb.test()
async def test_mxfp_mac_randomized(dut):
    import random
    dut._log.info("Start Randomized MXFP MAC Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    for i in range(50):
        format_a = random.randint(0, 3)
        format_b = random.randint(0, 3)
        round_mode = random.randint(0, 3)
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
    scale_a = 128
    scale_b = 127
    a_elements = [0x38] * 32 # 1.0
    b_elements = [0x38] * 32

    # 1. Normal Start
    await run_mac_test(dut, format_a, format_b, a_elements, b_elements, scale_a, scale_b)

    # 2. Fast Start (Reuse scales)
    # Manual protocol for fast start:
    dut.ui_in.value = 0x80
    await ClockCycles(dut.clk, 1)

    # Now at Cycle 3
    expected_acc = 0
    for a, b in zip(a_elements, b_elements):
        prod = align_product_model(a, b, format_a, format_b)
        expected_acc += prod

    shared_exp = scale_a + scale_b - 254
    acc_abs = abs(expected_acc)
    acc_sign = 1 if expected_acc < 0 else 0
    expected_final = align_model(acc_abs, shared_exp + 5, acc_sign)

    for i in range(32):
        dut.ui_in.value = a_elements[i]
        dut.uio_in.value = b_elements[i]
        await ClockCycles(dut.clk, 1)

    await ClockCycles(dut.clk, 5) # wait for Cycles 35-39

    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, 1)

    if actual_acc & 0x80000000: actual_acc -= 0x100000000
    assert actual_acc == expected_final
