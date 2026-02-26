# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer

def align_product_model(a_bits, b_bits, format_val):
    if format_val == 0: # E4M3
        ea = (a_bits >> 3) & 0xF
        ma = (a_bits & 0x7)
        eb = (b_bits >> 3) & 0xF
        mb = (b_bits & 0x7)
        bias = 7
        sign_a = (a_bits >> 7) & 1
        sign_b = (b_bits >> 7) & 1
    elif format_val == 1: # E5M2
        ea = (a_bits >> 2) & 0x1F
        ma = (a_bits & 0x3) << 1
        eb = (b_bits >> 2) & 0x1F
        mb = (b_bits & 0x3) << 1
        bias = 15
        sign_a = (a_bits >> 7) & 1
        sign_b = (b_bits >> 7) & 1
    elif format_val == 2: # E3M2
        ea = (a_bits >> 2) & 0x7
        ma = (a_bits & 0x3) << 1
        eb = (b_bits >> 2) & 0x7
        mb = (b_bits & 0x3) << 1
        bias = 3
        sign_a = (a_bits >> 5) & 1
        sign_b = (b_bits >> 5) & 1
    elif format_val == 3: # E2M3
        ea = (a_bits >> 3) & 0x3
        ma = (a_bits & 0x7)
        eb = (b_bits >> 3) & 0x3
        mb = (b_bits & 0x7)
        bias = 1
        sign_a = (a_bits >> 5) & 1
        sign_b = (b_bits >> 5) & 1
    elif format_val == 4: # E2M1
        ea = (a_bits >> 1) & 0x3
        ma = (a_bits & 0x1) << 2
        eb = (b_bits >> 1) & 0x3
        mb = (b_bits & 0x1) << 2
        bias = 1
        sign_a = (a_bits >> 3) & 1
        sign_b = (b_bits >> 3) & 1
    else: # Default to E4M3
        return align_product_model(a_bits, b_bits, 0)

    sign = sign_a ^ sign_b

    if ea == 0 or eb == 0:
        return 0

    prod = (8 + ma) * (8 + mb)
    exp_sum = ea + eb - 2*bias + 7
    shift_amt = exp_sum - 5

    if shift_amt >= 0:
        aligned = prod << shift_amt
    else:
        # Avoid negative shifts
        if (-shift_amt) >= 64:
            aligned = 0
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

async def run_mac_test(dut, format_val, a_elements, b_elements):
    await reset_dut(dut)

    # Cycle 1: Load Scale A and Format Select
    dut.ui_in.value = 0x00 # Scale A
    dut.uio_in.value = format_val
    await ClockCycles(dut.clk, 1)

    # Cycle 2: Load Scale B
    dut.ui_in.value = 0x00
    dut.uio_in.value = 0x00 # Scale B
    await ClockCycles(dut.clk, 1)

    expected_acc = 0
    for a, b in zip(a_elements, b_elements):
        expected_acc = (expected_acc + align_product_model(a, b, format_val)) & 0xFFFFFFFF
        if expected_acc & 0x80000000:
            expected_acc -= 0x100000000

    for i in range(32):
        dut.ui_in.value = a_elements[i]
        dut.uio_in.value = b_elements[i]
        await ClockCycles(dut.clk, 1)

    # Cycle 35-38: Output Serialized Result
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, 1)

    if actual_acc & 0x80000000:
        actual_acc -= 0x100000000

    format_names = ["E4M3", "E5M2", "E3M2", "E2M3", "E2M1"]
    name = format_names[format_val] if format_val < len(format_names) else "Unknown"
    dut._log.info(f"Format: {name}, Expected: {expected_acc}, Actual: {actual_acc}")
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
async def test_mxfp6_mac_e3m2(dut):
    dut._log.info("Start MXFP6 MAC Test (E3M2)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x0C] * 32 # 1.0 in E3M2 (S=0, E=3, M=0) -> bit 5=0, bit [4:2]=3, bit [1:0]=0 -> 001100 = 0x0C
    b_elements = [0x0C] * 32
    await run_mac_test(dut, 2, a_elements, b_elements)

@cocotb.test()
async def test_mxfp6_mac_e2m3(dut):
    dut._log.info("Start MXFP6 MAC Test (E2M3)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x08] * 32 # 1.0 in E2M3 (S=0, E=1, M=0) -> bit 5=0, bit [4:3]=1, bit [2:0]=0 -> 001000 = 0x08
    b_elements = [0x08] * 32
    await run_mac_test(dut, 3, a_elements, b_elements)

@cocotb.test()
async def test_mxfp4_mac_e2m1(dut):
    dut._log.info("Start MXFP4 MAC Test (E2M1)")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    a_elements = [0x02] * 32 # 1.0 in E2M1 (S=0, E=1, M=0) -> bit 3=0, bit [2:1]=1, bit 0=0 -> 0010 = 0x02
    b_elements = [0x02] * 32
    await run_mac_test(dut, 4, a_elements, b_elements)

@cocotb.test()
async def test_mxfp_mac_randomized(dut):
    import random
    dut._log.info("Start Randomized MXFP MAC Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    for i in range(20):
        format_val = random.randint(0, 4)
        a_elements = [random.randint(0, 255) for _ in range(32)]
        b_elements = [random.randint(0, 255) for _ in range(32)]
        await run_mac_test(dut, format_val, a_elements, b_elements)
