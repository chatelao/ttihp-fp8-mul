# Concept: Streaming MX MAC Unit for Tiny Tapeout

## 1. Introduction
The scaling of Deep Learning models necessitates efficient numerical representations to overcome the "Memory Wall". The **OCP Microscaling Formats (MX) Specification v1.0** introduces a block-based scaling approach that significantly reduces memory bandwidth and hardware complexity. This concept outlines the implementation of an MX-compatible Multiply-Accumulate (MAC) unit supporting various floating-point and integer formats within the strict constraints of a single **1x1 Tiny Tapeout tile** (Sky130/IHP SG13G2).

## 2. Numerical Representation: OCP MX
The implementation supports multiple **OCP MX** formats, including MXFP8, MXFP6, MXFP4, and MXINT8, all sharing a common block scaling factor.

- **Shared Scale**: UE8M0 (8-bit unsigned biased exponent, Bias 127, power-of-two scaling).
- **Element Formats**:
  - **MXFP8**: E4M3 (Bias 7) and E5M2 (Bias 15).
  - **MXFP6**: E3M2 (Bias 3) and E2M3 (Bias 1).
  - **MXFP4**: E2M1 (Bias 1).
  - **MXINT8**: Standard and Symmetric 8-bit signed integers.

### Bitwise Layouts
All formats are aligned to the lower bits of the 8-bit input wires during the `STREAM` phase.

#### E4M3 (8-bit MXFP8)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | S | E3 | E2 | E1 | E0 | M2 | M1 | M0 |
- **S**: Sign bit. **E[3:0]**: Exponent (Bias 7). **M[2:0]**: Mantissa.

#### E5M2 (8-bit MXFP8)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | S | E4 | E3 | E2 | E1 | E0 | M1 | M0 |
- **S**: Sign bit. **E[4:0]**: Exponent (Bias 15). **M[1:0]**: Mantissa.

#### E3M2 (6-bit MXFP6)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | - | - | S | E2 | E1 | E0 | M1 | M0 |
- **S**: Sign bit. **E[2:0]**: Exponent (Bias 3). **M[1:0]**: Mantissa.

#### E2M3 (6-bit MXFP6)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | - | - | S | E1 | E0 | M2 | M1 | M0 |
- **S**: Sign bit. **E[1:0]**: Exponent (Bias 1). **M[2:0]**: Mantissa.

#### E2M1 (4-bit MXFP4)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | - | - | - | - | S | E1 | E0 | M0 |
- **S**: Sign bit. **E[1:0]**: Exponent (Bias 1). **M[0]**: Mantissa.

