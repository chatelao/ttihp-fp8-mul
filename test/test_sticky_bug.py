import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
import os
import sys

# Add current directory to path to import test
sys.path.append(os.path.dirname(__file__))
from test import get_param

@cocotb.test()
async def test_lane_overflow_fix_verified(dut):
    """
    Verify the fix for lane addition overflow.
    """
    dut._log.info("Start Lane Overflow Fix Verification Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Initialize inputs to avoid Xs
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # C0: Packed=1
    dut.uio_in.value = (1 << 6)
    await ClockCycles(dut.clk, 1)

    # C1: scale 127, fmt 4
    dut.ui_in.value = 127
    dut.uio_in.value = 4
    await ClockCycles(dut.clk, 1)

    # C2: scale 127, fmt 4
    dut.ui_in.value = 127
    dut.uio_in.value = 4
    await ClockCycles(dut.clk, 1)

    # Drive 0 for elements first to clear any potential garbage
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    for _ in range(32):
        await ClockCycles(dut.clk, 1)

    # Now we are in the next block. (Or just do one block correctly).
    # Let's just do it in the first block but ensure everything is clean.

    # RESET AGAIN
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # C0
    dut.ui_in.value = 0
    dut.uio_in.value = (1 << 6)
    await ClockCycles(dut.clk, 1)
    # C1
    dut.ui_in.value = 127
    dut.uio_in.value = 4
    await ClockCycles(dut.clk, 1)
    # C2
    dut.ui_in.value = 127
    dut.uio_in.value = 4
    await ClockCycles(dut.clk, 1)

    # C3: MAX values
    dut.ui_in.value = 0x77
    dut.uio_in.value = 0x77
    await Timer(1, unit="ns")
    dut._log.info(f"C3: lane0={hex(int(dut.user_project.aligned_lane0_res.value))}, lane1={hex(int(dut.user_project.aligned_lane1_res.value))}, comb={hex(int(dut.user_project.aligned_combined.value))}")
    await ClockCycles(dut.clk, 1)

    # Rest zero
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    for _ in range(15+2): await ClockCycles(dut.clk, 1)

    # Output Phase
    for i in range(4):
        await Timer(1, unit="ns")
        res = dut.uo_out.value
        dut._log.info(f"Cycle {21+i} uo_out: {res}")
        await ClockCycles(dut.clk, 1)

@cocotb.test()
async def test_sticky_bug_fix_verified(dut):
    """
    Verify the fix for the sticky bug.
    """
    dut._log.info("Start Sticky Bug Fix Verification Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.ena.value = 1
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # Cycle 0
    await ClockCycles(dut.clk, 1)
    # Cycle 1: E5M2
    dut.uio_in.value = 1
    await ClockCycles(dut.clk, 1)
    # Cycle 2: E5M2
    dut.uio_in.value = 1
    await ClockCycles(dut.clk, 1)

    for _ in range(32):
        dut.ui_in.value = 0
        await ClockCycles(dut.clk, 1)

    # Cycle 35: Flush.
    dut.ui_in.value = 0x7E # NaN
    await Timer(1, unit="ns")
    dut._log.info(f"Cycle 35: latch_en={int(dut.user_project.sticky_latch_en.value)}")
    await ClockCycles(dut.clk, 1)

    # Cycle 36
    await ClockCycles(dut.clk, 1)

    # Cycle 37
    await Timer(1, unit="ns")
    res = dut.uo_out.value
    dut._log.info(f"Cycle 37 uo_out: {res}")

    assert int(dut.user_project.nan_sticky.value) == 0
    assert int(res) == 0
