# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

def align_product_model(a_bits, b_bits, format_val, round_mode=0, overflow_wrap=0):
    if format_val == 0: # E4M3
        ea = (a_bits >> 3) & 0xF
        ma = (a_bits & 0x7)
        eb = (b_bits >> 3) & 0xF
        mb = (b_bits & 0x7)
        bias = 7
        sign_a = (a_bits >> 7) & 1
        sign_b = (b_bits >> 7) & 1
        is_int = False
    elif format_val == 1: # E5M2
        ea = (a_bits >> 2) & 0x1F
        ma = (a_bits & 0x3) << 1
        eb = (b_bits >> 2) & 0x1F
        mb = (b_bits & 0x3) << 1
        bias = 15
        sign_a = (a_bits >> 7) & 1
        sign_b = (b_bits >> 7) & 1
        is_int = False
    elif format_val == 2: # E3M2
        ea = (a_bits >> 2) & 0x7
        ma = (a_bits & 0x3) << 1
        eb = (b_bits >> 2) & 0x7
        mb = (b_bits & 0x3) << 1
        bias = 3
        sign_a = (a_bits >> 5) & 1
        sign_b = (b_bits >> 5) & 1
        is_int = False
    elif format_val == 3: # E2M3
        ea = (a_bits >> 3) & 0x3
        ma = (a_bits & 0x7)
        eb = (b_bits >> 3) & 0x3
        mb = (b_bits & 0x7)
        bias = 1
        sign_a = (a_bits >> 5) & 1
        sign_b = (b_bits >> 5) & 1
        is_int = False
    elif format_val == 4: # E2M1
        ea = (a_bits >> 1) & 0x3
        ma = (a_bits & 0x1) << 2
        eb = (b_bits >> 1) & 0x3
        mb = (b_bits & 0x1) << 2
        bias = 1
        sign_a = (a_bits >> 3) & 1
        sign_b = (b_bits >> 3) & 1
        is_int = False
    elif format_val == 5: # INT8
        ia = a_bits
        if ia >= 128: ia -= 256
        ib = b_bits
        if ib >= 128: ib -= 256
        is_int = True
    elif format_val == 6: # INT8_SYM
        ia = a_bits
        if ia >= 128: ia -= 256
        if ia == -128: ia = -127
        ib = b_bits
        if ib >= 128: ib -= 256
        if ib == -128: ib = -127
        is_int = True
    else: # Default to E4M3
        return align_product_model(a_bits, b_bits, 0, round_mode, overflow_wrap)

    if is_int:
        prod_val = ia * ib
        sign = 1 if prod_val < 0 else 0
        prod = abs(prod_val)
        exp_sum = 1
    else:
        sign = sign_a ^ sign_b
        if ea == 0 or eb == 0:
            return 0
        prod = (8 + ma) * (8 + mb)
        exp_sum = ea + eb - 2*bias + 7

    shift_amt = exp_sum - 5

    if shift_amt >= 0:
        aligned = prod << shift_amt
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
            aligned = base + 1 if (not sign and sticky) else base
        elif round_mode == 2: # FLR
            aligned = base + 1 if (sign and sticky) else base
        elif round_mode == 3: # RNE
            if n >= 64:
                aligned = 0
            else:
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
        if not overflow_wrap and aligned > 0x80000000:
            aligned = 0x80000000
        else:
            aligned = -aligned
    else:
        if not overflow_wrap and aligned > 0x7FFFFFFF:
            aligned = 0x7FFFFFFF
        else:
            aligned = aligned

    # Mask to 32 bits and handle sign
    aligned = aligned & 0xFFFFFFFF
    if aligned & 0x80000000:
        if aligned == 0x80000000:
            return -0x80000000
        aligned -= 0x100000000

    return aligned

async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

