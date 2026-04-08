import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer

@cocotb.test()
async def test_asynchronous_reset(dut):
    """Verify that rst_n acts as an asynchronous reset."""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Initialize
    dut.rst_n.value = 1
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0

    # Wait for a few clock cycles
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    # Set some state (cycle_count)
    # We can't directly set cycle_count because it's internal,
    # but we can advance the protocol.
    # In STATE_IDLE (cycle 0), if ui_in[7]=0, it goes to cycle 1.
    dut.ui_in.value = 0x00
    await RisingEdge(dut.clk)
    # Now it should be cycle 1.
    # We can check uo_out if debug is enabled, but let's just assume it advanced.

    # Assert reset in the middle of the clock cycle
    await Timer(5, units="ns")
    dut.rst_n.value = 0

    # Immediately check if reset took effect (asynchronous)
    await Timer(1, units="ns")

    # We need a way to verify internal state.
    # tt_um_chatelao_fp8_multiplier has a debug mode.
    # If we enable debug mode and select a probe, we can see internal state.
    # Probe 1: {state, logical_cycle[5:0]}

    # Let's restart with debug enabled.
    dut.rst_n.value = 1
    dut.ui_in.value = 0x40 # debug_en (ui_in[6])
    dut.uio_in.value = 0x01 # probe_sel = 1 (uio_in[3:0])
    await RisingEdge(dut.clk) # Samples Cycle 0

    # Cycle 1
    await RisingEdge(dut.clk)

    # Verify we are not at 0
    assert dut.uo_out.value != 0, "Should have non-zero probe data in Cycle 1"

    # Assert reset asynchronously
    await Timer(5, units="ns")
    dut.rst_n.value = 0
    await Timer(1, units="ns")

    # In Cycle 0, probe 1 output is probe_data which is {state, cycle} = {0, 0} = 0.
    # But wait, Cycle 0 output is:
    # (debug_en_val && logical_cycle < capture_cycle) ? probe_data : 8'h00;
    # logical_cycle is 0. state is IDLE (0). probe_data for probe 1 is 0.

    # Let's use a different probe or just check if it's 0.
    # Actually, if it resets to 0, it should be 0.
    assert dut.uo_out.value == 0, f"uo_out should be 0 after async reset, got {dut.uo_out.value}"

    # Verify it stays 0
    await RisingEdge(dut.clk)
    assert dut.uo_out.value == 0

    # Release reset
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    # Should advance to Cycle 1 again (if ui_in still has debug_en)
    # Actually Cycle 0 is sampled at posedge.
    # If we release it after posedge, next posedge will sample Cycle 0.
    await RisingEdge(dut.clk)
    assert dut.uo_out.value != 0
