import cocotb
from cocotb.triggers import RisingEdge, Timer, ReadOnly
from cocotb.clock import Clock
import random

async def drive_serial(dut, val, width=40):
    for i in range(width):
        dut.strobe.value = 1 if i == 0 else 0
        dut.data_in_bit.value = (val >> i) & 1
        await RisingEdge(dut.clk)
    dut.strobe.value = 0
    dut.data_in_bit.value = 0

@cocotb.test()
async def test_accumulator_serial_basic(dut):
    """Test basic bit-serial accumulation"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Initialize
    dut.ena.value = 1
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.strobe.value = 0
    dut.data_in_bit.value = 0

    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")

    # Accumulate 123 + 456
    val1 = 123
    val2 = 456

    # 1. Add val1 (initial 0 + val1)
    await drive_serial(dut, val1)
    await Timer(1, unit="ns") # Exit ReadOnly if any
    res1 = int(dut.parallel_out.value)
    assert res1 == val1, f"Expected {val1}, got {res1}"

    # 2. Add val2 (val1 + val2)
    await drive_serial(dut, val2)
    await Timer(1, unit="ns")
    res2 = int(dut.parallel_out.value)
    expected = (val1 + val2)
    assert res2 == expected, f"Expected {expected}, got {res2}"

@cocotb.test()
async def test_accumulator_serial_random(dut):
    """Random bit-serial accumulation tests"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.strobe.value = 0
    dut.data_in_bit.value = 0
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    accumulator = 0
    for _ in range(20):
        val = random.getrandbits(32)
        await drive_serial(dut, val)
        await Timer(1, unit="ns")
        accumulator = (accumulator + val) & ((1 << 40) - 1)
        res = int(dut.parallel_out.value)
        assert res == accumulator, f"Random mismatch: expected {accumulator}, got {res}"

@cocotb.test()
async def test_accumulator_serial_clear(dut):
    """Test serial accumulator clear"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.rst_n.value = 1
    dut.clear.value = 1
    await RisingEdge(dut.clk)
    dut.clear.value = 0
    await Timer(1, unit="ns")
    assert int(dut.parallel_out.value) == 0

    # Add something
    val = 0xAA55
    await drive_serial(dut, val)
    await Timer(1, unit="ns")
    assert int(dut.parallel_out.value) == val

    # Clear
    dut.clear.value = 1
    await RisingEdge(dut.clk)
    dut.clear.value = 0
    await Timer(1, unit="ns")
    assert int(dut.parallel_out.value) == 0
