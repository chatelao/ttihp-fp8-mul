# Roadmap: Phase 2 - Optional & Advanced OCP MX Features

This second roadmap builds upon the baseline MXFP8 implementation (Steps 1-6) to incorporate all optional features and additional formats defined in the **OCP Microscaling Formats (MX) Specification v1.0**.

## Step 7: Extended Floating Point Support (MXFP6 & MXFP4)
- **Goal**: Expand the unit's versatility by supporting 6-bit and 4-bit floating point formats.
- **Code Tasks**:
  - Implement decoding logic for **MXFP6** (E3M2, E2M3) and **MXFP4** (E2M1).
  - Update the exponent bias handling to support the different biases of these smaller formats.
  - Implement zero-padding/sign-extension logic to feed these elements into the existing multiplier/aligner datapath.
- **Test Tasks**:
  - Extend the unit test suite to verify exhaustive bit-accurate multiplication for FP6 and FP4 formats.
  - Verify that underflow-to-zero logic works correctly for these formats.

## Step 8: Integer Support (MXINT8) & Symmetric Range
- **Goal**: Support 8-bit integer elements with scaling.
- **Code Tasks**:
  - Implement **MXINT8** multiplication path, treating operands as 2's complement integers with an implicit $2^{-6}$ scale.
  - Add a configuration bit to support **Symmetric INT8** (clamping -128 to -127) to maintain range symmetry as per specification "May" requirements.
- **Test Tasks**:
  - Verify MXINT8 dot product accuracy against a Python reference model.
  - Test the symmetric clamping logic for the -128 edge case.

## Step 9: Advanced Numerical Control (Rounding & Overflow)
- **Goal**: Implement optional rounding modes and configurable overflow methods.
- **Code Tasks**:
  - Implement additional rounding modes beyond `roundTiesToEven`: Round-to-Zero (Truncate), Round-to-Plus-Infinity, and Round-to-Minus-Infinity.
  - Add support for configurable **Overflow Methods** (e.g., optional Wrapping instead of Saturation for specific use cases).
- **Test Tasks**:
  - Create test vectors for edge-case rounding scenarios (ties) for all new modes.
  - Verify that the overflow flag/clamping logic correctly follows the configured method.

## Step 10: Mixed-Precision Operations
- **Goal**: Enable the MAC unit to process operands with different MX formats simultaneously.
- **Code Tasks**:
  - Decouple the format selection logic so that Operand A and Operand B can be configured independently (e.g., A=E4M3, B=E5M2).
  - Update the multiplier and aligner to handle mixed exponent ranges and mantissa widths.
- **Test Tasks**:
  - Run randomized tests with mixed-format pairs and verify results against a cross-format Python model.

## Step 11: Hardware-Accelerated Shared Scaling
- **Goal**: Move the application of shared scales ($X_A, X_B$) from software into the hardware datapath.
- **Code Tasks**:
  - Implement a 32-bit shift-and-add or multiplier unit to apply the $2^{X_A + X_B}$ scaling factor to the 32-bit accumulator result.
  - Update the I/O protocol to output the final normalized result instead of the raw sum.
- **Test Tasks**:
  - Verify that the hardware-scaled output matches the software-scaled results from Phase 1.

## Step 12: Throughput Optimization & Scale Compression
- **Goal**: Maximize performance and efficiency for multi-block data streams.
- **Code Tasks**:
  - Implement pipelining between the multiplier and accumulator to increase clock frequency.
  - Add support for **Scale Compression**, allowing multiple 32-element blocks to share or prune repeated scale factors.
  - Final GDS generation and timing closure for the fully-featured unit.
- **Test Tasks**:
  - Perform stress testing with continuous back-to-back 32-element blocks.
  - Verify that scale compression logic correctly maintains numerical integrity.
