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
- **Full 40-Cycle Protocol**: End-to-end verification of a 32-element dot product.
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
- Random elements, random formats, and random scales across thousands of 40-cycle blocks to ensure no hidden state-space bugs.

## 5. Rounding Mode Verification
Verification of the four rounding modes defined in Cycle 1 `uio_in[4:3]`:
- **TRN (00)**: Truncate towards zero.
- **CEL (01)**: Ceiling (round towards $+\infty$).
- **FLR (10)**: Floor (round towards $-\infty$).
- **RNE (11)**: Round-to-Nearest-Even (standard IEEE).

Tests include mid-point values to ensure RNE "ties-to-even" logic is correct.

## 6. Formal Verification (Future)
- **FSM Safety**: Use Bounded Model Checking (BMC) to prove that the FSM cannot reach an undefined state.
- **Property Checking**: Assert that the accumulator is only cleared during the `LOAD_SCALE` phase.

## 7. Hardware-in-the-Loop (HIL)
- **Platform**: Sipeed Tang Nano 9K (Gowin GW1NR-9C).
- **Interface**: A Python-based runner feeds test vectors via a UART-to-Parallel bridge (if implemented) or via direct GPIO stimulation using a logic analyzer/MCU.
- **Goal**: Verify that the RTL behaves identically on real silicon (FPGA) as it does in simulation.

## 8. Continuous Integration
- Every commit triggers a full suite of cocotb tests.
- Automated generation of coverage reports (Line, Toggle, FSM).
- Performance regression tracking (Cycle count per MAC).