async def run_mac_test(dut, format_val, a_elements, b_elements, round_mode=0, overflow_wrap=0):
    await reset_dut(dut)

    # Cycle 1: Load Scale A and Format/Numerical Control
    dut.ui_in.value = 0x00 # Scale A
    dut.uio_in.value = format_val | (round_mode << 3) | (overflow_wrap << 5)
    await ClockCycles(dut.clk, 1)

    # Cycle 2: Load Scale B
    dut.ui_in.value = 0x00
    dut.uio_in.value = 0x00 # Scale B
    await ClockCycles(dut.clk, 1)

    expected_acc = 0
    for a, b in zip(a_elements, b_elements):
        prod = align_product_model(a, b, format_val, round_mode, overflow_wrap)

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

    # Cycle 35: Extra cycle for pipeline latency
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 1)

    # Cycle 36-39: Output Serialized Result
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, 1)

    if actual_acc & 0x80000000:
        actual_acc -= 0x100000000

    format_names = ["E4M3", "E5M2", "E3M2", "E2M3", "E2M1", "INT8", "INT8_SYM"]
    name = format_names[format_val] if format_val < len(format_names) else "Unknown"
    dut._log.info(f"Format: {name}, RM: {round_mode}, Wrap: {overflow_wrap}, Expected: {expected_acc}, Actual: {actual_acc}")
    assert actual_acc == expected_acc

@cocotb.test()
async def test_mxfp8_mac_e4m3(dut):
    dut._log.info("Start MXFP8 MAC Test (E4M3)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x38] * 32 # 1.0 in E4M3
    b_elements = [0x38] * 32
    await run_mac_test(dut, 0, a_elements, b_elements)

@cocotb.test()
async def test_mxfp8_mac_e5m2(dut):
    dut._log.info("Start MXFP8 MAC Test (E5M2)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x3C] * 32 # 1.0 in E5M2
    b_elements = [0x3C] * 32
    await run_mac_test(dut, 1, a_elements, b_elements)

@cocotb.test()
async def test_rounding_modes(dut):
    dut._log.info("Start Rounding Modes Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = [0x29] * 32
    b_elements = [0x31] * 32

    # TRN: 40 * 32 = 1280
    await run_mac_test(dut, 0, a_elements, b_elements, round_mode=0)
    # CEL: (40+1) * 32 = 1312
    await run_mac_test(dut, 0, a_elements, b_elements, round_mode=1)
    # FLR: 40 * 32 = 1280 (positive)
    await run_mac_test(dut, 0, a_elements, b_elements, round_mode=2)
    # RNE: 81 >> 1 = 40.5. Ties to even. 40 is even. So 40.
    await run_mac_test(dut, 0, a_elements, b_elements, round_mode=3)

    # Negative test
    a_elements = [0xA9] * 32 # -0.28125
    b_elements = [0x31] * 32 # 0.5625
    # a*b = -0.158203125. Fixed point magnitude = 40.5.
    # TRN: -40 * 32 = -1280
    await run_mac_test(dut, 0, a_elements, b_elements, round_mode=0)
    # CEL: -40 * 32 = -1280 (negative, ceil towards 0)
    await run_mac_test(dut, 0, a_elements, b_elements, round_mode=1)
    # FLR: -(40+1) * 32 = -1312
    await run_mac_test(dut, 0, a_elements, b_elements, round_mode=2)
    # RNE: -40 * 32 = -1280
    await run_mac_test(dut, 0, a_elements, b_elements, round_mode=3)

@cocotb.test()
async def test_overflow_saturation(dut):
    dut._log.info("Start Overflow Saturation Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = [0x7C] * 32 # Max finite E5M2
    b_elements = [0x7C] * 32

    # Saturation
    await run_mac_test(dut, 1, a_elements, b_elements, overflow_wrap=0)
    # Wrap
    await run_mac_test(dut, 1, a_elements, b_elements, overflow_wrap=1)

@cocotb.test()
async def test_accumulator_saturation(dut):
    dut._log.info("Start Accumulator Saturation Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    a_elements = [0x78] * 32 # E5M2: ea=30
    b_elements = [0x78] * 32

    # Accumulator Saturation
    await run_mac_test(dut, 1, a_elements, b_elements, overflow_wrap=0)
    # Accumulator Wrap
    await run_mac_test(dut, 1, a_elements, b_elements, overflow_wrap=1)

@cocotb.test()
async def test_mxfp_mac_randomized(dut):
    import random
    dut._log.info("Start Randomized MXFP MAC Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    for i in range(50):
        format_val = random.randint(0, 6)
        round_mode = random.randint(0, 3)
        overflow_wrap = random.randint(0, 1)
        a_elements = [random.randint(0, 255) for _ in range(32)]
        b_elements = [random.randint(0, 255) for _ in range(32)]
        await run_mac_test(dut, format_val, a_elements, b_elements, round_mode, overflow_wrap)
