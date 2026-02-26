import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer
import random

@cocotb.test()
async def test_accumulator_basic(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.en.value = 0
    dut.data_in.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, "ns")

    # Accumulate some values
    expected_sum = 0
    for i in range(100):
        val = random.randint(-10000, 10000)
        dut.data_in.value = val
        dut.en.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, "ns")
        expected_sum += val

        actual_sum = int(dut.data_out.value)
        # Handle 32-bit signed in Python
        if actual_sum & 0x80000000:
            actual_sum -= 0x100000000

        assert actual_sum == expected_sum, f"Iteration {i}: Expected {expected_sum}, got {actual_sum}"

    # Clear
    dut.clear.value = 1
    await RisingEdge(dut.clk)
    await Timer(1, "ns")
    assert int(dut.data_out.value) == 0
    dut.clear.value = 0
    await RisingEdge(dut.clk)

@cocotb.test()
async def test_accumulator_32_elements(dut):
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut.rst_n.value = 1
    dut.clear.value = 1
    dut.en.value = 0
    await ClockCycles(dut.clk, 2)
    dut.clear.value = 0
    await RisingEdge(dut.clk)
    await Timer(1, "ns")

    # Accumulate 32 elements (max range)
    expected_sum = 0

    for i in range(32):
        val = random.randint(-1000000, 1000000)
        dut.data_in.value = val
        dut.en.value = 1
        await RisingEdge(dut.clk)
        await Timer(1, "ns")
        expected_sum += val

    actual_sum = int(dut.data_out.value)
    if actual_sum & 0x80000000:
        actual_sum -= 0x100000000

    assert actual_sum == expected_sum, f"32-element sum: Expected {expected_sum}, got {actual_sum}"
