# Roadmap: Incremental MXFP8 Implementation

This roadmap outlines a step-by-step approach to implementing the OCP MXFP8 Streaming MAC Unit. Each step combines RTL development with corresponding verification to ensure correctness at every stage.

## Step 1: Protocol Skeleton & FSM
- **Goal**: Establish the 38-cycle operational protocol.

### I/O Bit Mapping Tables

#### Table 1: Primary Input `ui_in`
| Phase | Cycles | Bits [7:0] | Function | Description |
|-------|--------|------------|----------|-------------|
| **IDLE** | 0 | `00000000` | N/A | No input accepted. |
| **LOAD_SCALE** | 1 | `X_A[7:0]` | **Scale A** | Shared UE8M0 scale for Tensor A. |
| **LOAD_SCALE** | 2 | `XXXXXXXX` | N/A | Ignored (Scale B on `uio_in`). |
| **STREAM** | 3-34 | `A_i[7:0]` | **Element A** | MXFP8 element (see Format table). |
| **OUTPUT** | 35-38 | `XXXXXXXX` | N/A | Ignored. |

#### Table 2: Bidirectional Input `uio_in`
| Phase | Cycles | Bits [7:0] | Function | Description |
|-------|--------|------------|----------|-------------|
| **IDLE** | 0 | `00000000` | N/A | No input accepted. |
| **LOAD_SCALE** | 1 | `XXXXXXXX` | N/A | Ignored. |
| **LOAD_SCALE** | 2 | `X_B[7:0]` | **Scale B** | Shared UE8M0 scale for Tensor B. |
| **STREAM** | 3-34 | `B_i[7:0]` | **Element B** | MXFP8 element (see Format table). |
| **OUTPUT** | 35-38 | `XXXXXXXX` | N/A | Input buffer isolated. |

#### Table 3: Element Bit Formats (MXFP8)
| Format | Sign (S) | Exponent (E) | Mantissa (M) | Notes |
|--------|----------|--------------|--------------|-------|
| **E4M3** | Bit 7 | Bits [6:3] | Bits [2:0] | Bias 7 |
| **E5M2** | Bit 7 | Bits [6:2] | Bits [1:0] | Bias 15 |

#### Table 4: Primary Output `uo_out`
| Phase | Cycles | Bits [7:0] | Function | Description |
|-------|--------|------------|----------|-------------|
| **IDLE** | 0 | `00000000` | Zero | Constant zero. |
| **LOAD/STREAM** | 1-34 | `00000000` | Zero | Constant zero during computation. |
| **OUTPUT** | 35 | `Acc[31:24]` | **Result Byte 3** | Accumulator MSB. |
| **OUTPUT** | 36 | `Acc[23:16]` | **Result Byte 2** | Accumulator Byte 2. |
| **OUTPUT** | 37 | `Acc[15:8]` | **Result Byte 1** | Accumulator Byte 1. |
| **OUTPUT** | 38 | `Acc[7:0]` | **Result Byte 0** | Accumulator LSB. |
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
