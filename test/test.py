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

    async def store(operand, upper, data):
        # ui_in[1] is store_en_n (active low)
        # ui_in[2] is op_sel (0=op1, 1=op2)
        # ui_in[3] is nibble_sel (0=lower, 1=upper)
        # ui_in[7:4] is data
        val = (data << 4) | (upper << 3) | (operand << 2) | (0 << 1) | 0
        dut.ui_in.value = val
        await ClockCycles(dut.clk, 1)
        # De-assert store_en
        dut.ui_in.value = val | 2
        await ClockCycles(dut.clk, 1)

    # Load 1.0 (0x38) into operand 1
    await store(0, 0, 0x8) # op1 lower = 0x8
    await store(0, 1, 0x3) # op1 upper = 0x3

    # Load 1.0 (0x38) into operand 2
    await store(1, 0, 0x8) # op2 lower = 0x8
    await store(1, 1, 0x3) # op2 upper = 0x3

    # Wait for result
    await ClockCycles(dut.clk, 1)

    # 1.0 * 1.0 = 1.0 (0x38)
    assert dut.uo_out.value == 0x38

    # Load 2.0 (0x40) into operand 2
    # 2.0 = (-1)^0 * 2^(8-7) * 1.000 = 0_1000_000 = 0x40
    await store(1, 0, 0x0) # op2 lower = 0x0
    await store(1, 1, 0x4) # op2 upper = 0x4

    await ClockCycles(dut.clk, 1)
    # 1.0 * 2.0 = 2.0 (0x40)
    assert dut.uo_out.value == 0x40
