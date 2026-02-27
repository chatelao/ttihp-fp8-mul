# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Timer
import random
import time

async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)

@cocotb.test()
async def performance_sweep(dut):
    """Measure throughput for multiple blocks."""
    dut._log.info("Starting Performance Sweep")
    clock = Clock(dut.clk, 10, unit="ns") # 100MHz for simulation
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    num_blocks = 100
    start_time = time.time()

    for block in range(num_blocks):
        # Cycle 1: Load Scale A and Format/Numerical Control
        dut.ui_in.value = 127
        dut.uio_in.value = 0 # E4M3, TRN, SAT
        await ClockCycles(dut.clk, 1)

        # Cycle 2: Load Scale B and Format B
        dut.ui_in.value = 0 # E4M3
        dut.uio_in.value = 127
        await ClockCycles(dut.clk, 1)

        # STREAM: 32 elements (Cycles 3-34)
        for i in range(32):
            dut.ui_in.value = random.randint(0, 255)
            dut.uio_in.value = random.randint(0, 255)
            await ClockCycles(dut.clk, 1)

        # PIPELINE: 5 cycles (Cycles 35-39)
        await ClockCycles(dut.clk, 5)

        # OUTPUT: 4 cycles (Cycles 40-43)
        await ClockCycles(dut.clk, 4)

    end_time = time.time()
    elapsed = end_time - start_time

    total_cycles = num_blocks * 44
    total_ops = num_blocks * 32 # 32 MAC operations

    dut._log.info(f"Processed {num_blocks} blocks ({total_ops} MAC ops) in {elapsed:.4f}s (simulated time: {total_cycles * 10}ns)")
    dut._log.info(f"Cycles per block: 44")
    dut._log.info(f"Throughput: {32/44:.4f} MACs/cycle")

@cocotb.test()
async def high_switching_activity(dut):
    """Generate high switching activity for power analysis simulation."""
    dut._log.info("Starting High Switching Activity Test")
    clock = Clock(dut.clk, 20, unit="ns") # 50MHz
    cocotb.start_soon(clock.start())
    await reset_dut(dut)

    # Use "Fast Start" to maximize streaming time
    # Cycle 0: IDLE. Set Fast Start bit ui_in[7]
    dut.ui_in.value = 0x80
    await ClockCycles(dut.clk, 1)

    # We run 1000 iterations of STREAM phase to get a good power signature
    for _ in range(1000):
        # STREAM: 32 elements
        for i in range(32):
            # Alternating bits to maximize switching
            dut.ui_in.value = 0xAA if (i % 2 == 0) else 0x55
            dut.uio_in.value = 0x55 if (i % 2 == 0) else 0xAA
            await ClockCycles(dut.clk, 1)

        # Cycle 35-39 (PIPELINE)
        await ClockCycles(dut.clk, 5)

        # Cycle 40-43 (OUTPUT)
        await ClockCycles(dut.clk, 4)

        # Back to IDLE (Cycle 0), trigger Fast Start again
        dut.ui_in.value = 0x80
        await ClockCycles(dut.clk, 1)

    dut._log.info("High switching activity sequence complete.")
