import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from test import run_mac_test, get_param

@cocotb.test()
async def test_subnormal_summation_precision(dut):
    """
    Test that 32 subnormal products (each 2^-9) sum up to 2^-4 (0.0625).
    In the old 8-bit fractional alignment, each 2^-9 was 0, so the sum was 0.
    In the new 16-bit fractional alignment, the sum should be correct.
    """
    dut._log.info("Start Subnormal Summation Precision Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # E4M3: 0x01 is subnormal (2^-9)
    # 0x38 is 1.0
    a_elements = [0x01] * 32
    b_elements = [0x38] * 32

    # Expected: 32 * 2^-9 = 2^-4 = 0.0625
    # In S23.8 output format, 0.0625 * 256 = 16.
    await run_mac_test(dut, 0, 0, a_elements, b_elements)

@cocotb.test()
async def test_high_precision_accumulation(dut):
    """
    Test accumulation of many small values that would be lost in 8-bit fractional format.
    Each element: 1.0 * 2^-12 = 2^-12.
    32 elements: 32 * 2^-12 = 2^-7 = 0.0078125.
    In S23.8: 0.0078125 * 256 = 2.
    Old 8-bit: Each element was 0. Sum = 0.
    """
    dut._log.info("Start High Precision Accumulation Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # E5M2: 0x01 is subnormal (2^-14 * 0.25 = 2^-16) -- wait, let's use something larger
    # E5M2: 0x04 is 2^-14 (Smallest normal)
    # 0x0C is 2^-12
    # 0x3C is 1.0
    a_elements = [0x0C] * 32
    b_elements = [0x3C] * 32

    # Expected: 32 * 2^-12 = 2^-7.
    # In S23.8: 2.
    await run_mac_test(dut, 1, 1, a_elements, b_elements)
