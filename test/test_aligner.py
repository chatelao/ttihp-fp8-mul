import cocotb
from cocotb.triggers import Timer
import random

def align_reference(prod, exp_sum, sign):
    # exp_sum is signed 7-bit
    if exp_sum >= 64:
        exp_sum -= 128

    val = (prod / 64.0) * (2.0 ** (exp_sum - 7))
    if sign:
        val = -val

    # Fixed point representation (bit 8 = 2^0)
    # This means value * 2^8
    # We use integer arithmetic to match Verilog

    shift_amt = exp_sum - 5
    shifted = prod
    if shift_amt >= 0:
        shifted = prod << shift_amt
    else:
        shifted = prod >> (-shift_amt)

    # Keep 32 bits
    mask = 0xFFFFFFFF
    if sign:
        res = (-shifted) & mask
    else:
        res = shifted & mask

    return res

@cocotb.test()
async def test_aligner_basic(dut):
    test_cases = [
        # prod, exp_sum, sign, label
        (64, 7, 0, "1.0 * 1.0 = 1.0"),
        (64, 7, 1, "-1.0 * 1.0 = -1.0"),
        (64, 13, 0, "1.0 * 2^6 = 64.0"),
        (225, 21, 0, "max * max = 57600.0"),
        (1, -5, 0, "subnormal * subnormal"),
    ]

    for prod, exp_sum, sign, label in test_cases:
        dut.prod.value = prod
        dut.exp_sum.value = exp_sum
        dut.sign.value = sign
        await Timer(1, units="ns")

        expected = align_reference(prod, exp_sum, sign)
        actual = int(dut.aligned.value)

        dut._log.info(f"{label}: Input (prod={prod}, exp_sum={exp_sum}, sign={sign}) -> Actual: 0x{actual:08x}, Expected: 0x{expected:08x}")
        assert actual == expected

@cocotb.test()
async def test_aligner_random(dut):
    for i in range(100):
        prod = random.randint(0, 255)
        exp_sum = random.randint(-64, 63)
        sign = random.randint(0, 1)

        dut.prod.value = prod
        dut.exp_sum.value = exp_sum
        dut.sign.value = sign
        await Timer(1, units="ns")

        expected = align_reference(prod, exp_sum, sign)
        actual = int(dut.aligned.value)

        if actual != expected:
             dut._log.error(f"FAIL: Input (prod={prod}, exp_sum={exp_sum}, sign={sign}) -> Actual: 0x{actual:08x}, Expected: 0x{expected:08x}")
        assert actual == expected
