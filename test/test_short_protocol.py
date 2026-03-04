import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
import os
import sys

# Add current directory to path to import test
sys.path.append(os.path.dirname(__file__))
from test import get_param, decode_format, align_product_model, align_model, reset_dut

@cocotb.test()
async def test_short_protocol_metadata(dut):
    dut._log.info("Start Short Protocol Metadata Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1)

    # 1. Reset with Short Protocol Start
    dut.ena.value = 1
    # ui_in[7]=1 (Fast Start), ui_in[6]=1 (Packed Mode)
    # uio_in: format_a=4 (bits 2:0), round_mode=0 (bits 4:3), overflow_wrap=0 (bit 5)
    dut.ui_in.value = 0x80 | 0x40
    dut.uio_in.value = 4 # E2M1
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # After first clock edge, cycle_count becomes 3.
    # We wait k_factor cycles to align with the first element sampling.
    await ClockCycles(dut.clk, k_factor)

    # Unit should now be at Cycle 3 (STATE_STREAM)
    # We expect it to use format_a=4.

    # E2M1: 1.0 is 0x02.
    # Each byte 0x22 = two 1.0s.
    for i in range(16):
        dut.ui_in.value = 0x22
        dut.uio_in.value = 0x22
        await ClockCycles(dut.clk, k_factor)

    await ClockCycles(dut.clk, 2 * k_factor) # Flush + Shared Scale

    # Expected: 32 * 1.0 * 1.0 = 32.
    # In fixed point (bit 8 = 1.0), 32 * 256 = 8192.

    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor)

    if actual_acc & 0x80000000: actual_acc -= 0x100000000

    dut._log.info(f"Actual Result: {actual_acc}")
    # Currently this is expected to FAIL (result will be 0 or small)
    assert actual_acc == 8192
