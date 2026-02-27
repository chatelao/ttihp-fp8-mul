# Roadmap: OCP MX Streaming MAC Unit Implementation

This roadmap outlines the incremental development of the OCP MXFP8 Streaming MAC Unit, following a test-driven approach.

## Phase 1: Baseline MXFP8 Implementation

### Step 1: Protocol Skeleton & FSM (Status: **COMPLETED**)
- **Goal**: Establish the 41-cycle operational protocol.
- **Details**: Implemented a 6-bit cycle counter and FSM (IDLE, LOAD_SCALE, STREAM, OUTPUT). Updated to 40 cycles to support pipelined datapath.
- **Verification**: Cocotb tests verify state transitions and I/O timing.

### Step 2: MXFP8 Multiplier Core (Status: **COMPLETED**)
- **Goal**: Implement combinatorial FP8 multiplication logic.
- **Refinement (Review findings)**: Refactored to align with OCP MX v1.0 (flush subnormals, support E5M2, simplify IEEE-754 logic).
- **Verification**: Exhaustive 256x256 unit tests against Python model.

### Step 3: Product Alignment (Status: **COMPLETED**)
- **Goal**: Align the floating-point product to a 32-bit fixed-point format.
- **Details**: Implemented a barrel shifter with saturation logic (clamps to 32-bit signed range).
- **Verification**: Unit tests for wide exponent range coverage.

### Step 4: Accumulator Unit (Status: **COMPLETED**)
- **Goal**: Maintain a running sum of aligned products.
- **Details**: 32-bit signed accumulator with synchronous clear during scale loading.
- **Verification**: Summation accuracy tests for 32-element blocks.

### Step 5: Full Datapath Integration (Status: **COMPLETED**)
- **Goal**: Integrate all components into the top-level Tiny Tapeout module.
- **Details**: Connected FSM, Multiplier, Aligner, and Accumulator. Implemented result serialization.
- **Verification**: Full system-level verification of the 38-cycle protocol.

### Step 6: Physical Design & Gate-Level Simulation (Status: **IN PROGRESS**)
- **Goal**: Validate area, timing, and post-synthesis correctness.
- **Tasks**:
  - Run OpenLane/LibreLane synthesis and verify area utilization.
  - Run Gate-Level Simulation (GLS) to ensure timing closure and netlist correctness.
  - Generate GDS and verify against Tiny Tapeout constraints.

---

## Phase 2: Advanced OCP MX Features

### Step 7: Extended Floating Point Support (MXFP6 & MXFP4) (Status: **COMPLETED**)
- **Goal**: Support 6-bit and 4-bit floating point formats.
- **Details**:
  - Implemented decoding for E3M2 (Bias 3), E2M3 (Bias 1), and E2M1 (Bias 1).
  - Updated 38-cycle protocol to support 3-bit format selection during Cycle 1.
  - Unified datapath to handle variable exponent ranges and mantissa padding.

### Step 8: Integer Support (MXINT8) & Symmetric Range (Status: **COMPLETED**)
- **Goal**: Support 8-bit integer elements (MXINT8).
- **Details**:
  - Implemented signed 8x8 multiplication with implicit $2^{-6}$ scale (mapped to $2^{-4}$ alignment shift).
  - Added support for both standard INT8 and symmetric INT8 (clamping -128 to -127).
- **Verification**: Dedicated test cases for both INT8 variants and randomized testing.

### Step 9: Advanced Numerical Control (Rounding & Overflow) (Status: **COMPLETED**)
- **Goal**: Implement optional rounding modes and configurable overflow methods.
- **Details**:
  - Implemented four rounding modes: Truncate (00), Ceil (01), Floor (10), and Round-to-Nearest-Ties-to-Even (11).
  - Added configurable overflow methods: Saturation (0) vs. Wrapping (1), applied to both the aligner and the 32-bit accumulator.
  - Configuration sampled from `uio_in[5:3]` during Cycle 1 of the protocol.
  - Optimized aligner logic and pipelined the datapath to meet 27MHz timing for Gowin.
- **Verification**: Targeted tests for rounding bit-accuracy and saturation/wrap behavior.

### Step 10: Mixed-Precision Operations (Status: **COMPLETED**)
- **Goal**: Enable independent format selection for Operand A and Operand B.
- **Details**:
  - Decoupled format selection logic for A and B.
  - Implemented unified exponent sum formula to handle mixed FP/INT precision.
  - Updated 41-cycle protocol to sample `format_a` (Cycle 1) and `format_b` (Cycle 2).
