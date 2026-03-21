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

    support_serial = get_param(dut, "SUPPORT_SERIAL", 0)
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1) if support_serial else 1
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    if not support_mxfp4:
        dut._log.info("Skipping Short Protocol Test (SUPPORT_MXFP4=0)")
        return

    # 1. Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    # Cycle 0 sampling: Wait for stable reset release
    await RisingEdge(dut.clk)

    # Now at Cycle 0. Sampling happens at the end of this logical cycle.
    dut.ui_in.value = 0x80 # Short Protocol = 1
    dut.uio_in.value = 4    # Format A/B = 4 (E2M1)

    # Wait for the strobe to sample metadata and move to Cycle 3
    for _ in range(k_factor):
        await RisingEdge(dut.clk)

    # Now at Cycle 3. Verify format capture if accessible.
    await Timer(1, "ns")
    try:
        f_a = int(dut.user_project.format_a.value)
        dut._log.info(f"Verified active format A: {f_a}")
        assert f_a == 4
    except AttributeError:
        dut._log.info("Signals not accessible for direct assertion")

    # Finish block with 1.0 * 1.0 (0x02 * 0x02)
    for _ in range(32):
        dut.ui_in.value = 0x02
        dut.uio_in.value = 0x02
        await ClockCycles(dut.clk, k_factor)

    await ClockCycles(dut.clk, 2 * k_factor) # Flush + Scale

    # Read Result (Cycle 37-40)
    actual_acc = 0
    for _ in range(4):
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

    support_serial = get_param(dut, "SUPPORT_SERIAL", 0)
    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1) if support_serial else 1
    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    if not support_shared:
        dut._log.info("Skipping test (ENABLE_SHARED_SCALING=0)")
        return

    # 1. First block: Standard protocol, load scale_a = 0xFF
    dut.ena.value = 1
    dut.ui_in.value = 0x00 # Standard protocol
    dut.uio_in.value = 0x00
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1

    # Cycle 0 (Standard protocol)
    await ClockCycles(dut.clk, k_factor)

    # Cycle 1: Load Scale A = 0xFF
    dut.ui_in.value = 0xFF
    dut.uio_in.value = 0 # Format A = E4M3
    await ClockCycles(dut.clk, k_factor)

    # Cycle 2: Load Scale B = 127
    dut.ui_in.value = 127
    dut.uio_in.value = 0 # Format B = E4M3
    await ClockCycles(dut.clk, k_factor)

    # Stream 32 elements (1.0 * 1.0)
    for _ in range(32):
        dut.ui_in.value = 0x38
        dut.uio_in.value = 0x38
        await ClockCycles(dut.clk, k_factor)

    # Flush & Scale (Cycle 35, 36)
    await ClockCycles(dut.clk, 2 * k_factor)

    # Output Phase (Cycles 37, 38, 39, 40)
    for i in range(4):
        if i == 3:
            # At the start of logical Cycle 40, set pins for block 2's Cycle 0
            # samplings happens at the *end* of the physical block (last k_factor edge)
            dut.ui_in.value = 0x80 # Short Protocol = 1
            dut.uio_in.value = 0    # Format A/B = 0
        await ClockCycles(dut.clk, k_factor)

    # Block 1 finishes, Block 2 samples Cycle 0 at the next edge and jumps to Cycle 3
    # Wait one strobe period for the FSM to transition
    await ClockCycles(dut.clk, k_factor)

    # 2. Now at Cycle 3 of the Short Protocol block
    # Verify nan_sticky initialization
    await Timer(1, "ns")
    try:
        nan_sticky = int(dut.user_project.nan_sticky.value)
        curr_cycle = int(dut.user_project.cycle_count.value)
        dut._log.info(f"nan_sticky value at start of Short Protocol block (Cycle {curr_cycle}): {nan_sticky}")
        assert nan_sticky == 1
    except AttributeError:
        dut._log.info("nan_sticky signal not accessible")

    # Finish the second block
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
