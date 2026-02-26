# Test Concept: Streaming MX MAC Unit

## 1. Introduction
The verification of the Streaming MX MAC Unit ensures compliance with the **OCP Microscaling Formats (MX) Specification v1.0**. Given the complexity of supporting multiple floating-point (FP8, FP6, FP4) and integer (MXINT8) formats, a multi-layered verification strategy is employed to ensure bit-accuracy, protocol robustness, and physical reliability.

## 2. Verification Hierarchy

### 2.1. Level 1: Unit Testing (Combinatorial Logic)
- **Multiplier Core**: Exhaustive testing (256x256 combinations) for FP8/INT8 and full coverage for smaller formats.
- **Aligner**: Verification of shift amounts, saturation logic, and rounding mode application.
- **Accumulator**: Verification of 33-bit addition, sign extension, and overflow (SAT/WRAP) behavior.

### 2.2. Level 2: Integration Testing (Protocol FSM)
- **State Transitions**: Verify IDLE -> LOAD_SCALE -> STREAM -> PIPELINE -> OUTPUT transitions.
- **Timing Compliance**: Ensure scale and format sampling occurs at precise cycles (Cycle 1 and Cycle 2).
- **Control Signal Integrity**: Verify clear/enable signals to the accumulator and aligner based on the FSM state.

### 2.3. Level 3: System-Level Testing (Block MAC)
- **Full 41-Cycle Protocol**: End-to-end verification of a 32-element dot product.
- **Mixed-Precision**: Verifying operations where Operand A and Operand B use different formats.
- **Numerical Consistency**: Cross-verification against a Python-based bit-accurate reference model.

### 2.4. Level 4: Physical & Post-Synthesis Verification
- **Gate-Level Simulation (GLS)**: Verification of the synthesized netlist to catch timing violations or synthesis mismatches.
- **Power Analysis**: Switching activity (VCD) driven power estimation to evaluate mW/TOPS efficiency.

## 3. Bit-Accurate Reference Model
A Python reference model (`model.py` and within `test.py`) serves as the "Golden Reference".
- **Decoding**: Emulates the OCP MX decoding logic for all 7 supported formats.
- **Arithmetic**: Performs high-precision floating-point multiplication and alignment.
- **Rounding**: Implements TRN, CEL, FLR, and RNE logic bit-for-bit identical to the RTL.
- **Accumulation**: Models the 32-bit signed saturation/wrapping logic.

## 4. Test Generation Strategy

### 4.1. Exhaustive Testing
- **FP8 Multiplier**: All $2^8 \times 2^8 = 65,536$ input combinations are verified for E4M3 and E5M2.

### 4.2. Targeted Corner Cases
- **Zero & Subnormals**: Verification that subnormals are flushed to zero as per OCP MX requirements.
- **Infinities & NaNs**: Specifically for E5M2, ensuring IEEE-754 compliance or OCP-defined mappings.
- **Max/Min Magnitude**: Testing the limits of each format to ensure correct saturation.
- **Accumulator Overflow**: Forcing the 32-bit accumulator to hit the positive/negative limits to verify SAT/WRAP modes.
- **Alignment Extremes**: Testing very large and very small exponents to verify barrel shifter bounds.

### 4.3. Randomized Testing (Constrained Random)
- Random elements, random formats, and random scales across thousands of 41-cycle blocks to ensure no hidden state-space bugs.

## 5. Rounding Mode Verification
Verification of the four rounding modes defined in Cycle 1 `uio_in[4:3]`:
- **TRN (00)**: Truncate towards zero.
- **CEL (01)**: Ceiling (round towards $+\infty$).
- **FLR (10)**: Floor (round towards $-\infty$).
- **RNE (11)**: Round-to-Nearest-Even (standard IEEE).

Tests include mid-point values to ensure RNE "ties-to-even" logic is correct.

## 6. Formal Verification
- **FSM Safety**: Use Bounded Model Checking (BMC) to prove that the FSM cannot reach an undefined state.
- **Property Checking**: Assert that the accumulator is only cleared during the `LOAD_SCALE` phase.

## 7. HIL Phase 1: FPGA Prototyping (Gowin Tang Nano 9K)

### 7.1. Aims
- Validate RTL behavior on real hardware logic gates.
- Verify timing closure at the target frequency (27MHz).
- Ensure the 41-cycle protocol is stable under physical clock conditions.

