import cocotb
from cocotb.triggers import Timer
import random

# Reuse model from test.py
from test import align_model

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
        dut.round_mode.value = 0
        dut.overflow_wrap.value = 0
        await Timer(1, unit="ns")

        expected_val = align_model(prod, exp_sum, sign, round_mode=0, overflow_wrap=0, width=80)
        expected = expected_val & ((1 << 80) - 1)
        actual = int(dut.aligned.value)

        dut._log.info(f"{label}: Input (prod={prod}, exp_sum={exp_sum}, sign={sign}) -> Actual: 0x{actual:020x}, Expected: 0x{expected:020x}")
        assert actual == expected

@cocotb.test()
async def test_aligner_random(dut):
    for i in range(100):
        prod = random.randint(0, 0xFFFFFFFF)
        exp_sum = random.randint(-127, 127)
        sign = random.randint(0, 1)
        rm = random.randint(0, 3)
        ov = random.randint(0, 1)

        dut.prod.value = prod
        dut.exp_sum.value = exp_sum
        dut.sign.value = sign
        dut.round_mode.value = rm
        dut.overflow_wrap.value = ov
        await Timer(1, unit="ns")

        expected_val = align_model(prod, exp_sum, sign, round_mode=rm, overflow_wrap=ov, width=80)
        expected = expected_val & ((1 << 80) - 1)
        actual = int(dut.aligned.value)

        if actual != expected:
             dut._log.error(f"FAIL: Input (prod={prod}, exp_sum={exp_sum}, sign={sign}, rm={rm}, ov={ov}) -> Actual: 0x{actual:020x}, Expected: 0x{expected:020x}")
        assert actual == expected
