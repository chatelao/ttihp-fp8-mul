# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

@cocotb.test()
async def test_fp8_multiplier(dut):
    dut._log.info("Start FP8 Multiplier test")

    # The actual clock in the design is ui_in[0]
    # The 'clk' input of the module is shadowed.

    # Initialize values
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0

    # Proper reset sequence
    await Timer(10, unit="ns")
    dut.rst_n.value = 1
    await Timer(10, unit="ns")

    async def store_val(op_sel, val):
        # Store lower nibble
        data_low = val & 0xF
        ui_val = (data_low << 4) | (0 << 3) | (op_sel << 2) | (0 << 1)
        dut.ui_in.value = ui_val
        await Timer(1, unit="ns")
        dut.ui_in.value = ui_val | 1 # posedge
        await Timer(1, unit="ns")
        dut.ui_in.value = ui_val # negedge
        await Timer(1, unit="ns")

        # Store upper nibble
        data_high = (val >> 4) & 0xF
        ui_val = (data_high << 4) | (1 << 3) | (op_sel << 2) | (0 << 1)
        dut.ui_in.value = ui_val
        await Timer(1, unit="ns")
        dut.ui_in.value = ui_val | 1 # posedge
        await Timer(1, unit="ns")
        dut.ui_in.value = ui_val # negedge
        await Timer(1, unit="ns")

    # Load 1.0 (0x38) into Op1 and Op2
    await store_val(0, 0x38)
    await store_val(1, 0x38)

    await Timer(10, unit="ns")
    val = int(dut.uo_out.value)
    dut._log.info(f"Output: {hex(val)}")
    assert val == 0x38

    # Load 2.0 (0x40) into Op1
    await store_val(0, 0x40)
    await Timer(10, unit="ns")
    val = int(dut.uo_out.value)
    dut._log.info(f"Output: {hex(val)}")
    assert val == 0x40

    # Load 0.5 (0x30) into Op2
    await store_val(1, 0x30)
    await Timer(10, unit="ns")
    val = int(dut.uo_out.value)
    dut._log.info(f"Output: {hex(val)}")
    assert val == 0x38
