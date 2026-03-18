"""
MicroPython MAC Runner for TT DevKit (RP2040)
This script runs one 32-element MAC operation using the 41-cycle protocol.
"""
import machine
import os
import time

# Identify board version based on machine info
is_rp2350 = "RP2350" in os.uname().machine

# Pin Configuration for TT DevKit
if is_rp2350: # v3.2 (RP2350)
    # ui_in: GP17-GP24
    UI_IN = [machine.Pin(i, machine.Pin.OUT) for i in range(17, 25)]
    # uo_out: GP33-GP40
    UO_OUT = [machine.Pin(i, machine.Pin.IN) for i in range(33, 41)]
    # uio: GP25-GP32
    UIO = [machine.Pin(i, machine.Pin.OUT) for i in range(25, 33)]
    # Control Pins
    CLK = machine.Pin(16, machine.Pin.OUT)
    RST_N = machine.Pin(14, machine.Pin.OUT)
    ENA = machine.Pin(15, machine.Pin.OUT)
else: # v2.0/v3.1 (RP2040)
    # ui_in: GP0-GP7
    UI_IN = [machine.Pin(i, machine.Pin.OUT) for i in range(8)]
    # uo_out: GP8-GP15
    UO_OUT = [machine.Pin(i, machine.Pin.IN) for i in range(8, 16)]
    # uio: GP16-GP23
    UIO = [machine.Pin(i, machine.Pin.OUT) for i in range(16, 24)]
    # Control Pins
    CLK = machine.Pin(24, machine.Pin.OUT)
    RST_N = machine.Pin(25, machine.Pin.OUT)
    ENA = machine.Pin(26, machine.Pin.OUT)

def set_ui_in(val):
    for i in range(8):
        UI_IN[i].value((val >> i) & 1)

def set_uio_in(val):
    # Set UIO as output to drive B elements and Config
    for i in range(8):
        UIO[i].init(machine.Pin.OUT)
        UIO[i].value((val >> i) & 1)

def get_uo_out():
    val = 0
    for i in range(8):
        if UO_OUT[i].value():
            val |= (1 << i)
    return val

def clock_step():
    CLK.value(1)
    time.sleep_us(10) # ~50kHz clock for stability
    CLK.value(0)
    time.sleep_us(10)

def run_mac():
    print("Initializing Streaming MAC...")
    ENA.value(1)
    RST_N.value(0)
    CLK.value(0)
    time.sleep_ms(10)
    RST_N.value(1)
    time.sleep_ms(10)

    # Cycle 0 -> 1
    clock_step()

    # Cycle 1: Scale A and Config
    # Format A = E4M3 (0), Rounding = TRN (0), Overflow = SAT (0)
    set_ui_in(127) # Scale A = 1.0
    set_uio_in(0x00)
    clock_step() # Moves to Cycle 2, samples Scale A

    # Cycle 2: Scale B and Format B
    set_ui_in(127) # Scale B = 1.0
    set_uio_in(0x00) # Format B = E4M3
    clock_step() # Moves to Cycle 3, samples Scale B

    # Cycle 3-34: Stream 32 elements (1.0 * 1.0)
    # 0x38 = 1.0 in E4M3
    set_ui_in(0x38)
    set_uio_in(0x38)
    print("Streaming 32 elements (1.0 * 1.0)...")
    for _ in range(32):
        clock_step() # Moves through cycles 3 to 34

    # Cycle 35: Pipeline Flush
    set_ui_in(0)
    set_uio_in(0)
    clock_step() # Moves from 35 to 36

    # Cycle 36: Shared Scaling Calculation
    clock_step() # Moves from 36 to 37

    # Cycle 37-40: Output (MSB First)
    print("Reading Result...")
    result = 0
    for i in range(4):
        # Data is present on uo_out during cycles 37, 38, 39, 40
        byte = get_uo_out()
        result = (result << 8) | byte
        print(f" Byte {3-i}: 0x{byte:02x}")
        clock_step()

    # Signed 32-bit conversion
    if result & 0x80000000:
        result -= 0x100000000

    print("-" * 30)
    print(f"Fixed-Point Result: {result}")
    print(f"Floating-Point:     {result / 256.0}")
    print("-" * 30)

    if result == 8192:
        print("SUCCESS: Result matches expected 32.0 (0x2000)")
    else:
        print(f"WARNING: Expected 8192, got {result}")

if __name__ == "__main__":
    run_mac()
