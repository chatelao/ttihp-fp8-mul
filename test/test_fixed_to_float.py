import cocotb
from cocotb.triggers import Timer
import struct

def float_to_bits(f):
    return struct.unpack('>I', struct.pack('>f', f))[0]

@cocotb.test()
async def test_f2f_basic(dut):
    """Test Fixed-to-Float normalization and exponent estimation"""

    # Initial sticky flags to 0
    dut.nan_sticky.value = 0
    dut.inf_pos_sticky.value = 0
    dut.inf_neg_sticky.value = 0

    test_cases = [
        # (acc, shared_exp, expected_sign, expected_lzc, expected_exp_biased, expected_zero, expected_underflow, expected_mantissa, expected_result)

        # 1.0 in S23.16 (1 << 16)
        (1 << 16, 0, 0, 23, 127, 0, 0, 0, 0x3f800000),

        # -1.0 in S23.16
        (-(1 << 16), 0, 1, 23, 127, 0, 0, 0, 0xbf800000),

        # 1.5 in S23.16 (1.5 * 2^16 = 3 * 2^15)
        (3 << 15, 0, 0, 23, 127, 0, 0, 1 << 22, 0x3fc00000),

        # Max positive (approx 2^23). acc is 40 bits signed.
        # ((1 << 39) - 1, 0) -> exp_biased=149, norm_mag[39:16]=0xFFFFFF.
        # Round up -> Carry out -> exp=150.
        ((1 << 39) - 1, 0, 0, 1, 149, 0, 0, 0, 0x4b000000),

        # Max negative magnitude (-2^39).
        (-(1 << 39), 0, 1, 0, 150, 0, 0, 0, 0xcb000000),

        # Smallest positive fractional (1 in bit 0)
        (1, 0, 0, 39, 111, 0, 0, 0, 0x37800000),

        # Zero
        (0, 0, 0, 40, 110, 1, 1, 0, 0x00000000),

        # Shared scaling: 1.0 * 2^10
        (1 << 16, 10, 0, 23, 137, 0, 0, 0, 0x44800000),

        # Shared scaling: 1.0 * 2^-10
        (1 << 16, -10, 0, 23, 117, 0, 0, 0, 0x3a800000),

        # Extreme underflow: (1 << 0) * 2^-150
        (1, -150, 0, 39, -39, 0, 1, 0, 0x00000000),

        # --- Subnormal cases ---
        # Case: shared_exp = -127, acc = 1 << 16 (1.0) -> 2^-127
        # 1.0 * 2^-127 = 0.5 * 2^-126. Biased Exp = 0.
        (1 << 16, -127, 0, 23, 0, 0, 1, 1 << 22, 0x00400000),

        # Case: shared_exp = -127, acc = 1 << 15 (0.5) -> 2^-128
        # 0.5 * 2^-127 = 0.25 * 2^-126.
        (1 << 15, -127, 0, 24, -1, 0, 1, 1 << 21, 0x00200000),
    ]

    for acc, shared_exp, exp_sign, exp_lzc, exp_exp_biased, exp_zero, exp_underflow, exp_mantissa, exp_result in test_cases:
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
        actual_result = int(dut.result.value)

        dut._log.info(f"Input: acc=0x{acc & 0xFFFFFFFFFF:010x}, shared_exp={shared_exp}")
        dut._log.info(f"Expected: sign={exp_sign}, lzc={exp_lzc}, exp_biased={exp_exp_biased}, zero={exp_zero}, underflow={exp_underflow}, mantissa=0x{exp_mantissa:06x}, result=0x{exp_result:08x}")
        dut._log.info(f"Actual:   sign={actual_sign}, lzc={actual_lzc}, exp_biased={actual_exp_biased}, zero={actual_zero}, underflow={actual_underflow}, mantissa=0x{actual_mantissa:06x}, result=0x{actual_result:08x}")

        assert actual_sign == exp_sign
        assert actual_lzc == exp_lzc
        assert actual_exp_biased == exp_exp_biased
        assert actual_zero == exp_zero
        assert actual_underflow == exp_underflow
        assert actual_mantissa == exp_mantissa
        assert actual_result == exp_result

@cocotb.test()
async def test_f2f_rounding(dut):
    """Verify Round-to-Nearest-Even (RNE) logic"""

    dut.nan_sticky.value = 0
    dut.inf_pos_sticky.value = 0
    dut.inf_neg_sticky.value = 0
    dut.shared_exp.value = 0

    rounding_cases = [
        # (acc, expected_result_hex)

        # 1.0 (Exact)
        (1 << 16, 0x3f800000),

        # 1.0 + 2^-8 in mantissa
        ((1 << 16) + (1 << 8), 0x3f808000),

        # 1. acc = 1<<30 (Exact)
        (1 << 30, 0x46800000),

        # 2. acc = (1<<30) + (1<<6) -> G=1, L=0, R=0, S=0. Halfway, round to even (down).
        ((1 << 30) + (1 << 6), 0x46800000),

        # 3. acc = (1<<30) + (1<<7) + (1<<6) -> G=1, L=1, R=0, S=0. Halfway, round to even (up).
        ((1 << 30) + (1 << 7) + (1 << 6), 0x46800002),

        # 4. acc = (1<<30) + (1<<6) + (1<<5) -> G=1, R=1, S=0. Above halfway, round up.
        ((1 << 30) + (1 << 6) + (1 << 5), 0x46800001),

        # 5. Carry out from mantissa: 1.11...1 (23 ones) + round up -> 10.00...0
        # acc = 0x7fffffc0. lzc=9. exp=141. norm_mag[39:16]=0xffffff. L=1, G=1.
        # Rounded = 0x1000000. Carry out. exp=142.
        (0x7fffffc0, 0x47000000),
    ]

    for acc, exp_res in rounding_cases:
        dut.acc.value = acc
        await Timer(1, unit="ns")
        actual_res = int(dut.result.value)
        dut._log.info(f"Rounding: acc=0x{acc:x}, exp=0x{exp_res:08x}, act=0x{actual_res:08x}")
        assert actual_res == exp_res

@cocotb.test()
async def test_f2f_special_values(dut):
    """Verify NaN and Infinity propagation"""

    # Helper to set all inputs
    def set_inputs(acc=0, shared_exp=0, nan=0, pinf=0, ninf=0):
        dut.acc.value = acc
        dut.shared_exp.value = shared_exp
        dut.nan_sticky.value = nan
        dut.inf_pos_sticky.value = pinf
        dut.inf_neg_sticky.value = ninf

    # 1. NaN sticky
    set_inputs(nan=1)
    await Timer(1, unit="ns")
    assert int(dut.result.value) == 0x7FC00000

    # 2. Both Infinities -> NaN
    set_inputs(pinf=1, ninf=1)
    await Timer(1, unit="ns")
    assert int(dut.result.value) == 0x7FC00000

    # 3. Positive Infinity
    set_inputs(pinf=1)
    await Timer(1, unit="ns")
    assert int(dut.result.value) == 0x7F800000

    # 4. Negative Infinity
    set_inputs(ninf=1)
    await Timer(1, unit="ns")
    assert int(dut.result.value) == 0xFF800000

    # 5. Overflow to Infinity (Positive)
    set_inputs(acc=0x7FFFFFFFFF, shared_exp=120)
    await Timer(1, unit="ns")
    assert int(dut.result.value) == 0x7F800000

    # 6. Overflow to Infinity (Negative)
    set_inputs(acc=1 << 39, shared_exp=120)
    await Timer(1, unit="ns")
    assert int(dut.result.value) == 0xFF800000
