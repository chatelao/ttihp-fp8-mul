import cocotb
from cocotb.clock import Clock
from test import run_mac_test, get_param

@cocotb.test()
async def test_ofp8_e4m3_compliance(dut):
    """Compliance test for OCP-OFP8 E4M3 format"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    if not get_param(dut, "SUPPORT_E4M3", 1):
        dut._log.info("Skipping E4M3 compliance test")
        return

    # 1. Zero check
    await run_mac_test(dut, 0, 0, [0x00]*32, [0x38]*32, expected_override=0)
    await run_mac_test(dut, 0, 0, [0x80]*32, [0x38]*32, expected_override=0)

    # 2. Max Normal (448) * 1.0 (0x38) = 448
    # 32 * 448 * 256 = 3670016
    await run_mac_test(dut, 0, 0, [0x7E]*32, [0x38]*32, expected_override=3670016)

    # 3. Min Normal (2^-6) * 1.0 = 2^-6 = 0.015625
    # 32 * 0.015625 * 256 = 32 * 4 = 128
    await run_mac_test(dut, 0, 0, [0x08]*32, [0x38]*32, expected_override=128)

    # 4. Min Subnormal (2^-9) * 1.125 (0x39) = 1.125 * 2^-9
    # In S23.16 (ALIGNER_WIDTH=40): 1.125 * 2^-9 * 2^16 = 144 -> >> 8 = 0
    # In S23.8 (ALIGNER_WIDTH=32): 1.125 * 2^-9 * 2^8 = 0.5625 -> rounds to 1 * 32 = 32
    aligner_w = get_param(dut, "ALIGNER_WIDTH", 40)
    exp_sub = 18 if aligner_w == 40 else 32
    await run_mac_test(dut, 0, 0, [0x01]*32, [0x39]*32, round_mode=3, expected_override=exp_sub)

    # 5. NaN propagation (0x7F is NaN in E4M3)
    # Fixed-point sentinel: 0x80000000 (-2147483648), Float32: 0x7FC00000
    await run_mac_test(dut, 0, 0, [0x7F]*32, [0x38]*32, expected_override=-2147483648)
    if get_param(dut, "SUPPORT_FLOAT32", 1):
        await run_mac_test(dut, 0, 0, [0x7F]*32, [0x38]*32, float32_mode=1, expected_override=0x7FC00000)

@cocotb.test()
async def test_ofp8_e5m2_compliance(dut):
    """Compliance test for OCP-OFP8 E5M2 format"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    if not get_param(dut, "SUPPORT_E5M2", 1):
        dut._log.info("Skipping E5M2 compliance test")
        return

    # 1. Infinity propagation
    # +Inf * 1.0 = +Inf (Fixed-point: 0x7FFFFFFF, Float32: 0x7F800000)
    await run_mac_test(dut, 1, 1, [0x7C]*32, [0x3C]*32, expected_override=0x7FFFFFFF)
    if get_param(dut, "SUPPORT_FLOAT32", 1):
        await run_mac_test(dut, 1, 1, [0x7C]*32, [0x3C]*32, float32_mode=1, expected_override=0x7F800000)

    # 2. NaN propagation (Check all 3 NaN patterns: 0x7D, 0x7E, 0x7F)
    for nan_val in [0x7D, 0x7E, 0x7F]:
        await run_mac_test(dut, 1, 1, [nan_val]*32, [0x3C]*32, expected_override=-2147483648)

    # 3. Inf * 0 = NaN
    await run_mac_test(dut, 1, 1, [0x7C]*32, [0x00]*32, expected_override=-2147483648)

    # 4. Max Normal (57344) * 1.0 (0x3C) = 57344
    # 32 * 57344 * 256 = 469762048
    await run_mac_test(dut, 1, 1, [0x7B]*32, [0x3C]*32, expected_override=469762048)

    # 5. Representable Subnormal
    # E5M2 0x2C is 2^-4. 2^-4 * 2^-4 = 2^-8.
    # 2^-8 * 256 = 1.0.
    # 32 * 1.0 = 32.
    # Scale A = 130 (2^3). 32 * 2^3 = 256.
    await run_mac_test(dut, 1, 1, [0x2C]*32, [0x2C]*32, scale_a=130, expected_override=256)

@cocotb.test()
async def test_ofp8_rounding_compliance(dut):
    """Verify roundTiesToEven requirement"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    aligner_w = get_param(dut, "ALIGNER_WIDTH", 40)

    # E4M3: 0x01 * 0x38 = 2^-9.
    # In S23.16 (ALIGNER_WIDTH=40): 2^-9 * 2^16 = 128 -> 32 * 128 = 4096 -> >> 8 = 16
    # In S23.8 (ALIGNER_WIDTH=32): 2^-9 * 2^8 = 0.5 -> ties to even 0
    exp_half = 16 if aligner_w == 40 else 0
    await run_mac_test(dut, 0, 0, [0x01]*32, [0x38]*32, round_mode=3, expected_override=exp_half)

    # E4M3: 0x03 * 0x38 = 3 * 2^-9.
    # In S23.16 (ALIGNER_WIDTH=40): 3 * 128 = 384 -> 32 * 384 = 12288 -> >> 8 = 48
    # In S23.8 (ALIGNER_WIDTH=32): 1.5 -> ties to even 2 * 32 = 64
    exp_3half = 48 if aligner_w == 40 else 64
    await run_mac_test(dut, 0, 0, [0x03]*32, [0x38]*32, round_mode=3, expected_override=exp_3half)

@cocotb.test()
async def test_ofp8_signed_zeros(dut):
    """Compliance test for OCP-OFP8 signed zeros"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # +0 * +1 = +0
    await run_mac_test(dut, 0, 0, [0x00]*32, [0x38]*32, expected_override=0)
    # -0 * +1 = -0
    await run_mac_test(dut, 0, 0, [0x80]*32, [0x38]*32, expected_override=0)
    # -1 * -1 = +1
    await run_mac_test(dut, 0, 0, [0xB8]*32, [0xB8]*32, expected_override=8192)
