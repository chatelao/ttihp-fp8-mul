# SPDX-FileCopyrightText: © 2025 Jules
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer, RisingEdge
import os
import random

# Import utilities from the original test
from test import get_param, align_product_model, align_model, decode_format

async def send_block_header(dut, scale_a, scale_b, format_a, format_b,
                            round_mode=0, overflow_wrap=0, packed_mode=0, mx_plus_mode=0, lns_mode=0,
                            short_protocol=False):
    """Sends the first 3 cycles of a block."""
    if short_protocol:
        # Cycle 0 with Short Protocol bit set
        dut.ui_in.value = 0x80 | (lns_mode << 3)
        dut.uio_in.value = (format_a & 0x7) | (round_mode << 3) | (overflow_wrap << 5) | (packed_mode << 6) | (mx_plus_mode << 7)
        await RisingEdge(dut.clk)
        # Immediately moves to Cycle 3 (Stream)
    else:
        # Cycle 0: Metadata
        dut.ui_in.value = (lns_mode << 3)
        dut.uio_in.value = (round_mode << 3) | (overflow_wrap << 5) | (packed_mode << 6) | (mx_plus_mode << 7)
        await RisingEdge(dut.clk)

        # Cycle 1: Scale A / Format A
        dut.ui_in.value = scale_a
        dut.uio_in.value = (format_a & 0x7)
        await RisingEdge(dut.clk)

        # Cycle 2: Scale B / Format B
        dut.ui_in.value = scale_b
        dut.uio_in.value = (format_b & 0x7)
        await RisingEdge(dut.clk)

