import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def test_f2f_basic(dut):
    """Test Fixed-to-Float normalization and exponent estimation"""

    test_cases = [
        # (acc, shared_exp, expected_sign, expected_lzc, expected_exp_biased, expected_zero, expected_underflow, expected_mantissa)

        # 1.0 in S23.16 (1 << 16)
        (1 << 16, 0, 0, 23, 127, 0, 0, 0),

        # -1.0 in S23.16
        (-(1 << 16), 0, 1, 23, 127, 0, 0, 0),

        # 1.5 in S23.16 (1.5 * 2^16 = 3 * 2^15)
        (3 << 15, 0, 0, 23, 127, 0, 0, 1 << 22),

        # Max positive (approx 2^23)
        ((1 << 39) - 1, 0, 0, 1, 149, 0, 0, 0x7FFFFF),

        # Max negative magnitude (-2^39)
        (-(1 << 39), 0, 1, 0, 150, 0, 0, 0),

        # Smallest positive fractional (1 in bit 0)
        (1, 0, 0, 39, 150 - 39, 0, 0, 0),

        # Zero
        (0, 0, 0, 40, 150 - 40, 1, 1, 0),

        # Shared scaling: 1.0 * 2^10
        (1 << 16, 10, 0, 23, 137, 0, 0, 0),

        # Shared scaling: 1.0 * 2^-10
        (1 << 16, -10, 0, 23, 117, 0, 0, 0),

        # Extreme underflow: (1 << 0) * 2^-150
        (1, -150, 0, 39, 150 - 39 - 150, 0, 1, 0),

        # --- Subnormal cases ---
        # Smallest normal is 2^-126.
        # Biased exp = 150 + shared_exp - LZC.
        # To get subnormal, we want 150 + shared_exp - LZC <= 0.

        # Case: shared_exp = -150, acc = 1 << 16 (1.0)
        # exp_biased = 150 - 150 - 23 = -23 (Underflow)
        # Shift = 149 + (-150) = -1.
        # norm_mag = (1 << 16) >> 1 = 1 << 15.
        # mantissa = norm_mag[38:16] = 0.
        (1 << 16, -150, 0, 23, -23, 0, 1, 0),

        # Case: shared_exp = -127, acc = 1 << 16 (1.0)
        # exp_biased = 150 - 127 - 23 = 0 (Underflow, exactly subnormal boundary)
        # Shift = 149 - 127 = 22.
        # norm_mag = (1 << 16) << 22 = 1 << 38.
        # mantissa = norm_mag[38:16] = 1 << 22 (0.5 in mantissa for exp_biased=0)
        # Wait, if exp_biased=0, it's 2^-126 * 0.mantissa.
        # 1.0 * 2^-127 = 0.5 * 2^-126. Correct.
        (1 << 16, -127, 0, 23, 0, 0, 1, 1 << 22),

        # Case: shared_exp = -127, acc = 1 << 15 (0.5)
        # exp_biased = 150 - 127 - 24 = -1
        # Shift = 149 - 127 = 22.
        # norm_mag = (1 << 15) << 22 = 1 << 37.
        # mantissa = norm_mag[38:16] = 1 << 21. (0.25 in mantissa)
        # 0.5 * 2^-127 = 0.25 * 2^-126. Correct.
        (1 << 15, -127, 0, 24, -1, 0, 1, 1 << 21),
    ]

    for acc, shared_exp, exp_sign, exp_lzc, exp_exp_biased, exp_zero, exp_underflow, exp_mantissa in test_cases:
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
        actual_mantissa = int(dut.mantissa.value)

        dut._log.info(f"Input: acc=0x{acc & 0xFFFFFFFFFF:010x}, shared_exp={shared_exp}")
        dut._log.info(f"Expected: sign={exp_sign}, lzc={exp_lzc}, exp_biased={exp_exp_biased}, zero={exp_zero}, underflow={exp_underflow}, mantissa=0x{exp_mantissa:06x}")
        dut._log.info(f"Actual:   sign={actual_sign}, lzc={actual_lzc}, exp_biased={actual_exp_biased}, zero={actual_zero}, underflow={actual_underflow}, mantissa=0x{actual_mantissa:06x}")

        assert actual_sign == exp_sign
        assert actual_lzc == exp_lzc
        assert actual_exp_biased == exp_exp_biased
        assert actual_zero == exp_zero
        assert actual_underflow == exp_underflow
        assert actual_mantissa == exp_mantissa

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
