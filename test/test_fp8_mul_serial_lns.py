import cocotb
from cocotb.triggers import Timer, RisingEdge
from cocotb.clock import Clock
import random

def to_bit_stream(val, fmt):
    # OCP MX formats: [S][E][M]
    # LSB first: M, E, S
    bits = [(val >> i) & 1 for i in range(8)]
    return bits

def mitchell_model(val_a, val_b, fmt_a, fmt_b):
    # Simplified Mitchell model for validation
    def decode(v, f):
        if f == 0: # E4M3: E[6:3], M[2:0], Bias 7
            return (v >> 7) & 1, (v >> 3) & 0xF, v & 0x7, 7, 3
        if f == 1: # E5M2: E[6:2], M[1:0], Bias 15
            return (v >> 7) & 1, (v >> 2) & 0x1F, v & 0x3, 15, 2
        if f == 4: # E2M1: E[2:1], M[0], Bias 1
            return (v >> 3) & 1, (v >> 1) & 0x3, v & 0x1, 1, 1
        return 0, 0, 0, 7, 3

    s1, e1, m1, b1, mw1 = decode(val_a, fmt_a)
    s2, e2, m2, b2, mw2 = decode(val_b, fmt_b)

    # Internal representation Log = E - Bias + M/(2^mw)
    log1 = e1 - b1 + m1 / (2.0**mw1)
    log2 = e2 - b2 + m2 / (2.0**mw2)
    log_sum = log1 + log2

    # Result Log in E4M3 (Bias 7, mw=3)
    res_log = log_sum + 7
    res_e = int(res_log) if res_log >= 0 else int(res_log) - (1 if res_log % 1 != 0 else 0)
    res_m = int((res_log - res_e) * 8.0 + 0.5) # Round for model consistency
    if res_m == 8: # Carry to E
        res_e += 1
        res_m = 0
    return s1 ^ s2, res_e, res_m

@cocotb.test()
async def test_fp8_mul_serial_lns_comprehensive(dut):
    """Comprehensive bit-serial LNS multiplication test"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.strobe.value = 0
    dut.a_bit.value = 0
    dut.b_bit.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    test_cases = [
        # (val_a, val_b, fmt_a, fmt_b)
        (0x38, 0x38, 0, 0), # 1.0 * 1.0 (E4M3)
        (0x3c, 0x38, 0, 0), # 1.5 * 1.0 (E4M3)
        (0x38, 0x3c, 0, 1), # 1.0 (E4M3) * 1.0 (E5M2, 1.0 is 0x3c)
        (0x3c, 0x3c, 0, 1), # 1.5 (E4M3) * 1.0 (E5M2)
        (0x40, 0x40, 1, 1), # 2.0 * 2.0 (E5M2, 2.0 is 0x40)
        (0x02, 0x02, 4, 4), # 1.0 * 1.0 (E2M1)
        (0x02, 0x38, 4, 0), # 1.0 (E2M1) * 1.0 (E4M3)
        (0x03, 0x3c, 4, 0), # 1.5 (E2M1) * 1.5 (E4M3)
    ]

    for va, vb, fa, fb in test_cases:
        bits_a = to_bit_stream(va, fa)
        bits_b = to_bit_stream(vb, fb)

        dut.format_a.value = fa
        dut.format_b.value = fb

        # Drive bit 0 DURING strobe
        dut.a_bit.value = bits_a[0]
        dut.b_bit.value = bits_b[0]
        dut.strobe.value = 1
        await Timer(1, unit="ns") # Allow combinatorial res_bit to settle
        res_bits = [int(dut.res_bit.value)]

        await RisingEdge(dut.clk)
        dut.strobe.value = 0

        for i in range(1, 15):
            dut.a_bit.value = bits_a[i] if i < 8 else 0
            dut.b_bit.value = bits_b[i] if i < 8 else 0
            await Timer(1, unit="ns") # res_bit is combinatorial
            res_bits.append(int(dut.res_bit.value))
            await RisingEdge(dut.clk)

        exp_s, exp_e_val, exp_m = mitchell_model(va, vb, fa, fb)
        exp_e = exp_e_val & 0xFF

        # Reconstruct result Log from bits 0-10 (M:0-2, E:3-10)
        m_res = res_bits[0] | (res_bits[1] << 1) | (res_bits[2] << 2)
        e_res = 0
        for i in range(8):
            e_res |= (res_bits[i+3] << i)

        e_res &= 0xFF

        assert dut.sign_out.value == exp_s, f"Sign mismatch: expected {exp_s}, got {dut.sign_out.value} for {va}*{vb}"
        assert e_res == exp_e, f"Exponent mismatch: expected {exp_e}, got {e_res} for {va}*{vb} (fmt {fa}x{fb})"
        assert abs(m_res - exp_m) <= 1, f"Mantissa mismatch: expected {exp_m}, got {m_res} for {va}*{vb} (fmt {fa}x{fb})"

@cocotb.test()
async def test_fp8_mul_serial_lns_special_all(dut):
    """Test all special values across formats"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.ena.value = 1
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Zero (0x0 * 0x0)
    dut.a_bit.value = 0
    dut.b_bit.value = 0
    dut.strobe.value = 1
    await RisingEdge(dut.clk)
    dut.strobe.value = 0
    for _ in range(12): await RisingEdge(dut.clk)
    assert dut.special_zero.value == 1

    # E5M2 Inf (0x7C * 1.0)
    bits_inf = to_bit_stream(0x7C, 1)
    bits_one = to_bit_stream(0x3C, 1) # 1.0 in E5M2 is 0x3C
    dut.format_a.value = 1
    dut.format_b.value = 1

    dut.a_bit.value = bits_inf[0]
    dut.b_bit.value = bits_one[0]
    dut.strobe.value = 1
    await RisingEdge(dut.clk)
    dut.strobe.value = 0
    for i in range(1, 12):
        dut.a_bit.value = bits_inf[i] if i < 8 else 0
        dut.b_bit.value = bits_one[i] if i < 8 else 0
        await RisingEdge(dut.clk)
    assert dut.special_inf.value == 1
    assert dut.special_nan.value == 0

    # E4M3 NaN (0x7F * 1.0)
    bits_nan = to_bit_stream(0x7F, 0)
    bits_one = to_bit_stream(0x38, 0) # 1.0 in E4M3 is 0x38
    dut.format_a.value = 0
    dut.format_b.value = 0

    dut.a_bit.value = bits_nan[0]
    dut.b_bit.value = bits_one[0]
    dut.strobe.value = 1
    await RisingEdge(dut.clk)
    dut.strobe.value = 0
    for i in range(1, 12):
        dut.a_bit.value = bits_nan[i] if i < 8 else 0
        dut.b_bit.value = bits_one[i] if i < 8 else 0
        await RisingEdge(dut.clk)
    assert dut.special_nan.value == 1
