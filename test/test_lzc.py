import cocotb
from cocotb.triggers import Timer
import random

@cocotb.test()
async def test_lzc_basic(dut):
    """Test LZC with various patterns"""

    # Test zero
    dut.in_i.value = 0
    await Timer(1, unit="ns")
    assert int(dut.cnt_o.value) == 40

    # Test all single-bit patterns
    for i in range(40):
        val = 1 << i
        dut.in_i.value = val
        await Timer(1, unit="ns")
        # bit 39 -> 0 zeros
        # bit 0  -> 39 zeros
        expected = 39 - i
        assert int(dut.cnt_o.value) == expected, f"Failed at bit {i}: got {int(dut.cnt_o.value)}, expected {expected}"

    # Test some random patterns
    for _ in range(1000):
        val = random.getrandbits(40)
        dut.in_i.value = val
        await Timer(1, unit="ns")

        if val == 0:
            expected = 40
        else:
            s = bin(val)[2:].zfill(40)
            expected = s.find('1')

        assert int(dut.cnt_o.value) == expected, f"Failed for {hex(val)}: got {int(dut.cnt_o.value)}, expected {expected}"

@cocotb.test()
async def test_lzc_edge_cases(dut):
    """Test LZC with specific edge cases"""

    # All ones
    dut.in_i.value = 0xFFFFFFFFFF
    await Timer(1, unit="ns")
    assert int(dut.cnt_o.value) == 0

    # One at MSB
    dut.in_i.value = 1 << 39
    await Timer(1, unit="ns")
    assert int(dut.cnt_o.value) == 0

    # One at LSB
    dut.in_i.value = 1
    await Timer(1, unit="ns")
    assert int(dut.cnt_o.value) == 39

    # Two ones
    dut.in_i.value = (1 << 39) | (1 << 0)
    await Timer(1, unit="ns")
    assert int(dut.cnt_o.value) == 0

    dut.in_i.value = (1 << 38) | (1 << 37)
    await Timer(1, unit="ns")
    assert int(dut.cnt_o.value) == 1