- **Verification**: New mixed-precision and randomized test cases in `test/test.py`.

### Step 11: Hardware-Accelerated Shared Scaling (Status: **COMPLETED**)
- **Goal**: Apply shared scales ($X_A, X_B$) in hardware.
- **Details**:
  - Reused the `fp8_aligner` to apply the shared scale $2^{(X_A-127) + (X_B-127)}$ to the 32-bit accumulator.
  - Optimized the 41-cycle protocol by removing a pipeline stage to ensure the fully scaled result is ready for serialization starting at cycle 36.
- **Verification**: New test cases in `test/test.py` verify accuracy for varying shared scales and randomized vectors.

### Step 12: Throughput Optimization & Scale Compression (Status: **COMPLETED**)
- **Goal**: Maximize performance and efficiency.
- **Details**:
  - Implemented a pipeline stage after the multiplier to break the critical path to the aligner/accumulator.
  - Updated the operational protocol to 41 cycles (0-40) to accommodate the pipeline flush while maintaining registered outputs.
  - Implemented "Fast Start" (Scale Compression) allowing the reuse of previous scales/formats by jumping from IDLE to STREAM.
- **Verification**: Updated Python reference model and protocol verification script.

---

## Phase 3: Rigorous Verification & Optimization

### Step 13: Comprehensive Coverage-Driven Verification (Status: **COMPLETED**)
- **Goal**: Achieve 100% functional and code coverage for all formats.
- **Details**:
  - Implemented a functional coverage collector in `test/test_coverage.py` using `cocotb-coverage`.
  - Achieved 100% cross-coverage for all format combinations, rounding modes, and overflow settings.
  - Verified edge cases including NaNs/Infinities (E5M2), subnormal flushing, and saturation boundaries.
  - Synchronized unit tests for `fp8_aligner` to match the updated 32-bit pipelined interface.

### Step 14: Formal Protocol Proofs (Status: **COMPLETED**)
- **Goal**: Mathematically prove the correctness of the 41-cycle FSM.
- **Details**:
  - Defined formal properties using SystemVerilog Assertions (SVA) within `src/project.v`.
  - Verified FSM state transitions, cycle count progression, and "Fast Start" logic.
  - Proved register stability and output gating/serialization correctness.
  - Successfully proved all properties using SymbiYosys and Z3 with k-induction.

### Step 15: Power & Performance Characterization (Status: **COMPLETED**)
- **Goal**: Evaluate the MAC unit's efficiency.
- **Details**:
  - Achieved a throughput of 0.7805 MACs/cycle (32 MACs per 41-cycle block).
  - Synthesized cell count: 3784 cells (approx. 104k cells/mm² in 1x2 tile).
  - Theoretical performance: 42.15 MFLOPS @ 27MHz, 156.10 MFLOPS @ 100MHz.
  - Implemented high-switching activity test suite for power signature analysis.
- **Verification**: Dedicated `test/test_performance.py` and `test/analyze_performance.py` scripts.

### Step 16: Hardware-in-the-Loop (HIL) Validation
- **Goal**: Cross-verify RTL behavior on the Tang Nano 9K FPGA.
- **Tasks**:
  - Develop a serial-to-parallel interface for high-throughput hardware testing.
  - Compare FPGA results bit-for-bit with the Python reference model.

### Step 17: Test on the TT Dev Kit
- **Goal**: Verify the design on the [Tiny Tapeout Development Kit](https://store.tinytapeout.com/products/FPGA-Development-Kit-p813805747).
- **Tasks**:
  - Deploy the bitstream to the TT Dev Kit FPGA.
  - Validate the 41-cycle streaming protocol using real hardware I/O.

### Step 18: Final ASIC Silicon Validation
- **Goal**: Verify the fabricated OCP MX MAC Unit on the [TT Demo Board](https://github.com/TinyTapeout/tt-demo-pcb) using the TT Dev Kit.
- **Tasks**:
  - **Functional HIL Verification**: Use a Raspberry Pi Pico as a master controller to drive the 41-cycle streaming protocol, verifying results bit-accurately against the Python reference model.
  - **Oscilloscope Characterization**: Measure protocol latency (from LOAD_SCALE to serialization) and clock jitter on the hardware.
  - **Power Signature Analysis**: Analyze power consumption signatures during the STREAM phase using an oscilloscope to characterize the final silicon.
