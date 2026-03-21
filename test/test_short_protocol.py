import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
import os
import sys

# Add current directory to path to import test
sys.path.append(os.path.dirname(__file__))
from test import run_mac_test, get_param, decode_format, align_product_model, align_model, reset_dut

@cocotb.test()
async def test_short_protocol_metadata(dut):
    dut._log.info("Start Short Protocol Metadata Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1)

    # 1. Reset with Short Protocol Start
    dut.ena.value = 1
    # Check if MXFP4 and vector packing are supported
    support_mxfp4 = get_param(dut, "SUPPORT_MXFP4", 1)
    support_packing = get_param(dut, "SUPPORT_VECTOR_PACKING", 0)
    support_serial = get_param(dut, "SUPPORT_SERIAL", 0)

    if not support_mxfp4:
        dut._log.info("Skipping Short Protocol Test (SUPPORT_MXFP4=0)")
        return

    # ui_in[7]=1 (Fast Start)
    # uio_in: format_a=4 (bits 2:0), round_mode=0 (bits 4:3), overflow_wrap=0 (bit 5)
    # Bit 6 of uio_in is Packed Mode in CONFIG cycle
    packed_en = support_packing
    dut.ui_in.value = 0x80
    dut.uio_in.value = 4 | (0 << 3) | (0 << 5) | (packed_en << 6) # E2M1, TRN, SAT, Packed
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # After first clock edge, cycle_count becomes 3.
    # We wait k_factor cycles to align with the first element sampling.
    await ClockCycles(dut.clk, k_factor)

    # Unit should now be at Cycle 3 (STATE_STREAM)
    # We expect it to use format_a=4.

    # E2M1: 1.0 is 0x02.
    # If packed: Each byte 0x22 = two 1.0s. Run for 16 cycles.
    # If not packed: Each byte 0x02 = one 1.0. Run for 32 cycles.
    num_cycles = 16 if packed_en else 32
    val = 0x22 if packed_en else 0x02

    for i in range(num_cycles):
        dut.ui_in.value = val
        dut.uio_in.value = val

        if i == 0:
            # Verify internal format capture during the first streaming cycle
            # Use Timer(1) to ensure non-blocking assignments have taken effect
            await Timer(1, unit="ns")
            try:
                # Try reading the active format wires first
                f_a = int(dut.user_project.format_a.value)
                f_b = int(dut.user_project.format_b_val.value)
                dut._log.info(f"Verified active formats: A={f_a}, B={f_b}")
                assert f_a == 4
                assert f_b == 4
            except AttributeError:
                # Fallback to registers if wires are not accessible
                try:
                    f_a_reg = int(dut.user_project.format_a_reg.value)
                    # Check if gen_format_b exists
                    try:
                        f_b_reg = int(dut.user_project.gen_format_b.format_b.value)
                    except AttributeError:
                        f_b_reg = f_a_reg
                    dut._log.info(f"Verified internal format registers: A={f_a_reg}, B={f_b_reg}")
                    assert f_a_reg == 4
                    assert f_b_reg == 4
                except AttributeError as e:
                    dut._log.info(f"Internal format signals not found, skipping check: {e}")

        await ClockCycles(dut.clk, k_factor)

    # Pipeline flush + Shared Scale
    # If serial, the timing might be slightly different depending on effective_pipelining
    # but 2*k_factor is a good baseline for the two-cycle gap.
    await ClockCycles(dut.clk, 2 * k_factor)

    # Expected: 32 * 1.0 * 1.0 = 32.
    # In fixed point (bit 8 = 1.0), 32 * 256 = 8192.
    # NOTE: In standard protocol, if scales were never loaded, they are 0.
    # BUT Short Protocol REUSES previous scales.
    # Since we just reset, they are likely 0 or 127 depending on reset values.
    # In project.v: scale_a/scale_b reset to 0.
    # scale=0 means 2^(0-127) = extremely small.
    # However, the core logic should still accumulate 32.
    # If ENABLE_SHARED_SCALING=0, we get the unscaled 32.
    # If ENABLE_SHARED_SCALING=1, we get the scaled 32 * 2^(0+0-254) which is 0.

    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    expected = 8192 if not support_shared else 0

    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor)

    if actual_acc & 0x80000000: actual_acc -= 0x100000000

    dut._log.info(f"Actual Result: {actual_acc}, Expected: {expected}")
    assert actual_acc == expected

@cocotb.test()
async def test_short_protocol_nan_scale_reuse(dut):
    """
    Test that starting a Short Protocol block with reused NaN (0xFF) scales
    correctly latches the nan_sticky bit.
    """
    dut._log.info("Start Short Protocol NaN Scale Reuse Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    k_factor = get_param(dut, "SERIAL_K_FACTOR", 1)
    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 0)
    if not support_shared:
        dut._log.info("Skipping test (ENABLE_SHARED_SCALING=0)")
        return

    # 1. First, run a standard block with scale_a = 0xFF to set the register
    await run_mac_test(dut, format_a=0, format_b=0, a_elements=[0x38]*32, b_elements=[0x38]*32, scale_a=0xFF, scale_b=127)

    # 2. Now start a Short Protocol block. It should reuse the 0xFF scale.
    # ui_in[7]=1
    dut.ui_in.value = 0x80
    dut.uio_in.value = 0 | (0 << 3) | (0 << 5) | (0 << 6) # E4M3, TRN, SAT, No Packed

    # Rising edge samples metadata and ui_in[7], jumping to Cycle 3
    await ClockCycles(dut.clk, 1)

    # Check nan_sticky immediately in the next cycle (Cycle 3)
    # The fix ensures nan_sticky is latched during the IDLE -> STREAM transition
    await Timer(1, unit="ns")
    try:
        nan_sticky = int(dut.user_project.nan_sticky.value)
        dut._log.info(f"nan_sticky value after Short Protocol start: {nan_sticky}")
        assert nan_sticky == 1
    except AttributeError:
        dut._log.info("nan_sticky signal not accessible for direct assertion")

    # Finish the block and check output
    for i in range(32):
        dut.ui_in.value = 0x38
        dut.uio_in.value = 0x38
        await ClockCycles(dut.clk, k_factor)

    await ClockCycles(dut.clk, 2 * k_factor) # Flush + Scale

    # Read Result
    actual_acc = 0
    for i in range(4):
        await Timer(1, unit="ns")
        actual_acc = (actual_acc << 8) | int(dut.uo_out.value)
        await ClockCycles(dut.clk, k_factor)

    # Result should be NaN (0x7FC00000)
    dut._log.info(f"Actual Result: 0x{actual_acc:08X}, Expected: 0x7FC00000")
    assert actual_acc == 0x7FC00000
