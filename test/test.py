# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

def fp8_mul_reference(a, b):
    # a, b are 8-bit integers representing FP8 E4M3
    sign1 = (a >> 7) & 1
    exp1 = (a >> 3) & 0xF
    mant1 = a & 0x7

    sign2 = (b >> 7) & 1
    exp2 = (b >> 3) & 0xF
    mant2 = b & 0x7

    isnan1 = (exp1 == 15 and mant1 != 0)
    isnan2 = (exp2 == 15 and mant2 != 0)
    isnan = isnan1 or isnan2

    # Mantissa multiplication including implicit leading bit (1.xxx), if Exp != 0
    # wire [7:0] full_mant = ({exp1 != 4'b0, mant1} * {exp2 != 4'b0, mant2});
    m1 = ((1 << 3) | mant1) if exp1 != 0 else mant1
    m2 = ((1 << 3) | mant2) if exp2 != 0 else mant2
    full_mant = (m1 * m2) & 0xFF

    # wire overflow_mant = full_mant[7];
    overflow_mant = (full_mant >> 7) & 1

    # wire [6:0] shifted_mant = overflow_mant ? full_mant[6:0] : {full_mant[5:0], 1'b0};
    if overflow_mant:
        shifted_mant = full_mant & 0x7F
    else:
        shifted_mant = (full_mant << 1) & 0x7F

    # wire [4:0] exp_sum = {1'b0, exp1} + {1'b0, exp2} + {4'b0, overflow_mant};
    exp_sum = exp1 + exp2 + overflow_mant

    # wire roundup = (exp_sum < {1'b0, 4'd1 + EXP_BIAS[3:0]}) && (shifted_mant[6:0] != 7'b0)
    #                || (shifted_mant[6:4] == 3'b111 && shifted_mant[3]);
    roundup = (exp_sum < 8 and shifted_mant != 0) or \
              (((shifted_mant >> 4) & 0x7) == 7 and ((shifted_mant >> 3) & 1))

    # wire underflow = exp_sum < ({1'b0, 4'd1 + EXP_BIAS[3:0]} - {4'b0, roundup});
    underflow = exp_sum < (8 - (1 if roundup else 0))

    # wire is_zero = exp1 == 4'b0 || exp2 == 4'b0 || underflow;
    is_zero = (exp1 == 0 or exp2 == 0 or underflow)

    # wire [4:0] exp_out_tmp = ((exp_sum + {4'b0, roundup}) < {1'b0, EXP_BIAS[3:0]}) ? 5'b0 : (exp_sum + {4'b0, roundup} - {1'b0, EXP_BIAS[3:0]});
    exp_sum_with_roundup = exp_sum + (1 if roundup else 0)
    if exp_sum_with_roundup < 7:
        exp_out_tmp = 0
    else:
        exp_out_tmp = exp_sum_with_roundup - 7

    # assign exp_out = isnan ? 4'b1111 : (exp_out_tmp > 5'd15 ? 4'b1111 : (is_zero) ? 4'b0000 : exp_out_tmp[3:0]);
    if isnan:
        exp_out = 15
    elif exp_out_tmp > 15:
        exp_out = 15
    elif is_zero:
        exp_out = 0
    else:
        exp_out = exp_out_tmp & 0xF

    # assign mant_out = isnan ? 3'b111 : (exp_out_tmp > 5'd15 ? 3'b111 : (is_zero || roundup) ? 3'b000 : (shifted_mant[6:4] + {2'b0, (shifted_mant[3:0] > 4'd8 || (shifted_mant[3:0] == 4'd8 && shifted_mant[4]))}));
    if isnan:
        mant_out = 7
    elif exp_out_tmp > 15:
        mant_out = 7
    elif is_zero or roundup:
        mant_out = 0
    else:
        m_hi = (shifted_mant >> 4) & 0x7
        m_lo = shifted_mant & 0xF
        inc = 1 if (m_lo > 8 or (m_lo == 8 and (m_hi & 1))) else 0
        mant_out = (m_hi + inc) & 0x7

    # assign sign_out = isnan ? (isnan1 ? sign1 : sign2) : (sign1 ^ sign2);
    if isnan:
        sign_out = sign1 if isnan1 else sign2
    else:
        sign_out = sign1 ^ sign2

    return (sign_out << 7) | (exp_out << 3) | mant_out

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

    # Test cases: (A, B, Expected)
    test_cases = [
        (0x40, 0x40, 0x48), # 2.0 * 2.0 = 4.0
        (0x38, 0x38, 0x38), # 1.0 * 1.0 = 1.0
        (0x40, 0x38, 0x40), # 2.0 * 1.0 = 2.0
        (0x00, 0x40, 0x00), # 0.0 * 2.0 = 0.0
        (0x80, 0x40, 0x80), # -0.0 * 2.0 = -0.0
        (0x7F, 0x38, 0x7F), # NaN * 1.0 = NaN
    ]

    for a, b, expected in test_cases:
        dut.ui_in.value = a
        dut.uio_in.value = b
        await ClockCycles(dut.clk, 1)
        dut._log.info(f"Input: A=0x{a:02x}, B=0x{b:02x} | Output: 0x{int(dut.uo_out.value):02x} | Expected: 0x{expected:02x}")
        assert int(dut.uo_out.value) == expected

    dut._log.info("All tests passed!")

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

    for a in range(256):
        if a % 32 == 0:
            dut._log.info(f"Testing A = {a}/255")
        for b in range(256):
            dut.ui_in.value = a
            dut.uio_in.value = b
            await ClockCycles(dut.clk, 1)
            expected = fp8_mul_reference(a, b)
            actual = int(dut.uo_out.value)
            if actual != expected:
                 dut._log.error(f"FAIL: Input: A=0x{a:02x}, B=0x{b:02x} | Output: 0x{actual:02x} | Expected: 0x{expected:02x}")
                 assert actual == expected

    dut._log.info("All 65536 combinations passed!")
