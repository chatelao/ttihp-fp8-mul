# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

async def store(dut, operand, half, data):
    # operand: 0 for operand1, 1 for operand2
    # half: 0 for bits 3:0, 1 for bits 7:4
    # data: 4-bit value
    ctrl = (half << 2) | (operand << 1) | 0 # ctrl[0]=0 for store
    dut.ui_in.value = (data << 4) | (ctrl << 1)
    await ClockCycles(dut.clk, 1)

async def load_operand(dut, operand, value):
    await store(dut, operand, 0, value & 0xF)
    await store(dut, operand, 1, (value >> 4) & 0xF)

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 ns (100 MHz)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    dut._log.info("Test FP8 Multiplier")

    # Load operand 1: 1.0 (0x38)
    # Load operand 2: 1.0 (0x38)
    await load_operand(dut, 0, 0x38)
    await load_operand(dut, 1, 0x38)

    # The multiplier is combinational from the stored operands.
    # We might need to wait a tiny bit or just check.
    # Since it's RTL, it's immediate after the clock edge that stores the last nibble.
    await ClockCycles(dut.clk, 1)

    dut._log.info(f"uo_out: {hex(int(dut.uo_out.value))}")
    assert dut.uo_out.value == 0x38 # 1.0 * 1.0 = 1.0

    # Load operand 1: 2.0 (sign=0, exp=8(1000), mant=0(000) -> 0_1000_000 = 0x40)
    # Load operand 2: 0.5 (sign=0, exp=6(0110), mant=0(000) -> 0_0110_000 = 0x30)
    # 2.0 * 0.5 = 1.0 (0x38)
    await load_operand(dut, 0, 0x40)
    await load_operand(dut, 1, 0x30)
    await ClockCycles(dut.clk, 1)
    dut._log.info(f"uo_out: {hex(int(dut.uo_out.value))}")
    assert dut.uo_out.value == 0x38

    # Test with negative numbers
    # -1.0 is 0xB8 (sign=1, exp=7, mant=0)
    # -1.0 * 1.0 = -1.0 (0xB8)
    await load_operand(dut, 0, 0xB8)
    await load_operand(dut, 1, 0x38)
    await ClockCycles(dut.clk, 1)
    dut._log.info(f"uo_out: {hex(int(dut.uo_out.value))}")
    assert dut.uo_out.value == 0xB8

    # -1.0 * -1.0 = 1.0 (0x38)
    await load_operand(dut, 0, 0xB8)
    await load_operand(dut, 1, 0xB8)
    await ClockCycles(dut.clk, 1)
    dut._log.info(f"uo_out: {hex(int(dut.uo_out.value))}")
    assert dut.uo_out.value == 0x38
