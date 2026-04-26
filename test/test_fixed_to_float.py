import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def test_f2f_basic(dut):
    """Test Fixed-to-Float normalization and exponent estimation"""

    test_cases = [
        # (acc, shared_exp, expected_sign, expected_lzc, expected_exp_biased, expected_zero, expected_underflow)

        # 1.0 in S23.16 (1 << 16)
        (1 << 16, 0, 0, 23, 127, 0, 0),

        # -1.0 in S23.16
        (-(1 << 16), 0, 1, 23, 127, 0, 0),

        # Max positive (approx 2^22)
        ((1 << 39) - 1, 0, 0, 1, 149, 0, 0),

        # Max negative magnitude (-2^39)
        (-(1 << 39), 0, 1, 0, 150, 0, 0),

        # Smallest positive fractional (1 in bit 0)
        (1, 0, 0, 39, 150 - 39, 0, 0),

        # Zero
        (0, 0, 0, 40, 150 - 40, 1, 1),

        # Shared scaling: 1.0 * 2^10
        (1 << 16, 10, 0, 23, 137, 0, 0),

        # Shared scaling: 1.0 * 2^-10
        (1 << 16, -10, 0, 23, 117, 0, 0),

        # Extreme underflow: (1 << 0) * 2^-150
        (1, -150, 0, 39, 150 - 39 - 150, 0, 1),
    ]

    for acc, shared_exp, exp_sign, exp_lzc, exp_exp_biased, exp_zero, exp_underflow in test_cases:
        # Handle 40-bit signed for Cocotb
        if acc < 0:
            if acc == -(1 << 39):
                dut.acc.value = 1 << 39
            else:
                dut.acc.value = (1 << 40) + acc
        else:
            dut.acc.value = acc

        dut.shared_exp.value = shared_exp

        await Timer(1, unit="ns")

        actual_sign = int(dut.sign.value)
        actual_lzc = int(dut.lzc.value)
        actual_exp_biased = int(dut.exp_biased.value)
        # Handle 12-bit signed
        if actual_exp_biased >= 2048:
            actual_exp_biased -= 4096

        actual_zero = int(dut.zero.value)
        actual_underflow = int(dut.underflow.value)

        dut._log.info(f"Input: acc=0x{acc & 0xFFFFFFFFFF:010x}, shared_exp={shared_exp}")
        dut._log.info(f"Expected: sign={exp_sign}, lzc={exp_lzc}, exp_biased={exp_exp_biased}, zero={exp_zero}, underflow={exp_underflow}")
        dut._log.info(f"Actual:   sign={actual_sign}, lzc={actual_lzc}, exp_biased={actual_exp_biased}, zero={actual_zero}, underflow={actual_underflow}")

        assert actual_sign == exp_sign
        assert actual_lzc == exp_lzc
        assert actual_exp_biased == exp_exp_biased
        assert actual_zero == exp_zero
        assert actual_underflow == exp_underflow

@cocotb.test()
async def test_f2f_normalization(dut):
    """Verify that norm_mag is correctly left-justified"""
    import random

    for _ in range(100):
        acc = random.getrandbits(39) # positive
        if acc == 0: continue

        dut.acc.value = acc
        dut.shared_exp.value = 0

        await Timer(1, unit="ns")

        norm_mag = int(dut.norm_mag.value)
        # For non-zero values, the MSB (bit 39) of norm_mag must be 1
        assert (norm_mag & (1 << 39)) != 0

        # Also verify it's a correct shift
        lzc = int(dut.lzc.value)
        assert norm_mag == (acc << lzc) & ((1 << 40) - 1)
