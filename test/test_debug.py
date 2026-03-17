import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
from test import get_param

async def reset_with_debug(dut, debug_en=0, probe_sel=0, loopback_en=0, rm=0, overflow=0, packed=0, mx_plus=0):
    dut.ena.value = 1
    # ui_in[6]=Debug En, [5]=Loopback En
    dut.ui_in.value = (debug_en << 6) | (loopback_en << 5)
    # uio_in[3:0]=Probe Sel, [4]=RM[1], [5]=Overflow, [6]=Packed, [7]=MX+ En
    # Note: uio_in[3] is also RM[0]. So Probe Sel bits 3 and RM[0] are same.
    uio_val = (probe_sel & 0xF) | ((rm & 2) << 3) | (overflow << 5) | (packed << 6) | (mx_plus << 7)
    # Ensure RM[0] is consistent with probe_sel[3] if we want to be pedantic
    # but here we just follow the requested bit mapping.
    dut.uio_in.value = uio_val
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
    # Ensure uio_in is 0
    dut.uio_in.value = 0
    await reset_with_debug(dut, loopback_en=1)

    # In Loopback mode, uo_out should follow ui_in immediately (as ui_in ^ 0)
    for val in [0x55, 0xAA, 0x00, 0xFF]:
        dut.ui_in.value = val
        await Timer(1, unit="ns")
        actual = int(dut.uo_out.value)
        dut._log.info(f"Loopback: ui_in={val:02x}, out={actual:02x}")
        assert actual == val

