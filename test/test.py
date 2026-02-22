# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    dut._log.info("Test project behavior")

    # Test cases: (A, B, Expected)
    test_cases = [
        (0x40, 0x40, 0x48), # 2.0 * 2.0 = 4.0
        (0x38, 0x38, 0x38), # 1.0 * 1.0 = 1.0
        (0x40, 0x38, 0x40), # 2.0 * 1.0 = 2.0
        (0x00, 0x40, 0x00), # 0.0 * 2.0 = 0.0
        (0x80, 0x40, 0x80), # -0.0 * 2.0 = -0.0
        (0x7F, 0x38, 0x7F), # NaN * 1.0 = NaN
    ]

    for a, b, expected in test_cases:
        dut.ui_in.value = a
        dut.uio_in.value = b
        await ClockCycles(dut.clk, 1)
        dut._log.info(f"Input: A=0x{a:02x}, B=0x{b:02x} | Output: 0x{int(dut.uo_out.value):02x} | Expected: 0x{expected:02x}")
        assert int(dut.uo_out.value) == expected

    dut._log.info("All tests passed!")
