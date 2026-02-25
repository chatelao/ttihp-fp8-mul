# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
import math

"""
IEEE 754 Reference Model for FP8 (E4M3)
- Clause 3.2: Format consists of 1 sign bit, 4 exponent bits (bias 7), 3 mantissa bits.
- Clause 3.3: Exponent 0 indicates subnormal numbers (if mantissa != 0) or zero.
- Clause 4.3.1: Round-to-nearest-even (RNE) is used as the default rounding mode.
- Clause 7.2: 0 * Infinity = NaN.
"""

def float8_to_val(bits):
    s = (bits >> 7) & 1
    e = (bits >> 3) & 0xF
    m = bits & 0x7
    sign = -1 if s else 1
    if e == 0:
        if m == 0:
            return 0.0 * sign
        else:
            # Subnormal: 0.mmm * 2^(1-7)
            return sign * (m / 8.0) * (2 ** -6)
    elif e == 15:
        if m == 0:
            return float('inf') * sign
        else:
            return float('nan')
    else:
        # Normal: 1.mmm * 2^(e-7)
        return sign * (1 + m / 8.0) * (2 ** (e - 7))

def val_to_float8_rne(val):
    if math.isnan(val):
        return 0x7F # canonical NaN

    sign_bit = 0x80 if math.copysign(1.0, val) < 0 else 0
    abs_val = abs(val)

    if abs_val == 0:
        return sign_bit

    # IEEE 754-2008 Clause 4.3: Overflow to Infinity threshold
    # Max finite value: (1 + 7/8.0) * (2 ** 7) = 240.0
    # Next representable value (if exp=15 was finite): 256.0
    # Midpoint for rounding to infinity: 248.0
    max_finite = 240.0
    if abs_val >= 248.0:
        return sign_bit | 0x78 # Infinity

    # Check for subnormal range (Clause 6.3)
    smallest_normal = 2 ** -6
    if abs_val < smallest_normal:
        # Subnormal
        m_scaled = abs_val * (2 ** 9)
        m_int = int(math.floor(m_scaled))
        rem = m_scaled - m_int
        # Clause 4.3.1: RNE
        if rem > 0.5 or (rem == 0.5 and (m_int % 2 == 1)):
            m_int += 1

        if m_int >= 8:
            return sign_bit | (1 << 3) | 0 # Round up to smallest normal
        return sign_bit | m_int
    else:
        # Normal
        exp = int(math.floor(math.log2(abs_val)))
        if exp > 7: exp = 7

        e = exp + 7
        m_scaled = (abs_val / (2**exp) - 1.0) * 8
        m_int = int(math.floor(m_scaled))
        rem = m_scaled - m_int
        # Clause 4.3.1: RNE
        if rem > 0.5 or (rem == 0.5 and (m_int % 2 == 1)):
            m_int += 1

        if m_int >= 8:
            m_int = 0
            e += 1

        if e >= 15:
            return sign_bit | 0x78 # Infinity

        return sign_bit | (e << 3) | m_int

def fp8_mul_reference(a, b):
    va = float8_to_val(a)
    vb = float8_to_val(b)

    if math.isnan(va) or math.isnan(vb):
        return 0x7F # Simple NaN

    # IEEE 754-2008 Clause 7.2: 0 * Inf = NaN
    if (va == 0 and math.isinf(vb)) or (math.isinf(va) and vb == 0):
        return 0x7F # NaN

    res = va * vb
    return val_to_float8_rne(res)

@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    dut._log.info("Test project behavior")

    # IEEE 754 Test cases
    test_cases = [
        (0x40, 0x40, 0x48), # 2.0 * 2.0 = 4.0
        (0x38, 0x38, 0x38), # 1.0 * 1.0 = 1.0
        (0x40, 0x38, 0x40), # 2.0 * 1.0 = 2.0
        (0x00, 0x40, 0x00), # 0.0 * 2.0 = 0.0
        (0x80, 0x40, 0x80), # -0.0 * 2.0 = -0.0
        (0x7F, 0x38, 0x7F), # NaN * 1.0 = NaN
        (0x00, 0x78, 0x7F), # 0 * Inf = NaN (Clause 7.2)
        (0x78, 0x38, 0x78), # Inf * 1.0 = Inf
    ]

    for a, b, expected in test_cases:
        dut.ui_in.value = a
        dut.uio_in.value = b
        await ClockCycles(dut.clk, 1)
        actual = int(dut.uo_out.value)
        # Normalize NaN for comparison
        if (actual & 0x7F) == 0x7F and (expected & 0x7F) == 0x7F:
            pass
        else:
            dut._log.info(f"Input: A=0x{a:02x}, B=0x{b:02x} | Output: 0x{actual:02x} | Expected: 0x{expected:02x}")
            assert actual == expected

    dut._log.info("All manual tests passed!")

@cocotb.test()
async def test_all_combinations(dut):
    dut._log.info("Start all combinations test")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    failures = 0
    for a in range(256):
        if a % 32 == 0:
            dut._log.info(f"Testing A = {a}/255")
        for b in range(256):
            dut.ui_in.value = a
            dut.uio_in.value = b
            await ClockCycles(dut.clk, 1)
            expected = fp8_mul_reference(a, b)
            actual = int(dut.uo_out.value)

            # Normalize NaN
            if (actual & 0x7F) == 0x7F and (expected & 0x7F) == 0x7F:
                continue

            if actual != expected:
                 if failures < 10:
                     dut._log.error(f"FAIL: Input: A=0x{a:02x}, B=0x{b:02x} | Output: 0x{actual:02x} | Expected: 0x{expected:02x}")
                 failures += 1

    if failures > 0:
        dut._log.error(f"Total failures: {failures}")
        assert failures == 0
    else:
        dut._log.info("All 65536 combinations passed!")
