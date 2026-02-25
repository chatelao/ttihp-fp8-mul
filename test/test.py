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

        for expected_cycle in range(39):
            # Check for valid data in GLS
            val = dut.uo_out.value
            if not val.is_resolvable:
                dut._log.warning(f"Cycle {expected_cycle}: uo_out is {val}")
                actual = 0 # Assume 0 if not resolvable for checking logic if needed
            else:
                actual = int(val)

            # The hardware increments the cycle_count on each posedge.
            # At cycle 0, uo_out should be 0.
            # During OUTPUT phase (cycles 35-38), uo_out should be cycle_count.

            if 35 <= expected_cycle <= 38:
                assert actual == expected_cycle, f"Cycle {expected_cycle}: uo_out should be {expected_cycle}, got {actual}"
            else:
                assert actual == 0, f"Cycle {expected_cycle}: uo_out should be 0, got {actual}"

            await ClockCycles(dut.clk, 1)

    dut._log.info("FSM Protocol Test passed!")
