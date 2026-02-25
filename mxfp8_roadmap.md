# Roadmap: Incremental MXFP8 Implementation

This roadmap outlines a step-by-step approach to implementing the OCP MXFP8 Streaming MAC Unit. Each step combines RTL development with corresponding verification to ensure correctness at every stage.

## Step 1: Protocol Skeleton & FSM
- **Goal**: Establish the 38-cycle operational protocol.
- **Code Tasks**:
  - Implement a 6-bit cycle counter in the top-level module.
  - Implement a Finite State Machine (FSM) with states: `IDLE`, `LOAD_SCALE`, `STREAM`, `OUTPUT`.
- **Test Tasks**:
  - Create a new cocotb test to verify that the FSM transitions correctly through all 38 cycles.
  - Verify that `uo_out` remains zero during the `STREAM` phase.

## Step 2: MXFP8 Multiplier Core (Combinatorial)
- **Goal**: Implement basic FP8 multiplication logic for a single pair of elements.
- **Code Tasks**:
  - Create a combinatorial multiplier module that handles sign XOR, exponent addition, and mantissa multiplication for E4M3/E5M2.
- **Test Tasks**:
  - Add unit tests to perform exhaustive testing of all 256x256 input combinations against a bit-accurate Python model.

## Step 3: Product Alignment (Barrel Shifter)
- **Goal**: Align the floating-point product to a common 32-bit fixed-point format for accumulation.
- **Code Tasks**:
  - Implement a barrel shifter that uses the resulting exponent to shift the mantissa product.
- **Test Tasks**:
  - Create unit tests to verify correct alignment across the full range of possible exponents.

## Step 4: Accumulator Unit
- **Goal**: Maintain a running sum of aligned products.
- **Code Tasks**:
  - Implement a 32-bit accumulator register and adder.
  - Ensure the accumulator resets at the start of a new block (`LOAD_SCALE` phase).
- **Test Tasks**:
  - Create unit tests to verify 32-element summation accuracy and handle potential overflow within the 32-element block.

## Step 5: Full Datapath Integration
- **Goal**: Integrate all components into the top-level Tiny Tapeout module.
- **Code Tasks**:
  - Connect the FSM, Multiplier, Aligner, and Accumulator in the main project file.
  - Implement the logic to shift out the 32-bit accumulator 8 bits at a time over the 4-cycle `OUTPUT` phase.
- **Test Tasks**:
  - Update the main testbench to perform full system-level verification of the 38-cycle MXFP8 protocol using randomized test vectors.

## Step 6: Physical Design & Gate-Level Simulation
- **Goal**: Validate area, timing, and post-synthesis correctness.
- **Tasks**:
  - Run OpenLane synthesis and verify area utilization targets the ~100 DFF estimate (within the 320 DFF tile limit).
  - Run Gate-Level Simulation (GLS) using the full system testbench to ensure timing closure.