@cocotb.test()
async def test_debug_probes(dut):
    dut._log.info("Start Debug Probes Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    support_serial_hw = get_param(dut, "SUPPORT_SERIAL", 0)
    k = get_param(dut, "SERIAL_K_FACTOR", 1) if support_serial_hw else 1

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

    support_serial_hw = get_param(dut, "SUPPORT_SERIAL", 0)
    k = get_param(dut, "SERIAL_K_FACTOR", 1) if support_serial_hw else 1
    can_pack = get_param(dut, "SUPPORT_VECTOR_PACKING", 0) or \
               get_param(dut, "SUPPORT_INPUT_BUFFERING", 0) or \
               get_param(dut, "SUPPORT_PACKED_SERIAL", 0)

    # Enable debug and load metadata in Cycle 0
    # format_a=4 (FP4), RM=3 (RNE), Wrap=1, Packed=1
    # Note: reset_with_debug sets uio_in.
    # We want RM=3, so rm=3. Probe sel 0.
    # uio_in[3:0]=0, [4]=RM[1]=1. RM[0] is uio_in[3], which is 0.
    # So if we want RM=3, we need probe_sel[3]=1.
    await reset_with_debug(dut, debug_en=1, probe_sel=8, rm=3, overflow=1, packed=1, mx_plus=0)

    # Cycle 1: Load Scale A and Format A
    # BM Index A = 0
    dut.ui_in.value = 127
    dut.uio_in.value = 4 # format_a=4, bm_index_a=0
    await ClockCycles(dut.clk, k)

    # Cycle 2: Load Scale B and Format B
    # BM Index B = 0
    dut.ui_in.value = 127
    dut.uio_in.value = 4 # format_b=4, bm_index_b=0
    await ClockCycles(dut.clk, k)

    # We just finished the strobe for Cycle 2. cycle_count is now 3.
    # The first element is sampled at cycle_count=3.
    # format_a and format_b are both 4, so if packing is supported, it will be in packed mode.
    is_packed = can_pack
    capture_cycle = 20 if is_packed else 36

    # We are at the end of Cycle 2 (strobe just finished).
    # cycle_count is now 3.
    # We need to wait until Cycle capture_cycle - 1.
    # wait = (capture_cycle - 1 - 3) * k + (k-1) to reach the end of that cycle
    wait_cycles = (capture_cycle - 1 - 3) * k + (k - 1)
    if wait_cycles > 0:
        await ClockCycles(dut.clk, wait_cycles)

    # Now at Cycle capture_cycle - 1, should see metadata_echo
    await Timer(1, unit="ns")
    # metadata_echo = {mx_plus_en_val, packed_mode_reg, overflow_wrap_reg, round_mode_reg, format_a_reg}
    # {0, (is_packed ? 1 : 0), 1, 3, 4}
    # 0_1_1_11_100 = 01111100 = 0x7C
    expected = 0x7C if is_packed else 0x3C
    actual = int(dut.uo_out.value)
    cur_cycle = int(dut.user_project.cycle_count.value)
    dut._log.info(f"Metadata Echo, Cycle {cur_cycle} (expected {capture_cycle-1}): out={actual:02x}, expected={expected:02x}")

    if actual != expected:
        # Check internal registers
        pa = int(dut.user_project.packed_mode_reg.value)
        ov = int(dut.user_project.overflow_wrap_reg.value)
        rm = int(dut.user_project.round_mode_reg.value)
        fa = int(dut.user_project.format_a_reg.value)
        mx = int(dut.user_project.mx_plus_en_val.value)
        dut._log.info(f"Internal: mx={mx}, packed={pa}, overflow={ov}, rm={rm}, fa={fa}")

    assert actual == expected

@cocotb.test()
async def test_uio_loopback(dut):
    dut._log.info("Start UIO Loopback Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Enable Loopback in Cycle 0
    await reset_with_debug(dut, loopback_en=1)
    # Set ui_in to 0 after loopback is enabled
    dut.ui_in.value = 0

    # uio_oe should be 0x00 (all inputs to avoid combinational loops)
    await Timer(1, unit="ns")
    assert int(dut.uio_oe.value) == 0x00

    # uo_out should reflect ui_in ^ uio_in. Since ui_in=0, uo_out == uio_in.
    for val in [0x55, 0xAA, 0x00, 0xFF]:
        dut.uio_in.value = val
        await Timer(1, unit="ns")
        actual = int(dut.uo_out.value)
        dut._log.info(f"UIO Loopback check on uo_out: uio_in={val:02x}, out={actual:02x}")
        assert actual == val

@cocotb.test()
async def test_loopback_persistence(dut):
    dut._log.info("Start Loopback Persistence Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    support_serial_hw = get_param(dut, "SUPPORT_SERIAL", 0)
    k = get_param(dut, "SERIAL_K_FACTOR", 1) if support_serial_hw else 1

    # Enable Loopback in Cycle 0
    await reset_with_debug(dut, loopback_en=1)

    # Release loopback_en in Cycle 1
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, k * 45) # Run past a full 41-cycle operation

    # Should still be in loopback
    dut.ui_in.value = 0x12
    await Timer(1, unit="ns")
    assert int(dut.uo_out.value) == 0x12

@cocotb.test()
async def test_debug_no_packed_interference(dut):
    dut._log.info("Start Debug No Packed Interference Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    support_serial_hw = get_param(dut, "SUPPORT_SERIAL", 0)
    k = get_param(dut, "SERIAL_K_FACTOR", 1) if support_serial_hw else 1

    # Fast Start with Debug Enable (ui_in[6]=1, ui_in[7]=1)
    # But uio_in[6] (Packed Mode) is 0.
    dut.ena.value = 1
    dut.ui_in.value = 0xC0 # ui_in[7]=1 (Fast Start), ui_in[6]=1 (Debug En)
    dut.uio_in.value = 0x00 # All other config 0, including uio_in[6] (Packed Mode)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1) # Samples Cycle 0

    # Now cycle_count should be 3 (jumped from 0 to 3)
    await Timer(1, unit="ns")
    assert int(dut.user_project.cycle_count.value) == 3

    # Verify packed_mode_reg is 0
    # metadata_echo = {mx_plus_en_val, packed_mode_reg, overflow_wrap_reg, round_mode_reg, format_a_reg}
    # at Cycle 35
    await ClockCycles(dut.clk, (35-3) * k)
    await Timer(1, unit="ns")
    actual = int(dut.uo_out.value)
    dut._log.info(f"Metadata Echo: {actual:02x}")
    assert (actual >> 6) & 1 == 0 # packed_mode_reg should be 0
