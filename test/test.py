# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

@cocotb.test()
async def test_fsm_protocol(dut):
    dut._log.info("Start FSM Protocol Test")

    # Set the clock period to 10 ns (100 MHz)
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # Wait for reset to de-assert and first clock edge
    await ClockCycles(dut.clk, 1)

    # We expect 39 cycles per iteration (0 to 38)
    for iteration in range(3):
        dut._log.info(f"Iteration {iteration}")

        for _ in range(39):
            cycle = int(dut.user_project.cycle_count.value)
            state = int(dut.user_project.state.value)
            actual = int(dut.uo_out.value)
            # dut._log.info(f"Internal cycle_count={cycle}, state={state}, uo_out={actual}")

            if 35 <= cycle <= 38:
                assert actual == cycle, f"Cycle {cycle}: uo_out should be {cycle}, got {actual}"
            else:
                assert actual == 0, f"Cycle {cycle}: uo_out should be 0, got {actual}"

            await ClockCycles(dut.clk, 1)

    dut._log.info("FSM Protocol Test passed!")
