import cocotb
from cocotb.triggers import Timer, RisingEdge
from cocotb.clock import Clock
import random

@cocotb.test()
async def test_aligner_serial_basic(dut):
    """Basic serial aligner test: verify alignment shift and sign handling"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.strobe.value = 0
    dut.exp_sum.value = 0
    dut.sign.value = 0
    dut.prod_bit.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Test Case 1: Positive product, Exp = 0
    # Expected: Product shifted by k0 = 3
    val = 0xA5 # 10100101
    dut.exp_sum.value = 0
    dut.sign.value = 0
    dut.strobe.value = 1
    await RisingEdge(dut.clk)
    dut.strobe.value = 0

    results = []
    for i in range(16):
        dut.prod_bit.value = (val >> i) & 1 if i < 8 else 0
        await Timer(1, unit="ns")
        results.append(int(dut.aligned_bit.value))
        await RisingEdge(dut.clk)

    # k0 = 3, so first 3 bits should be 0, then val should start
    expected = [0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0]
    assert results == expected, f"Expected {expected}, got {results}"

    # Test Case 2: Negative product, Exp = 1
    # Expected: Product shifted by k0 = 4, then negated
    val = 0x01 # 00000001
    dut.exp_sum.value = 1
    dut.sign.value = 1 # Negative
    dut.strobe.value = 1
    await RisingEdge(dut.clk)
    dut.strobe.value = 0

    results = []
    for i in range(16):
        dut.prod_bit.value = (val >> i) & 1 if i < 8 else 0
        await Timer(1, unit="ns")
        results.append(int(dut.aligned_bit.value))
        await RisingEdge(dut.clk)

    # k0 = 4, so first 4 bits are 0.
    # val = 00000001. After k0=4: 0000 0000 0001 0000
    # Negation: -X = ~X + 1
    # In bits (LSB first):
    # ~X: 1111 1111 1110 1111
    # +1: 0000 0000 0001 1111? No.
    # X = 0x0010 (binary 0000 0000 0001 0000)
    # -X = 0xFFF0 (binary 1111 1111 1111 0000)
    # Bit stream (LSB first): 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    expected_neg = [0, 0, 0, 0] + [1]*12
    assert results == expected_neg, f"Expected {expected_neg}, got {results}"
