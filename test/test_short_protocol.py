import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer
import os
import sys

# Add current directory to path to import test
sys.path.append(os.path.dirname(__file__))
from test import run_mac_test, get_param, decode_format, align_product_model, align_model, reset_dut

@cocotb.test()
async def test_short_protocol_metadata(dut):
    """
    Verify that Short Protocol correctly captures metadata from uio_in[2:0] in Cycle 0.
    """
    dut._log.info("Start Short Protocol Metadata Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1)
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    if not support_mxfp4:
        dut._log.info("Skipping Short Protocol Test (SUPPORT_MXFP4=0)")
        return

    # 1. Reset with Short Protocol pins already set
    dut.ena.value = 1
    dut.ui_in.value = 0x80 # Short Protocol = 1
    dut.uio_in.value = 4    # Format A/B = 4 (E2M1)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # samples metadata on the first strobe of logical cycle 0 (immediately after reset)
    # wait for that edge
    await RisingEdge(dut.clk)

    # FSM should have sampled and jumped to Cycle 3 immediately
    await Timer(1, "ns")
    try:
        curr_cycle = int(dut.user_project.cycle_count.value)
        dut._log.info(f"FSM State after Cycle 0 jump: {curr_cycle}")
    except AttributeError:
        pass

    # Finish block with 1.0 * 1.0 (0x02 * 0x02)
    for _ in range(32):
        dut.ui_in.value = 0x02
        dut.uio_in.value = 0x02
        await ClockCycles(dut.clk, k_factor)

    await ClockCycles(dut.clk, 2 * k_factor) # Flush + Scale

    # Read Result (Cycle 37-40)
    actual_acc = 0
    for i in range(4):
        await Timer(1, "ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor)

    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    expected = 0 if support_shared else 8192

    dut._log.info(f"Actual Result: {actual_acc}, Expected: {expected}")
    assert actual_acc == expected

@cocotb.test()
async def test_short_protocol_nan_scale_reuse(dut):
    """
    Test that starting a Short Protocol block with reused NaN (0xFF) scales
    correctly latches the nan_sticky bit.
    """
    dut._log.info("Start Short Protocol NaN Scale Reuse Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1)
    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    if not support_shared:
        dut._log.info("Skipping test (ENABLE_SHARED_SCALING=0)")
        return

    # 1. First block: Standard protocol, load scale_a = 0xFF
    dut.ena.value = 1
    dut.ui_in.value = 0x00
    dut.uio_in.value = 0x00
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # samples Cycle 0 (Standard), moves to Cycle 1
    await ClockCycles(dut.clk, k_factor)

    # Cycle 1: Load Scale A = 0xFF
    dut.ui_in.value = 0xFF
    dut.uio_in.value = 0 # Format A = E4M3
    await ClockCycles(dut.clk, k_factor)

    # Cycle 2: Load Scale B = 127
    dut.ui_in.value = 127
    dut.uio_in.value = 0 # Format B = E4M3
    await ClockCycles(dut.clk, k_factor)

    # Stream 32 elements
    for _ in range(32):
        dut.ui_in.value = 0x38
        dut.uio_in.value = 0x38
        await ClockCycles(dut.clk, k_factor)

    await ClockCycles(dut.clk, 2 * k_factor) # Flush + Scale

    # Output Phase (Cycles 37, 38, 39, 40)
    for i in range(4):
        # We must set ui_in[7] for the NEXT block's Cycle 0
        # Sampling for the next block happens on the edge that transitions FROM 40 TO 0
        if i == 3:
            dut.ui_in.value = 0x80 # Short Protocol = 1
            dut.uio_in.value = 0
        await ClockCycles(dut.clk, k_factor)

    # Transition to next block (sampling happens here)
    await Timer(1, "ns") # Check state after jump

    # 2. Now at start of logical Cycle 3.
    try:
        nan_sticky = int(dut.user_project.nan_sticky.value)
        curr_cycle = int(dut.user_project.cycle_count.value)
        dut._log.info(f"nan_sticky at start of Short Protocol (Cycle {curr_cycle}): {nan_sticky}")
        assert nan_sticky == 1
    except AttributeError:
        pass

    # Finish second block
    for _ in range(32):
        dut.ui_in.value = 0x38
        dut.uio_in.value = 0x38
        await ClockCycles(dut.clk, k_factor)

    await ClockCycles(dut.clk, 2 * k_factor) # Flush + Scale

    # Read Result (Cycle 37-40)
    actual_acc = 0
    for _ in range(4):
        await Timer(1, "ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor)

    # Result should be NaN (0x7FC00000)
    dut._log.info(f"Actual Result: 0x{actual_acc:08X}, Expected: 0x7FC00000")
    assert actual_acc == 0x7FC00000
