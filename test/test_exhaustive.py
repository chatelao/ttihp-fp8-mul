import cocotb
from cocotb.clock import Clock
import random
from test import run_mac_test, get_param

@cocotb.test()
async def test_fp4_exhaustive(dut):
    """Test all 16x16 = 256 combinations of FP4 (E2M1) bit patterns"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    if not support_mxfp4:
        dut._log.info("Skipping FP4 exhaustive test: SUPPORT_MXFP4=0")
        return

    # Total 256 combinations (16 * 16)
    # We can pack these into 8 MAC runs of 32 elements each
    all_pairs = [(a, b) for a in range(16) for b in range(16)]

    for i in range(0, 256, 32):
        chunk = all_pairs[i:i+32]
        a_els = [p[0] for p in chunk]
        b_els = [p[1] for p in chunk]
        # Pad with zeros if necessary (not needed here since 256 % 32 == 0)
        await run_mac_test(dut, format_a=4, format_b=4, a_elements=a_els, b_elements=b_els)

@cocotb.test()
async def test_fp8_e4m3_mantissa_exhaustive(dut):
    """Test all 8x8 = 64 combinations of E4M3 normal mantissas"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    support_e4m3 = get_param(dut, "SUPPORT_E4M3", 1)
    if not support_e4m3:
        dut._log.info("Skipping E4M3 exhaustive test: SUPPORT_E4M3=0")
        return

    # E4M3 normal mantissas are bit patterns where exp != 0.
    # We'll use exp=7 (bias) so value is 1.mant
    # Bit patterns: 0x38 (1.000) to 0x3F (1.111)
    all_pairs = [(a, b) for a in range(0x38, 0x40) for b in range(0x38, 0x40)]

    for i in range(0, 64, 32):
        chunk = all_pairs[i:i+32]
        a_els = [p[0] for p in chunk]
        b_els = [p[1] for p in chunk]
        await run_mac_test(dut, format_a=0, format_b=0, a_elements=a_els, b_elements=b_els)

@cocotb.test()
async def test_fp8_e5m2_mantissa_exhaustive(dut):
    """Test all 8x8 = 64 combinations of E5M2 mantissas (including subnormals)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    support_e5m2 = get_param(dut, "SUPPORT_E5M2", 1)
    if not support_e5m2:
        dut._log.info("Skipping E5M2 exhaustive test: SUPPORT_E5M2=0")
        return

    # E5M2 has 2-bit mantissa.
    # Subnormals (exp=0): 0x00, 0x01, 0x02, 0x03
    # Normals (exp=1): 0x04, 0x05, 0x06, 0x07
    # Total 8 bit patterns covering the full mantissa space at the bottom of the range.
    all_pairs = [(a, b) for a in range(8) for b in range(8)]

    for i in range(0, 64, 32):
        chunk = all_pairs[i:i+32]
        a_els = [p[0] for p in chunk]
        b_els = [p[1] for p in chunk]
        await run_mac_test(dut, format_a=1, format_b=1, a_elements=a_els, b_elements=b_els)