#### MXINT8 (8-bit)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | S | V6 | V5 | V4 | V3 | V2 | V1 | V0 |
- **S**: Sign bit. **V[6:0]**: Value (Two's complement).
- **INT8_SYM**: Symmetric range where -128 is clamped to -127.

#### Shared Scale: UE8M0 (8-bit)
| Bit | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Field** | X7 | X6 | X5 | X4 | X3 | X2 | X1 | X0 |
- **X[7:0]**: 8-bit Unsigned Biased Exponent (Bias 127).

### Numerical Semantics
- **Block Size ($k$)**: 32 elements.
- **Mathematical Formula**:
  - **FP Formats**: $V_i = (-1)^{S_i} \times 2^{E_i - \text{Bias}} \times (1 + M_i) \times 2^{X-127}$
  - **INT Formats**: $V_i = (\text{Integer}_i \times 2^{-6}) \times 2^{X-127}$ (As per OCP MX v1.0, INT8 has an implicit $2^{-6}$ scale).
- **Subnormals**: Flushed to zero (E=0).
- **Special Values**: The unit prioritizes saturation for out-of-range values. E5M2 supports IEEE-style Infinities and NaNs, while other formats utilize the full range for finite numbers or specialized NaN encodings as per OCP MX v1.0.

## 3. Architecture: Operand Streaming
To fit within the ~320 D-Flip-Flop (DFF) budget of a 1x1 tile, the design employs **Temporal Multiplexing (Operand Streaming)**.

### 3.1. I/O Protocol (41-Cycle Sequence)
The unit communicates with a host using a strictly timed protocol:

| Phase | Cycles | Input (`ui_in`) | Input (`uio_in`) | Output (`uo_out`) |
|-------|--------|-----------------|------------------|-------------------|
| **IDLE** | 0 | - | - | 0 |
| **LOAD_SCALE** | 1 | Scale $X_A$ | Format/NC | 0 |
| **LOAD_SCALE** | 2 | - | Scale $X_B$ | 0 |
| **STREAM** | 3-34 | Element $A_i$ | Element $B_i$ | 0 |
| **PIPELINE** | 35-36 | - | - | 0 |
| **OUTPUT** | 37-40 | - | - | Accumulator[byte] |

#### Detailed I/O Bit Mapping

**Table 1: Input `ui_in` (Primary)**
| Phase | Cycles | Bits [7:0] | Function | Description |
|-------|--------|------------|----------|-------------|
| **IDLE** | 0 | `SXXXXXXX` | **Fast Start** | Bit [7]=1 skips LOAD_SCALE cycles. |
| **LOAD_SCALE** | 1 | `X_A[7:0]` | **Scale A** | Shared UE8M0 scale for Tensor A. |
| **LOAD_SCALE** | 2 | `XXXXXXXX` | N/A | |
| **STREAM** | 3-34 | `A_i[7:0]` | **Element A** | MXFP8 element (E4M3/E5M2). |
| **PIPELINE** | 35-36 | `XXXXXXXX` | N/A | |
| **OUTPUT** | 37-40 | `XXXXXXXX` | N/A | |

**Table 2: Input `uio_in` (Bidirectional)**
| Phase | Cycles | Bits [7:0] | Function | Description |
|-------|--------|------------|----------|-------------|
| **IDLE** | 0 | `00000000` | N/A | |
| **LOAD_SCALE** | 1 | `XXOWWRRR` | **Format/NC** | Bits [2:0]: Format, [4:3]: Rounding, [5]: Overflow. |
| **LOAD_SCALE** | 2 | `X_B[7:0]` | **Scale B** | Shared UE8M0 scale for Tensor B. |
| **STREAM** | 3-34 | `B_i[7:0]` | **Element B** | MX element (aligned to lower bits). |
| **PIPELINE** | 35 | `XXXXXXXX` | Isolated | |
| **OUTPUT** | 36-39 | `XXXXXXXX` | Isolated | |

#### Table 4: Supported Formats
| Format ID (`FFF`) | Name | Type | Bits | Sign | Exponent | Mantissa | Bias |
|---|---|---|---|---|---|---|---|
| `000` | E4M3 | MXFP8 | 8 | [7] | [6:3] | [2:0] | 7 |
| `001` | E5M2 | MXFP8 | 8 | [7] | [6:2] | [1:0] | 15 |
| `010` | E3M2 | MXFP6 | 6 | [5] | [4:2] | [1:0] | 3 |
| `011` | E2M3 | MXFP6 | 6 | [5] | [4:3] | [2:0] | 1 |
| `100` | E2M1 | MXFP4 | 4 | [3] | [2:1] | [0] | 1 |
| `101` | INT8 | MXINT8 | 8 | [7] | N/A | [6:0] | N/A |
| `110` | INT8_SYM | MXINT8 | 8 | [7] | N/A | [6:0] | N/A |

#### Table 5: Numerical Control Bits (Cycle 1)
| Bits | Name | Description |
|---|---|---|
| [2:0] | Format | Format Selection (see Table 4). |
| [4:3] | Rounding | 00: TRN (Truncate), 01: CEIL (Round up), 10: FLOOR (Round down), 11: RNE (Ties to Even). |
| [5] | Overflow | 0: SAT (Saturation), 1: WRAP (Wrapping). |

**Table 3: Output `uo_out` (Accumulator Serialization)**
| Phase | Cycle | Bits [7:0] | Content |
|-------|-------|------------|---------|
| **OUTPUT** | 37 | `Acc[31:24]` | Byte 3 (MSB) |
| **OUTPUT** | 38 | `Acc[23:16]` | Byte 2 |
| **OUTPUT** | 39 | `Acc[15:8]` | Byte 1 |
| **OUTPUT** | 40 | `Acc[7:0]` | Byte 0 (LSB) |

### 3.2. Hardware/Software Co-Design
The hardware computes the dot product of the scaled elements but factors out the shared scales to minimize gate count:
$$C = \left( \sum_{i=1}^{32} \text{FP}(A_i) \times \text{FP}(B_i) \right) \times 2^{(X_A-127) + (X_B-127)}$$
The ASIC performs the summation and the intermediate exponent arithmetic. The final scaling by the shared factors is performed by the host software (default) or hardware-accelerated in later stages.

## 4. Microarchitecture
### 4.1. Datapath
- [x] **Sign Logic**: $S_{res} = S_A \oplus S_B$ (for FP) or signed multiplication (for INT).
- [x] **Exponent Path**: Unified logic for variable exponent ranges and biases.
- [x] **Mantissa Multiplier**: 4x4-bit integer multiplier (extended to 8x8 for INT8).
- [x] **Alignment Shifter**: A barrel shifter aligns the product to a 32-bit fixed-point format (bit 8 = $2^0$) with saturation logic.
- [x] **Accumulator**: A 32-bit signed register stores the running sum.

### 4.2. Control Logic
- [x] **Finite State Machine (FSM)**: Manages the 38-cycle protocol, including format and scale sampling.

## 5. Resource Estimation (1x1 Tile)
- **D-Flip-Flops (DFFs)**: ~150 DFFs (approx. 45% of 1x1 tile limit).
- **Combinational Logic**: 8x8 Multiplier + Barrel Shifter + 32-bit Adder.
- **Total Area**: Optimized for IHP SG13G2 1x1 tile.

## 6. Implementation Roadmap

### Phase 1: Baseline MXFP8 Implementation

#### Step 1: Protocol Skeleton & FSM (Status: **COMPLETED**)
- **Goal**: Establish the 41-cycle operational protocol.
- **Details**: Implemented a 6-bit cycle counter and FSM (IDLE, LOAD_SCALE, STREAM, OUTPUT). Updated to 40 cycles to support pipelined datapath.
- **Verification**: Cocotb tests verify state transitions and I/O timing.

#### Step 2: MXFP8 Multiplier Core (Status: **COMPLETED**)
- **Goal**: Implement combinatorial FP8 multiplication logic.
- **Refinement (Review findings)**: Refactored to align with OCP MX v1.0 (flush subnormals, support E5M2, simplify IEEE-754 logic).
- **Verification**: Exhaustive 256x256 unit tests against Python model.

#### Step 3: Product Alignment (Status: **COMPLETED**)
- **Goal**: Align the floating-point product to a 32-bit fixed-point format.
- **Details**: Implemented a barrel shifter with saturation logic (clamps to 32-bit signed range).
- **Verification**: Unit tests for wide exponent range coverage.

#### Step 4: Accumulator Unit (Status: **COMPLETED**)
- **Goal**: Maintain a running sum of aligned products.
- **Details**: 32-bit signed accumulator with synchronous clear during scale loading.
- **Verification**: Summation accuracy tests for 32-element blocks.

#### Step 5: Full Datapath Integration (Status: **COMPLETED**)
- **Goal**: Integrate all components into the top-level Tiny Tapeout module.
- **Details**: Connected FSM, Multiplier, Aligner, and Accumulator. Implemented result serialization.
- **Verification**: Full system-level verification of the 38-cycle protocol.

#### Step 6: Physical Design & Gate-Level Simulation (Status: **IN PROGRESS**)
- **Goal**: Validate area, timing, and post-synthesis correctness.
- **Tasks**:
  - Run OpenLane/LibreLane synthesis and verify area utilization.
  - Run Gate-Level Simulation (GLS) to ensure timing closure and netlist correctness.
  - Generate GDS and verify against Tiny Tapeout constraints.

---

### Phase 2: Advanced OCP MX Features

#### Step 7: Extended Floating Point Support (MXFP6 & MXFP4) (Status: **COMPLETED**)
- **Goal**: Support 6-bit and 4-bit floating point formats.
- **Details**:
  - Implemented decoding for E3M2 (Bias 3), E2M3 (Bias 1), and E2M1 (Bias 1).
  - Updated 38-cycle protocol to support 3-bit format selection during Cycle 1.
  - Unified datapath to handle variable exponent ranges and mantissa padding.

#### Step 8: Integer Support (MXINT8) & Symmetric Range (Status: **COMPLETED**)
- **Goal**: Support 8-bit integer elements (MXINT8).
- **Details**:
  - Implemented signed 8x8 multiplication with implicit $2^{-6}$ scale (mapped to $2^{-4}$ alignment shift).
  - Added support for both standard INT8 and symmetric INT8 (clamping -128 to -127).
- **Verification**: Dedicated test cases for both INT8 variants and randomized testing.

#### Step 9: Advanced Numerical Control (Rounding & Overflow) (Status: **COMPLETED**)
- **Goal**: Implement optional rounding modes and configurable overflow methods.
- **Details**:
  - Implemented four rounding modes: Truncate (00), Ceil (01), Floor (10), and Round-to-Nearest-Ties-to-Even (11).
  - Added configurable overflow methods: Saturation (0) vs. Wrapping (1), applied to both the aligner and the 32-bit accumulator.
  - Configuration sampled from `uio_in[5:3]` during Cycle 1 of the protocol.
  - Optimized aligner logic and pipelined the datapath to meet 27MHz timing for Gowin.
- **Verification**: Targeted tests for rounding bit-accuracy and saturation/wrap behavior.

#### Step 10: Mixed-Precision Operations (Status: **COMPLETED**)
- **Goal**: Enable independent format selection for Operand A and Operand B.
- **Details**:
  - Decoupled format selection logic for A and B.
  - Implemented unified exponent sum formula to handle mixed FP/INT precision.
  - Updated 41-cycle protocol to sample `format_a` (Cycle 1) and `format_b` (Cycle 2).
- **Verification**: New mixed-precision and randomized test cases in `test/test.py`.

#### Step 11: Hardware-Accelerated Shared Scaling (Status: **COMPLETED**)
- **Goal**: Apply shared scales ($X_A, X_B$) in hardware.
- **Details**:
  - Reused the `fp8_aligner` to apply the shared scale $2^{(X_A-127) + (X_B-127)}$ to the 32-bit accumulator.
  - Optimized the 41-cycle protocol by removing a pipeline stage to ensure the fully scaled result is ready for serialization starting at cycle 36.
- **Verification**: New test cases in `test/test.py` verify accuracy for varying shared scales and randomized vectors.

#### Step 12: Throughput Optimization & Scale Compression (Status: **COMPLETED**)
- **Goal**: Maximize performance and efficiency.
- **Details**:
  - Implemented a pipeline stage after the multiplier to break the critical path to the aligner/accumulator.
  - Updated the operational protocol to 41 cycles (0-40) to accommodate the pipeline flush while maintaining registered outputs.
  - Implemented "Fast Start" (Scale Compression) allowing the reuse of previous scales/formats by jumping from IDLE to STREAM.
- **Verification**: Updated Python reference model and protocol verification script.

---

### Phase 3: Rigorous Verification & Optimization

#### Step 13: Comprehensive Coverage-Driven Verification (Status: **COMPLETED**)
- **Goal**: Achieve 100% functional and code coverage for all formats.
- **Details**:
  - Implemented a functional coverage collector in `test/test_coverage.py` using `cocotb-coverage`.
  - Achieved 100% cross-coverage for all format combinations, rounding modes, and overflow settings.
  - Verified edge cases including NaNs/Infinities (E5M2), subnormal flushing, and saturation boundaries.
  - Synchronized unit tests for `fp8_aligner` to match the updated 32-bit pipelined interface.

#### Step 14: Formal Protocol Proofs (Status: **COMPLETED**)
- **Goal**: Mathematically prove the correctness of the 41-cycle FSM.
- **Details**:
  - Defined formal properties using SystemVerilog Assertions (SVA) within `src/project.v`.
  - Verified FSM state transitions, cycle count progression, and "Fast Start" logic.
  - Proved register stability and output gating/serialization correctness.
  - Successfully proved all properties using SymbiYosys and Z3 with k-induction.

#### Step 15: Power & Performance Characterization (Status: **COMPLETED**)
- **Goal**: Evaluate the MAC unit's efficiency.
- **Details**:
  - Achieved a throughput of 0.7805 MACs/cycle (32 MACs per 41-cycle block).
  - Synthesized cell count: 3784 cells (approx. 104k cells/mm² in 1x2 tile).
  - Theoretical performance: 42.15 MFLOPS @ 27MHz, 156.10 MFLOPS @ 100MHz.
  - Implemented high-switching activity test suite for power signature analysis.
- **Verification**: Dedicated `test/test_performance.py` and `test/analyze_performance.py` scripts.

#### Step 16: Hardware-in-the-Loop (HIL) Validation
- **Goal**: Cross-verify RTL behavior on the Tang Nano 9K FPGA.
- **Tasks**:
  - Develop a serial-to-parallel interface for high-throughput hardware testing.
  - Compare FPGA results bit-for-bit with the Python reference model.

#### Step 17: Test on the TT Dev Kit
- **Goal**: Verify the design on the [Tiny Tapeout Development Kit](https://store.tinytapeout.com/products/FPGA-Development-Kit-p813805747).
- **Tasks**:
  - Deploy the bitstream to the TT Dev Kit FPGA.
  - Validate the 41-cycle streaming protocol using real hardware I/O.

#### Step 18: Final ASIC Silicon Validation
- **Goal**: Verify the fabricated OCP MX MAC Unit on the [TT Demo Board](https://github.com/TinyTapeout/tt-demo-pcb) using the TT Dev Kit.
- **Tasks**:
  - **Functional HIL Verification**: Use a Raspberry Pi Pico as a master controller to drive the 41-cycle streaming protocol, verifying results bit-accurately against the Python reference model.
  - **Oscilloscope Characterization**: Measure protocol latency (from LOAD_SCALE to serialization) and clock jitter on the hardware.
  - **Power Signature Analysis**: Analyze power consumption signatures during the STREAM phase using an oscilloscope to characterize the final silicon.

---

### Phase 4: Parameterization & Scalability

#### Step 19: Hardware Parameterization (Status: **COMPLETED**)
- **Goal**: Make the design scalable via Verilog parameters.
- **Details**:
  - Implement `SUPPORT_MXFP6`, `SUPPORT_MXFP4`, and `SUPPORT_ADV_ROUNDING` to prune logic.
  - Implement `ENABLE_SHARED_SCALING` and `SUPPORT_MIXED_PRECISION` for architectural scaling.
  - Parameterize `ALIGNER_WIDTH` for datapath optimization.
- **Verification**: Matrix testing of Full, Lite, and Tiny variants.

## 7. Verification Strategy

### 7.1. Verification Hierarchy

#### Level 1: Unit Testing (Combinatorial Logic) (Status: **COMPLETED**)
- **Multiplier Core**: Exhaustive testing (256x256 combinations) for FP8/INT8 and full coverage for smaller formats.
- **Aligner**: Verification of shift amounts, saturation logic, and rounding mode application.
- **Accumulator**: Verification of 33-bit addition, sign extension, and overflow (SAT/WRAP) behavior.

#### Level 2: Integration Testing (Protocol FSM) (Status: **COMPLETED**)
- **State Transitions**: Verify IDLE -> LOAD_SCALE -> STREAM -> PIPELINE -> OUTPUT transitions.
- **Timing Compliance**: Ensure scale and format sampling occurs at precise cycles (Cycle 1 and Cycle 2).
- **Control Signal Integrity**: Verify clear/enable signals to the accumulator and aligner based on the FSM state.

#### Level 3: System-Level Testing (Block MAC) (Status: **COMPLETED**)
- **Full 41-Cycle Protocol**: End-to-end verification of a 32-element dot product.
- **Mixed-Precision**: Verifying operations where Operand A and Operand B use different formats.
- **Numerical Consistency**: Cross-verification against a Python-based bit-accurate reference model.

#### Level 4: Physical & Post-Synthesis Verification (Status: **IN PROGRESS**)
- **Gate-Level Simulation (GLS)**: Verification of the synthesized netlist to catch timing violations or synthesis mismatches.
- **Power Analysis**: Switching activity (VCD) driven power estimation to evaluate mW/TOPS efficiency.

### 7.2. Bit-Accurate Reference Model (Status: **COMPLETED**)
A Python reference model (`model.py` and within `test.py`) serves as the "Golden Reference".
- **Decoding**: Emulates the OCP MX decoding logic for all 7 supported formats.
- **Arithmetic**: Performs high-precision floating-point multiplication and alignment.
- **Rounding**: Implements TRN, CEL, FLR, and RNE logic bit-for-bit identical to the RTL.
- **Accumulation**: Models the 32-bit signed saturation/wrapping logic.

### 7.3. Test Generation Strategy (Status: **COMPLETED**)

#### Exhaustive Testing
- **FP8 Multiplier**: All $2^8 \times 2^8 = 65,536$ input combinations are verified for E4M3 and E5M2.

#### Targeted Corner Cases
- **Zero & Subnormals**: Verification that subnormals are flushed to zero as per OCP MX requirements.
- **Infinities & NaNs**: Specifically for E5M2, ensuring IEEE-754 compliance or OCP-defined mappings.
- **Max/Min Magnitude**: Testing the limits of each format to ensure correct saturation.
- **Accumulator Overflow**: Forcing the 32-bit accumulator to hit the positive/negative limits to verify SAT/WRAP modes.
- **Alignment Extremes**: Testing very large and very small exponents to verify barrel shifter bounds.

#### Randomized Testing (Constrained Random)
- Random elements, random formats, and random scales across thousands of 41-cycle blocks to ensure no hidden state-space bugs.

### 7.4. Rounding Mode Verification (Status: **COMPLETED**)
Verification of the four rounding modes defined in Cycle 1 `uio_in[4:3]`:
- **TRN (00)**: Truncate towards zero.
- **CEL (01)**: Ceiling (round towards $+\infty$).
- **FLR (10)**: Floor (round towards $-\infty$).
- **RNE (11)**: Round-to-Nearest-Even (standard IEEE).

Tests include mid-point values to ensure RNE "ties-to-even" logic is correct.

### 7.5. Formal Verification (Status: **COMPLETED**)
- **FSM Safety**: Use Bounded Model Checking (BMC) to prove that the FSM cannot reach an undefined state.
- **Property Checking**: Assert that the accumulator is only cleared during the `LOAD_SCALE` phase.

### 7.6. HIL Phase 1: FPGA Prototyping (Gowin Tang Nano 9K) (Status: **COMPLETED**)

#### Aims
- Validate RTL behavior on real hardware logic gates.
- Verify timing closure at the target frequency (27MHz).
- Ensure the 41-cycle protocol is stable under physical clock conditions.

#### HW / SW Setup
- **Hardware**:
  - Sipeed Tang Nano 9K FPGA board.
  - Raspberry Pi Pico (acting as a high-speed Serial-to-Parallel Bridge).
  - Breadboard and jumper wires connecting Pico GPIOs to Tang Nano headers.
- **Software**:
  - **Gowin EDA**: For synthesis and bitstream generation.
  - **Bridge Firmware (C/C++)**: Running on the Pico to receive test vectors via USB-CDC and drive the FPGA pins.
  - **Python Host Runner**: Sends randomized vectors and verifies results against the reference model.

#### Test Procedure
1. **Flash Bitstream**: Deploy the `tt_gowin_top` bitstream to the Tang Nano.
2. **Synchronize Bridge**: Use the Pico to send a reset pulse (`rst_n`) and verify the `IDLE` state.
3. **Burst Testing**:
   - Send a block of 32-element pairs.
   - Collect the 32-bit result serialized over 4 cycles.
   - Compare with Python reference.
4. **Stress Test**: Run 1 million randomized blocks with varying scales and formats.

### 7.7. HIL Phase 2: TT DevKit Emulation (ICE40) (Status: **IN PROGRESS**)

#### Aims
- Evaluate performance on the "official" Tiny Tapeout emulation platform.
- Verify the physical pinout mapping and `uio` bidirectional behavior.
- Test the "Fast Start" (Scale Compression) mechanism in a self-contained environment.

#### HW / SW Setup
- **Hardware**:
  - Tiny Tapeout Development Kit (ICE40 version).
  - Onboard RP2040 (used as the test controller).
- **Software**:
  - **TT SDK**: To generate the ICE40 bitstream from Verilog.
  - **Test Firmware (MicroPython or C)**: Resides on the RP2040, eliminating the need for an external PC during the test loop.
  - **LED Indicators**: Map internal status (e.g., FSM state) to PMOD LEDs for visual debugging.

#### Test Procedure
1. **Self-Test Loop**: The RP2040 generates pseudo-random sequences (PRNG) internally.
2. **Automated Verification**: The RP2040 runs a simplified bit-accurate model to check results.
3. **Manual Override**: Use the DevKit DIP switches to manually step through cycles and observe `uo_out` on the 7-segment display.

### 7.8. ASIC Silicon Validation (Status: **PLANNED**)

#### Aims
- Characterize the maximum operational frequency ($F_{max}$) of the fabricated chip.
- Measure precise power consumption per MAC operation.
- Validate physical reliability across voltage/temperature corners (if equipment permits).

#### HW / SW Setup
- **Hardware**:
  - Tiny Tapeout Development Kit with the final ASIC plugged into the socket.
  - Precision Multi-meter (current measurement via Shunt resistor).
  - High-bandwidth Oscilloscope (100MHz+).
- **Software**:
  - Specialized "Characterization Firmware" on the RP2040 that sweeps the `clk` frequency.

#### Test Procedure
1. **Power Baseline**: Measure static power with `ena=0`.
2. **Frequency Sweep**: Increase frequency from 10MHz to 100MHz (or until failure) while running a continuous dot-product loop.
3. **Signature Analysis**: Collect `uo_out` patterns and verify them against the golden vectors at each frequency step.
4. **Efficiency Calculation**: Derive Energy-per-Operation ($\text{pJ/MAC}$).

### 7.9. Oscilloscope Measurements (Status: **PLANNED**)

To gain deeper insights into the physical behavior, the following measurements are performed on the TT DevKit:

| Measurement | Point | Purpose |
|-------------|-------|---------|
| **Latency** | `clk` vs `uo_out[7]` | Measure exact cycle-to-output delay and jitter. |
| **I/O Setup/Hold** | `ui_in` vs `clk` | Verify timing margins at high frequencies. |
| **Power Signature** | VCC Pin (AC coupled) | Observe the current spikes during the `STREAM` phase vs `IDLE` to correlate switching activity. |
| **Signal Integrity** | `uio[7:0]` | Check for crosstalk or ground bounce during high-speed switching of bidirectional pins. |

### 7.10. Continuous Integration (Status: **COMPLETED**)
- Every commit triggers a full suite of cocotb tests.
- Automated generation of coverage reports (Line, Toggle, FSM).
- Performance regression tracking (Cycle count per MAC).
