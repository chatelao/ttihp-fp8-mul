import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from test import get_param

async def reset_with_debug(dut, debug_en=0, probe_sel=0, loopback_en=0):
    dut.ena.value = 1
    dut.ui_in.value = (debug_en << 6) | (loopback_en << 5)
    dut.uio_in.value = probe_sel & 0xF
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    # On the first posedge of clk after rst_n=1, k_counter is 0, so strobe is 1.
    # The design samples Cycle 0 and increments cycle_count to 1.
    await ClockCycles(dut.clk, 1)
    # Now cycle_count should be 1.

@cocotb.test()
async def test_debug_loopback(dut):
    dut._log.info("Start Debug Loopback Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Enable Loopback in Cycle 0 (loopback_en=1)
    await reset_with_debug(dut, loopback_en=1)

    # In Loopback mode, uo_out should follow ui_in immediately
    for val in [0x55, 0xAA, 0x00, 0xFF]:
        dut.ui_in.value = val
        await Timer(1, unit="ns")
        actual = int(dut.uo_out.value)
        dut._log.info(f"Loopback: in={val:02x}, out={actual:02x}")
        assert actual == val

@cocotb.test()
async def test_debug_probes(dut):
    dut._log.info("Start Debug Probes Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    k = get_param(dut, "SERIAL_K_FACTOR", 1)

    # Probe 1: FSM State & Logical Cycle
    await reset_with_debug(dut, debug_en=1, probe_sel=1)

    # Cycle 1: State should be LOAD_SCALE (1), logical_cycle=1
    # expected = {state[1:0], logical_cycle[5:0]} = 2'b01, 6'b000001 = 0x41
    await Timer(1, unit="ns")
    actual = int(dut.uo_out.value)
    dut._log.info(f"Probe 1, Cycle 1: out={actual:02x}")
    assert actual == 0x41

    await ClockCycles(dut.clk, k)
    # Cycle 2: State LOAD_SCALE, cycle 2 -> 0x42
    await Timer(1, unit="ns")
    actual = int(dut.uo_out.value)
    dut._log.info(f"Probe 1, Cycle 2: out={actual:02x}")
    assert actual == 0x42

    # Probe 9: Control Signals
    # We want to catch strobe=1. Strobe is 1 only when k_counter is 0.
    # At the start of a logical cycle (after k cycles), k_counter is 0.
    await reset_with_debug(dut, debug_en=1, probe_sel=9)
    # Immediately after reset_with_debug, we are at the beginning of Cycle 1.
    # k_counter just incremented to 1 on the edge that moved us to Cycle 1.
    # We need to wait k-1 more cycles to see k_counter wrap to 0.

    await ClockCycles(dut.clk, k - 1)
    await Timer(1, unit="ns")
    res = int(dut.uo_out.value)
    dut._log.info(f"Probe 9, end of Cycle 1: out={res:02x}")
    assert (res >> 7) & 1 == 1 # ena
    assert (res >> 6) & 1 == 1 # strobe
    # acc_clear is active during cycles 0, 1, 2
    assert (res >> 4) & 1 == 1 # acc_clear

@cocotb.test()
async def test_debug_metadata_echo(dut):
    dut._log.info("Start Debug Metadata Echo Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    k = get_param(dut, "SERIAL_K_FACTOR", 1)
    can_pack = get_param(dut, "SUPPORT_VECTOR_PACKING", 0) or \
               get_param(dut, "SUPPORT_INPUT_BUFFERING", 0) or \
               get_param(dut, "SUPPORT_PACKED_SERIAL", 0)

    # Enable debug
    await reset_with_debug(dut, debug_en=1)

    # Cycle 1: Load config: format_a=4 (FP4), RM=3 (RNE), Wrap=1, Packed=1
    # uio_in[2:0]=4, [4:3]=3, [5]=1, [6]=1 -> 01111100 = 0x7C
    dut.ui_in.value = 127
    dut.uio_in.value = 0x7C
    await ClockCycles(dut.clk, k)

    # Cycle 2: format_b=4
    dut.ui_in.value = 127
    dut.uio_in.value = 4
    await ClockCycles(dut.clk, k)

    # capture_cycle is 36 for standard mode.
    # metadata echo happens at capture_cycle - 1 = 35.
    await ClockCycles(dut.clk, 32 * k)

    # At Cycle 35, should see metadata_echo
    await Timer(1, unit="ns")
    # metadata_echo = {mx_plus_en_val, packed_mode_reg, overflow_wrap_reg, round_mode_reg, format_a_reg}
    # {0, (can_pack ? 1 : 0), 1, 3, 4}
    # If can_pack=0: 0_0_1_11_100 -> 00111100 -> 0x3C
    # If can_pack=1: 0_1_1_11_100 -> 01111100 -> 0x7C
    expected = 0x7C if can_pack else 0x3C
    actual = int(dut.uo_out.value)
    dut._log.info(f"Metadata Echo, Cycle 35: out={actual:02x}, expected={expected:02x}")
    assert actual == expected
