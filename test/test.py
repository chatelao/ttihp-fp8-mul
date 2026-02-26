# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

def align_product_model(a_bits, b_bits, is_e5m2):
    if is_e5m2:
        # E5M2 Extraction
        ea = (a_bits >> 2) & 0x1F
        eb = (b_bits >> 2) & 0x1F
        ma = (a_bits & 0x3) << 1
        mb = (b_bits & 0x3) << 1
        exp_bias = 23
    else:
        # E4M3 Extraction
        ea = (a_bits >> 3) & 0xF
        eb = (b_bits >> 3) & 0xF
        ma = (a_bits & 0x7)
        mb = (b_bits & 0x7)
        exp_bias = 7

    sign = ((a_bits >> 7) & 1) ^ ((b_bits >> 7) & 1)

    if ea == 0 or eb == 0:
        return 0

    prod = (8 + ma) * (8 + mb)
    exp_sum = ea + eb - exp_bias
    shift_amt = exp_sum - 5

    if shift_amt >= 0:
        aligned = prod << shift_amt
    else:
        aligned = prod >> (-shift_amt)

    if sign:
        if aligned > 0x80000000:
            aligned = 0x80000000
        else:
            aligned = -aligned
    else:
        if aligned > 0x7FFFFFFF:
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

@cocotb.test()
async def test_mxfp8_mac_e4m3(dut):
    dut._log.info("Start MXFP8 MAC Test (E4M3)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # State should now be LOAD_SCALE, cycle_count=1
    # Capture scale_a and is_e5m2 at edge 1->2
    dut.ui_in.value = 0x00
    dut.uio_in.value = 0x00
    await ClockCycles(dut.clk, 1) # EDGE 1 -> 2. state=LOAD_SCALE, cycle_count=2

    # Capture scale_b at edge 2->3
    dut.ui_in.value = 0x00
    dut.uio_in.value = 0x00
    await ClockCycles(dut.clk, 1) # EDGE 2 -> 3. state=STREAM, cycle_count=3

    # Stream elements (Cycle 3 to 34)
    a_elements = [0x38] * 32 # 1.0
    b_elements = [0x38] * 32
    is_e5m2 = False

    expected_acc = 0
    for a, b in zip(a_elements, b_elements):
        expected_acc = (expected_acc + align_product_model(a, b, is_e5m2)) & 0xFFFFFFFF
        if expected_acc & 0x80000000:
            expected_acc -= 0x100000000

    for i in range(32):
        dut.ui_in.value = a_elements[i]
        dut.uio_in.value = b_elements[i]
        await ClockCycles(dut.clk, 1)

    # Cycle 35 is now active. State=OUTPUT
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, 1)

    if actual_acc & 0x80000000:
        actual_acc -= 0x100000000

    dut._log.info(f"Expected: {expected_acc}, Actual: {actual_acc}")
    assert actual_acc == expected_acc

@cocotb.test()
async def test_mxfp8_mac_randomized(dut):
    import random
    dut._log.info("Start Randomized MXFP8 MAC Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    for i in range(5):
        await reset_dut(dut)
        is_e5m2 = random.choice([True, False])

        # Cycle 1
        dut.ui_in.value = random.randint(0, 255)
        dut.uio_in.value = 1 if is_e5m2 else 0
        await ClockCycles(dut.clk, 1)

        # Cycle 2
        dut.ui_in.value = random.randint(0, 255)
        dut.uio_in.value = random.randint(0, 255)
        await ClockCycles(dut.clk, 1)

        a_elements = [random.randint(0, 255) for _ in range(32)]
        b_elements = [random.randint(0, 255) for _ in range(32)]

        expected_acc = 0
        for a, b in zip(a_elements, b_elements):
            expected_acc = (expected_acc + align_product_model(a, b, is_e5m2)) & 0xFFFFFFFF
            if expected_acc & 0x80000000:
                expected_acc -= 0x100000000

        for j in range(32):
            dut.ui_in.value = a_elements[j]
            dut.uio_in.value = b_elements[j]
            await ClockCycles(dut.clk, 1)

        actual_acc = 0
        for j in range(4):
            await Timer(1, unit="ns")
            actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
            await ClockCycles(dut.clk, 1)

        if actual_acc & 0x80000000:
            actual_acc -= 0x100000000

        dut._log.info(f"Iteration {i} ({'E5M2' if is_e5m2 else 'E4M3'}): Expected: {expected_acc}, Actual: {actual_acc}")
        assert actual_acc == expected_acc

@cocotb.test()
async def test_mxfp8_mac_e5m2(dut):
    dut._log.info("Start MXFP8 MAC Test (E5M2)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    await reset_dut(dut)

    # Cycle 1
    dut.ui_in.value = 0x00
    dut.uio_in.value = 0x01 # is_e5m2 = 1
    await ClockCycles(dut.clk, 1)

    # Cycle 2
    dut.ui_in.value = 0x00
    dut.uio_in.value = 0x00
    await ClockCycles(dut.clk, 1)

    # Stream elements
    a_elements = [0x3C] * 32 # 1.0 in E5M2
    b_elements = [0x3C] * 32
    is_e5m2 = True

    expected_acc = 0
    for a, b in zip(a_elements, b_elements):
        expected_acc = (expected_acc + align_product_model(a, b, is_e5m2)) & 0xFFFFFFFF
        if expected_acc & 0x80000000:
            expected_acc -= 0x100000000

    for i in range(32):
        dut.ui_in.value = a_elements[i]
        dut.uio_in.value = b_elements[i]
        await ClockCycles(dut.clk, 1)

    # Cycle 35-38
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, 1)

    if actual_acc & 0x80000000:
        actual_acc -= 0x100000000

    dut._log.info(f"Expected: {expected_acc}, Actual: {actual_acc}")
    assert actual_acc == expected_acc
