import cocotb
from cocotb.triggers import Timer

@cocotb.test()
async def test_lzc40_basic(dut):
    """Test LZC40 with various patterns"""

    test_cases = [
        (0, 40),
        (1, 39),
        (1 << 39, 0),
        (1 << 38, 1),
        (0xFFFFFFFFFF, 0),
        (0x00000000FF, 32),
        (0x0000000001, 39),
        (0x0000000100, 31),
        (0x0000010000, 23),
        (0x0001000000, 15),
        (0x0100000000, 7),
        (0x8000000000, 0),
        (0x4000000000, 1),
        (0x0080000000, 8),
    ]

    for val, expected in test_cases:
        dut.in_val.value = val
        await Timer(1, unit="ns")
        actual = int(dut.cnt.value)
        dut._log.info(f"Input: 0x{val:010x}, Expected: {expected}, Actual: {actual}")
        assert actual == expected

@cocotb.test()
async def test_lzc40_exhaustive_8bit_high(dut):
    """Exhaustive test for the upper 8 bits"""
    for i in range(256):
        val = i << 32
        expected = 40
        if i != 0:
            expected = 7 - (i.bit_length() - 1)

        dut.in_val.value = val
        await Timer(1, unit="ns")
        actual = int(dut.cnt.value)
        assert actual == expected

@cocotb.test()
async def test_lzc40_random(dut):
    """Randomized tests for LZC40"""
    import random
    for _ in range(1000):
        val = random.getrandbits(40)
        expected = 40
        if val != 0:
            expected = 39 - (val.bit_length() - 1)

        dut.in_val.value = val
        await Timer(1, unit="ns")
        actual = int(dut.cnt.value)
        assert actual == expected
