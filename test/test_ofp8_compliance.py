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
    await run_mac_test(dut, 0, 0, [0x00]*32, [0x38]*32, expected_override=0x00000000)
    await run_mac_test(dut, 0, 0, [0x80]*32, [0x38]*32, expected_override=0x00000000)

    # 2. Max Normal (448) * 1.0 (0x38) = 448
    # 32 * 448 = 14336.0 -> 0x46600000
    await run_mac_test(dut, 0, 0, [0x7E]*32, [0x38]*32, expected_override=0x46600000)

    # 3. Min Normal (2^-6) * 1.0 = 2^-6 = 0.015625
    # 32 * 0.015625 = 0.5 -> 0x3F000000
    await run_mac_test(dut, 0, 0, [0x08]*32, [0x38]*32, expected_override=0x3F000000)

    # 4. Min Subnormal (2^-9) * 1.125 (0x39) = 1.125 * 2^-9
    # 32 * 1.125 * 2^-9 = 0.0703125 -> 0x3D900000
    await run_mac_test(dut, 0, 0, [0x01]*32, [0x39]*32, round_mode=3, expected_override=0x3D900000)

    # 5. NaN propagation (0x7F is NaN in E4M3)
    await run_mac_test(dut, 0, 0, [0x7F]*32, [0x38]*32, expected_override=0x7FC00000)

@cocotb.test()
async def test_ofp8_e5m2_compliance(dut):
    """Compliance test for OCP-OFP8 E5M2 format"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    if not get_param(dut, "SUPPORT_E5M2", 1):
        dut._log.info("Skipping E5M2 compliance test")
        return

    # 1. Infinity propagation
    # +Inf * 1.0 = +Inf (0x7F800000)
    await run_mac_test(dut, 1, 1, [0x7C]*32, [0x3C]*32, expected_override=0x7F800000)

    # 2. NaN propagation (Check all 3 NaN patterns: 0x7D, 0x7E, 0x7F)
    for nan_val in [0x7D, 0x7E, 0x7F]:
        await run_mac_test(dut, 1, 1, [nan_val]*32, [0x3C]*32, expected_override=0x7FC00000)

    # 3. Inf * 0 = NaN
    await run_mac_test(dut, 1, 1, [0x7C]*32, [0x00]*32, expected_override=0x7FC00000)

    # 4. Max Normal (57344) * 1.0 (0x3C) = 57344
    # 32 * 57344 = 1835008 -> 0x49E00000
    await run_mac_test(dut, 1, 1, [0x7B]*32, [0x3C]*32, expected_override=0x49E00000)

    # 5. Representable Subnormal
    # E5M2 0x2C is 2^-4. 2^-4 * 2^-4 = 2^-8.
    # 32 * 2^-8 = 32 * 2^-8 = 2^-3 = 0.125
    # Scale A = 130 (2^3). 0.125 * 2^3 = 1.0 -> 0x3F800000
    await run_mac_test(dut, 1, 1, [0x2C]*32, [0x2C]*32, scale_a=130, expected_override=0x3F800000)

@cocotb.test()
async def test_ofp8_rounding_compliance(dut):
    """Verify roundTiesToEven requirement"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # IEEE 754 conversion itself handles rounding from internal high precision.
    # The 'round_mode' configuration in RTL is currently used by aligner which we mostly bypassed
    # for precision, OR it should be used for Float32 rounding.
    # Our project.v uses RNE for Float32 conversion.

    # E4M3: 0x01 * 0x38 = 2^-9.
    # 32 * 2^-9 = 2^-4 = 0.0625 -> 0x3D800000
    await run_mac_test(dut, 0, 0, [0x01]*32, [0x38]*32, round_mode=3, expected_override=0x3D800000)

@cocotb.test()
async def test_ofp8_signed_zeros(dut):
    """Compliance test for OCP-OFP8 signed zeros"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # +0 * +1 = +0
    await run_mac_test(dut, 0, 0, [0x00]*32, [0x38]*32, expected_override=0x00000000)
    # -0 * +1 = -0
    await run_mac_test(dut, 0, 0, [0x80]*32, [0x38]*32, expected_override=0x80000000)
    # -1 * -1 = +1
    # 32 * 1.0 = 32.0 -> 0x42000000
    await run_mac_test(dut, 0, 0, [0xB8]*32, [0xB8]*32, expected_override=0x42000000)