### 7.2. HW / SW Setup
- **Hardware**:
  - Sipeed Tang Nano 9K FPGA board.
  - Raspberry Pi Pico (acting as a high-speed Serial-to-Parallel Bridge).
  - Breadboard and jumper wires connecting Pico GPIOs to Tang Nano headers.
- **Software**:
  - **Gowin EDA**: For synthesis and bitstream generation.
  - **Bridge Firmware (C/C++)**: Running on the Pico to receive test vectors via USB-CDC and drive the FPGA pins.
  - **Python Host Runner**: Sends randomized vectors and verifies results against the reference model.

### 7.3. Test Procedure
1. **Flash Bitstream**: Deploy the `tt_gowin_top` bitstream to the Tang Nano.
2. **Synchronize Bridge**: Use the Pico to send a reset pulse (`rst_n`) and verify the `IDLE` state.
3. **Burst Testing**:
   - Send a block of 32-element pairs.
   - Collect the 32-bit result serialized over 4 cycles.
   - Compare with Python reference.
4. **Stress Test**: Run 1 million randomized blocks with varying scales and formats.

## 8. HIL Phase 2: TT DevKit Emulation (ICE40)

### 8.1. Aims
- Evaluate performance on the "official" Tiny Tapeout emulation platform.
- Verify the physical pinout mapping and `uio` bidirectional behavior.
- Test the "Fast Start" (Scale Compression) mechanism in a self-contained environment.

### 8.2. HW / SW Setup
- **Hardware**:
  - Tiny Tapeout Development Kit (ICE40 version).
  - Onboard RP2040 (used as the test controller).
- **Software**:
  - **TT SDK**: To generate the ICE40 bitstream from Verilog.
  - **Test Firmware (MicroPython or C)**: Resides on the RP2040, eliminating the need for an external PC during the test loop.
  - **LED Indicators**: Map internal status (e.g., FSM state) to PMOD LEDs for visual debugging.

### 8.3. Test Procedure
1. **Self-Test Loop**: The RP2040 generates pseudo-random sequences (PRNG) internally.
2. **Automated Verification**: The RP2040 runs a simplified bit-accurate model to check results.
3. **Manual Override**: Use the DevKit DIP switches to manually step through cycles and observe `uo_out` on the 7-segment display.

## 9. ASIC Silicon Validation

### 9.1. Aims
- Characterize the maximum operational frequency ($F_{max}$) of the fabricated chip.
- Measure precise power consumption per MAC operation.
- Validate physical reliability across voltage/temperature corners (if equipment permits).

### 9.2. HW / SW Setup
- **Hardware**:
  - Tiny Tapeout Development Kit with the final ASIC plugged into the socket.
  - Precision Multi-meter (current measurement via Shunt resistor).
  - High-bandwidth Oscilloscope (100MHz+).
- **Software**:
  - Specialized "Characterization Firmware" on the RP2040 that sweeps the `clk` frequency.

### 9.3. Test Procedure
1. **Power Baseline**: Measure static power with `ena=0`.
2. **Frequency Sweep**: Increase frequency from 10MHz to 100MHz (or until failure) while running a continuous dot-product loop.
3. **Signature Analysis**: Collect `uo_out` patterns and verify them against the golden vectors at each frequency step.
4. **Efficiency Calculation**: Derive Energy-per-Operation ($\text{pJ/MAC}$).

## 10. Oscilloscope Measurements

To gain deeper insights into the physical behavior, the following measurements are performed on the TT DevKit:

| Measurement | Point | Purpose |
|-------------|-------|---------|
| **Latency** | `clk` vs `uo_out[7]` | Measure exact cycle-to-output delay and jitter. |
| **I/O Setup/Hold** | `ui_in` vs `clk` | Verify timing margins at high frequencies. |
| **Power Signature** | VCC Pin (AC coupled) | Observe the current spikes during the `STREAM` phase vs `IDLE` to correlate switching activity. |
| **Signal Integrity** | `uio[7:0]` | Check for crosstalk or ground bounce during high-speed switching of bidirectional pins. |

## 11. Continuous Integration
- Every commit triggers a full suite of cocotb tests.
- Automated generation of coverage reports (Line, Toggle, FSM).
- Performance regression tracking (Cycle count per MAC).
