# Roadmap: OCP MX Streaming MAC Unit Implementation

This roadmap outlines the incremental development of the OCP MXFP8 Streaming MAC Unit, following a test-driven approach.

## Phase 1: Baseline MXFP8 Implementation

### Step 1: Protocol Skeleton & FSM (Status: **COMPLETED**)
- **Goal**: Establish the 38-cycle operational protocol.
- **Details**: Implemented a 6-bit cycle counter and FSM (IDLE, LOAD_SCALE, STREAM, OUTPUT).
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

### Step 8: Integer Support (MXINT8) & Symmetric Range
- **Goal**: Support 8-bit integer elements (MXINT8).
- **Tasks**:
  - Implement MXINT8 multiplication path (implicit $2^{-6}$ scale).
  - Add optional symmetric clamping for -128.

### Step 9: Advanced Numerical Control (Rounding & Overflow)
- **Goal**: Implement optional rounding modes and configurable overflow methods.
- **Tasks**:
  - Add Truncate, Round-to-Plus-Infinity, and Round-to-Minus-Infinity modes.
  - Support configurable overflow methods (Wrapping vs Saturation).

### Step 10: Mixed-Precision Operations
- **Goal**: Enable independent format selection for Operand A and Operand B.
- **Tasks**:
  - Decouple format selection logic.
  - Update datapath to handle mixed exponent ranges.

### Step 11: Hardware-Accelerated Shared Scaling
- **Goal**: Apply shared scales ($X_A, X_B$) in hardware.
- **Tasks**:
  - Implement 32-bit shift logic to apply $2^{(X_A-127) + (X_B-127)}$ to the accumulator result.
  - Update protocol to output the fully scaled result.

### Step 12: Throughput Optimization & Scale Compression
- **Goal**: Maximize performance and efficiency.
- **Tasks**:
  - Pipeline the multiplier/accumulator datapath.
  - Implement Scale Compression for multi-block streams.
