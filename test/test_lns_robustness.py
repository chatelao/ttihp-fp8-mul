import cocotb
from cocotb.triggers import Timer, RisingEdge, FallingEdge
from cocotb.clock import Clock
import random

# Reuse helper functions from test.py if possible, but for standalone robustness we redefine
def float_to_mxfp8(v, fmt):
    # This is a very simplified version for testing specific special values
    if fmt == 0: # E4M3
        if v == float('nan'): return 0x7F
        if v == float('inf'): return 0x7E # E4M3 has no Inf, saturates
        if v == -float('inf'): return 0xFE
    if fmt == 1: # E5M2
        if v == float('nan'): return 0x7E # One possible NaN
        if v == float('inf'): return 0x7C
        if v == -float('inf'): return 0xFC
    return 0

async def send_cycle(dut, ui, uio, k_factor):
    dut.ui_in.value = ui
    dut.uio_in.value = uio
    await RisingEdge(dut.clk)
    for _ in range(k_factor - 1):
        await RisingEdge(dut.clk)

def get_k_factor(dut):
    try:
        support_serial = int(dut.user_project.SUPPORT_SERIAL.value)
        if support_serial:
            return int(dut.user_project.SERIAL_K_FACTOR.value)
    except AttributeError:
        pass
    return 1

@cocotb.test()
async def test_nan_propagation_e5m2(dut):
    """Test NaN propagation in E5M2 format"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    k_factor = get_k_factor(dut)

    dut.rst_n.value = 0
    dut.ena.value = 1
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Cycle 0: IDLE
    await send_cycle(dut, 0, 0, k_factor)

    # Cycle 1: LOAD_SCALE A, Format A=E5M2 (001)
    # E5M2 format code is 1
    await send_cycle(dut, 0x80, 0x01, k_factor)

    # Cycle 2: LOAD_SCALE B, Format B=E5M2
    await send_cycle(dut, 0x80, 0x01, k_factor)

    # Cycle 3: STREAM - NaN * 1.0
    # E5M2 NaN: 0x7E, 1.0: 0x3C
    await send_cycle(dut, 0x7E, 0x3C, k_factor)
    print(f"Cycle 3: nan={dut.user_project.mul_nan_lane0.value}, inf={dut.user_project.mul_inf_lane0.value}")

    # Cycle 4-34: STREAM - 0 * 0
    for _ in range(31):
        await send_cycle(dut, 0, 0, k_factor)

    # Wait for capture_cycle (36 for non-packed)
    while int(dut.user_project.logical_cycle.value) < 36:
        await RisingEdge(dut.clk)

    # Check sticky bit
    assert dut.user_project.nan_sticky.value == 1, "nan_sticky should be set by NaN element"

    # Check output at capture_cycle
    await Timer(1, "ns")
    # IEEE-754 Quiet NaN is 0x7FC00000
    assert dut.user_project.final_scaled_result.value == 0x7FC00000, f"Expected NaN override 0x7FC00000, got {hex(int(dut.user_project.final_scaled_result.value))}"

@cocotb.test()
async def test_inf_propagation_e5m2(dut):
    """Test Infinity propagation in E5M2 format"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    k_factor = get_k_factor(dut)

    dut.rst_n.value = 0
    dut.ena.value = 1
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Cycle 0: IDLE
    await send_cycle(dut, 0, 0, k_factor)

    # Cycle 1: LOAD_SCALE A, Format A=E5M2
    await send_cycle(dut, 0x80, 0x01, k_factor)

    # Cycle 2: LOAD_SCALE B, Format B=E5M2
    await send_cycle(dut, 0x80, 0x01, k_factor)

    # Cycle 3: Stream +Inf
    # E5M2 +Inf: 0x7C, 1.0: 0x3C
    await send_cycle(dut, 0x7C, 0x3C, k_factor)
    print(f"Cycle 3: nan={dut.user_project.mul_nan_lane0.value}, inf={dut.user_project.mul_inf_lane0.value}")

    for _ in range(31):
        await send_cycle(dut, 0, 0, k_factor)

    while int(dut.user_project.logical_cycle.value) < 36:
        await RisingEdge(dut.clk)

    assert dut.user_project.inf_pos_sticky.value == 1
    assert dut.user_project.nan_sticky.value == 0
    await Timer(1, "ns")
    assert dut.user_project.final_scaled_result.value == 0x7F800000

@cocotb.test()
async def test_mixed_inf_to_nan(dut):
    """Test that +Inf and -Inf in the same block results in NaN"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    k_factor = get_k_factor(dut)

    dut.rst_n.value = 0
    dut.ena.value = 1
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Cycle 0: IDLE
    await send_cycle(dut, 0, 0, k_factor)

    # Metadata
    await send_cycle(dut, 0x80, 0x01, k_factor) # E5M2
    await send_cycle(dut, 0x80, 0x01, k_factor)

    # +Inf
    await send_cycle(dut, 0x7C, 0x3C, k_factor)

    # -Inf
    await send_cycle(dut, 0xFC, 0x3C, k_factor)

    for _ in range(30):
        await send_cycle(dut, 0, 0, k_factor)

    while int(dut.user_project.logical_cycle.value) < 36:
        await RisingEdge(dut.clk)

    assert dut.user_project.inf_pos_sticky.value == 1
    assert dut.user_project.inf_neg_sticky.value == 1
    await Timer(1, "ns")
    # effective_nan = nan_sticky || (inf_pos_sticky && inf_neg_sticky)
    assert dut.user_project.final_scaled_result.value == 0x7FC00000

@cocotb.test()
async def test_shared_scale_nan_rule(dut):
    """Test Shared Scale NaN Rule (Scale=0xFF)"""
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    k_factor = get_k_factor(dut)

    dut.rst_n.value = 0
    dut.ena.value = 1
    await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)

    # Cycle 0: IDLE
    await send_cycle(dut, 0, 0, k_factor)

    # Cycle 1: Scale A = 0xFF -> NaN
    await send_cycle(dut, 0xFF, 0x00, k_factor) # E4M3

    # Cycle 2: Scale B
    await send_cycle(dut, 0x80, 0x00, k_factor)

    # Stream normal values
    for _ in range(32):
        await send_cycle(dut, 0x38, 0x38, k_factor)

    while int(dut.user_project.logical_cycle.value) < 36:
        await RisingEdge(dut.clk)

    assert dut.user_project.nan_sticky.value == 1
    await Timer(1, "ns")
    assert dut.user_project.final_scaled_result.value == 0x7FC00000