@cocotb.test()
async def test_high_density_overlap(dut):
    """
    Verifies that the MAC unit can process blocks back-to-back with
    37-cycle periodicity (Standard) or 21-cycle (Packed).
    """
    dut._log.info("Starting High Density Overlap Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Initial Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    # Cycle 0 metadata is sampled on the first edge after rst_n=1.

    # Test configuration
    num_blocks = 5
    format_a = 0 # E4M3
    format_b = 0
    scale_a = 127
    scale_b = 127

    # Pre-generate data for all blocks
    blocks_data = []
    expected_results = []

    acc_width = get_param(dut, "ACCUMULATOR_WIDTH", 32)
    aligner_width = get_param(dut, "ALIGNER_WIDTH", 40)
    support_shared = get_param(dut, "ENABLE_SHARED_SCALING", 1)

    for b in range(num_blocks):
        a_els = [random.randint(0, 255) for _ in range(32)]
        b_els = [random.randint(0, 255) for _ in range(32)]
        blocks_data.append((a_els, b_els))

        # Calculate expected result for each block
        expected_acc = 0
        for i in range(32):
            prod = align_product_model(a_els[i], b_els[i], format_a, format_b,
                                       aligner_width=aligner_width)
            # Intermediate additions in 32-bit signed fixed point
            expected_acc = (expected_acc + prod)
            if expected_acc > 2147483647: expected_acc = 2147483647
            if expected_acc < -2147483648: expected_acc = -2147483648

        if support_shared:
            shared_exp = scale_a + scale_b - 254
            acc_abs = abs(expected_acc)
            acc_sign = 1 if expected_acc < 0 else 0
            res = align_model(acc_abs, shared_exp + 5, acc_sign, width=aligner_width)
        else:
            res = expected_acc

        res = res & 0xFFFFFFFF
        if res & 0x80000000: res -= 0x100000000
        expected_results.append(res)

    # Task to capture results from uo_out
    captured_results = []
    async def capture_results():
        # Wait for the first capture event
        while int(dut.user_project.output_step_cnt.value) == 0:
            await RisingEdge(dut.clk)

        for b in range(num_blocks):
            res = 0
            # Wait for output_step_cnt to reach 4
            while int(dut.user_project.output_step_cnt.value) != 4:
                await RisingEdge(dut.clk)

            for i in range(4):
                await Timer(1, unit="ns")
                val = dut.uo_out.value
                if val.is_resolvable:
                    res = (res << 8) | int(val)
                else:
                    res = (res << 8) | 0x00
                await RisingEdge(dut.clk)
            captured_results.append(res if res < 0x80000000 else res - 0x100000000)

    cocotb.start_soon(capture_results())

    # Stream blocks
    for b in range(num_blocks):
        dut._log.info(f"Sending Block {b}")
        # Cycles 0-2 (or just 0 if we used short protocol)
        await send_block_header(dut, scale_a, scale_b, format_a, format_b)

        # Cycles 3-34: Elements
        a_els, b_els = blocks_data[b]
        for i in range(32):
            dut.ui_in.value = a_els[i]
            dut.uio_in.value = b_els[i]
            await RisingEdge(dut.clk)

        # Cycle 35: Flush
        dut.ui_in.value = 0
        dut.uio_in.value = 0
        await RisingEdge(dut.clk)

        # Cycle 36: Capture (last_cycle)
        # At the end of this cycle, cycle_count wraps to 0.
        # Next block starts immediately.

    # Wait for all results to be captured
    await ClockCycles(dut.clk, 40)

    for b in range(num_blocks):
        dut._log.info(f"Block {b}: Expected {expected_results[b]}, Captured {captured_results[b]}")
        assert captured_results[b] == expected_results[b]

@cocotb.test()
async def test_packed_fp4_overlap(dut):
    """
    Verifies that FP4 Packed mode can process blocks back-to-back with
    21-cycle periodicity.
    """
    support_packing = get_param(dut, "SUPPORT_VECTOR_PACKING", 1)
    if not support_packing:
        dut._log.info("Skipping Packed FP4 Overlap Test (Not supported)")
        return

    dut._log.info("Starting Packed FP4 Overlap Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Initial Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    num_blocks = 5
    format_a = 4 # E2M1
    format_b = 4
    packed_mode = 1

    blocks_data = []
    expected_results = []
    aligner_width = get_param(dut, "ALIGNER_WIDTH", 40)

    for b in range(num_blocks):
        a_els = [random.randint(0, 15) for _ in range(32)]
        b_els = [random.randint(0, 15) for _ in range(32)]
        blocks_data.append((a_els, b_els))

        expected_acc = 0
        for i in range(32):
            prod = align_product_model(a_els[i], b_els[i], format_a, format_b,
                                       aligner_width=aligner_width)
            expected_acc = (expected_acc + prod)
            if expected_acc > 2147483647: expected_acc = 2147483647
            if expected_acc < -2147483648: expected_acc = -2147483648

        # Result is signed 32-bit
        res = expected_acc & 0xFFFFFFFF
        if res & 0x80000000: res -= 0x100000000
        expected_results.append(res)

    captured_results = []
    async def capture_results_packed():
        while int(dut.user_project.output_step_cnt.value) == 0:
            await RisingEdge(dut.clk)

        for b in range(num_blocks):
            res = 0
            while int(dut.user_project.output_step_cnt.value) != 4:
                await RisingEdge(dut.clk)

            for i in range(4):
                await Timer(1, unit="ns")
                val = dut.uo_out.value
                if val.is_resolvable:
                    res = (res << 8) | int(val)
                await RisingEdge(dut.clk)
            captured_results.append(res if res < 0x80000000 else res - 0x100000000)

    cocotb.start_soon(capture_results_packed())

    for b in range(num_blocks):
        dut._log.info(f"Sending Packed Block {b}")
        # Cycle 0: Config (Packed=1)
        dut.ui_in.value = 0
        dut.uio_in.value = (1 << 6) # PACKED_EN
        await RisingEdge(dut.clk)

        # Cycle 1-2: Scales
        dut.ui_in.value = 127
        dut.uio_in.value = 4 # E2M1
        await RisingEdge(dut.clk)
        dut.ui_in.value = 127
        dut.uio_in.value = 4
        await RisingEdge(dut.clk)

        # Cycles 3-18: 16 cycles of packed elements
        a_els, b_els = blocks_data[b]
        for i in range(16):
            dut.ui_in.value = (a_els[2*i+1] << 4) | a_els[2*i]
            dut.uio_in.value = (b_els[2*i+1] << 4) | b_els[2*i]
            await RisingEdge(dut.clk)

        # Cycle 19: Flush
        dut.ui_in.value = 0
        dut.uio_in.value = 0
        await RisingEdge(dut.clk)

        # Cycle 20: Capture (last_cycle for packed)
        await RisingEdge(dut.clk)

    await ClockCycles(dut.clk, 30)
    for b in range(num_blocks):
        dut._log.info(f"Block {b}: Expected {expected_results[b]}, Captured {captured_results[b]}")
        assert captured_results[b] == expected_results[b]

@cocotb.test()
async def test_short_overlap(dut):
    """Verifies overlap using the Short Protocol (23-cycle periodicity)."""
    dut._log.info("Starting Short Protocol Overlap Test")
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())

    # Initial Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # First block MUST be standard to load scales
    scale_a = 127
    scale_b = 127
    format_a = 4 # E2M1 (needed for packed mode eventually, but here we just use it for standard short)
    format_b = 4

    await send_block_header(dut, scale_a, scale_b, format_a, format_b)
    for i in range(33): await RisingEdge(dut.clk) # Stream + Flush
    await RisingEdge(dut.clk) # Capture (logical_cycle 36)

    # Now start Short Protocol overlap
    num_blocks = 3
    for b in range(num_blocks):
        # Cycle 0: Short Start
        dut.ui_in.value = 0x80
        dut.uio_in.value = (format_a & 0x7)
        await RisingEdge(dut.clk)

        # Cycle 3..34
        for i in range(32):
            dut.ui_in.value = 0x02 # 1.0
            dut.uio_in.value = 0x02
            await RisingEdge(dut.clk)

        # Cycle 35: Flush
        await RisingEdge(dut.clk)
        # Cycle 36: Capture
        await RisingEdge(dut.clk)

    await ClockCycles(dut.clk, 10)
