# Project Roadmap: OCP MX Streaming MAC Unit

This document centralizes the open issues and development roadmaps across the project. It tracks the evolution from a standalone MAC unit to a fully integrated RISC-V vector accelerator.

## 1. Architectural Refactoring & Infrastructure Prep
- [x] **Step 8.1: [Refactor] Decouple Output Multiplexer**: Separate the 8-bit serialization logic in `src/project.v` (common to both fixed-point and future Float32 results) from the protocol-level output gating to simplify the integration of the `fixed_to_float` path.
- [x] **Step 8.2: [Refactor] Standardize Probing Interface**: Reorganize the `probe_data` multiplexer and `SUPPORT_DEBUG` block in `src/project.v` to facilitate the future addition of internal probes for the F2F engine (e.g., LZC output, normalization shifts).
- [x] **Step 8.3: [Refactor] Accumulator Port Expansion**: Modify the `accumulator` module and its instantiation in `src/project.v` to explicitly expose the full internal width (preparing for the 40-bit upgrade) to the top-level for direct connection to the F2F engine, bypassing the serial shift logic.

## 2. Numerical Precision & FP32 Compliance
Address the gaps identified in the `docs/FP32_AUDIT.md` to ensure full compliance with OCP MX and IEEE 754 expectations.

- [x] **Step 9: [Infra] Parameterize Datapath Widths**: Unify `ALIGNER_WIDTH` and `ACCUMULATOR_WIDTH` to 40 bits across `src/project.v`, `src/accumulator.v`, and `src/fp8_aligner.v`. Update serialization logic to extract the appropriate 32-bit window (maintaining S23.8 mapping for backward compatibility) and verify that existing fixed-point tests pass.
- [x] **Step 10: [Datapath] 16-bit Fractional Alignment**: Shift the internal binary point from bit 8 to bit 16 ($2^0$) in the aligner and accumulator. Verify that FP8 subnormal products (e.g., $2^{-9}$) are now preserved in the accumulator instead of being truncated, and ensure consistency with the Step 9 extraction window.
- [x] **Step 11: [F2F] Leading Zero Count (LZC40) Module**: Implement a 40-bit LZC module to determine the normalization shift required for Float32 conversion and verify it with a dedicated unit test.
- [x] **Step 12: [F2F] Sign-Magnitude Extraction**: Implement logic to extract the sign bit and calculate the 39-bit absolute magnitude of the signed 40-bit accumulator.
- [x] **Step 13: [F2F] Normalization Barrel Shifter**: Design a shifter that uses the LZC40 output to left-justify the accumulator magnitude, preparing it for mantissa extraction.
- [x] **Step 14: [F2F] Base Exponent Estimation**: Implement logic to calculate the initial IEEE 754 biased exponent from the LZC result, accounting for the S23.16 fixed-point offset.
- [x] **Step 15: [F2F] Float32 Underflow Detection**: Add hardware flags to identify when the magnitude is too small for a normal Float32 result ($E_{biased} \le 0$).
- [x] **Step 16: [F2F] Subnormal Mantissa Alignment**: Implement a bypass path in the normalizer to produce correctly aligned subnormal mantissas when the underflow flag is active.
- [x] **Step 17: [F2F] Mantissa Extraction**: Extract the 23-bit fractional mantissa from the normalized result, ensuring the implicit '1' is handled correctly for normal values.
- [x] **Step 18: [F2F] Rounding - Guard/Sticky Bit Logic**: Implement logic to capture Guard, Round, and Sticky (GRS) bits from the shifter to support bit-accurate IEEE 754 rounding.
- [x] **Step 19: [F2F] Rounding - RNE Implementation**: Implement a Round-to-Nearest-Even (RNE) incrementer for the 23-bit mantissa based on GRS bits.
- [x] **Step 20: [F2F] Exponent Post-Rounding Correction**: Add logic to increment the exponent if the mantissa rounding results in a carry-out (e.g., rounding `1.11...1` to `10.00...0`).
- [x] **Step 21: [F2F] Float32 Overflow Detection**: Detect when the final exponent $\ge 255$ and flag the result for Infinity saturation.
- [x] **Step 22: [F2F] Sign-Exponent-Mantissa Assembly**: Implement the final stage to pack the sign bit, 8-bit exponent, and 23-bit mantissa into a 32-bit Binary32 pattern.
- [x] **Step 23: [F2F] Special Value Muxing**: Integrate the existing `nan_sticky` and `inf_sticky` registers to override the F2F output with canonical OCP MX NaN/Inf bit patterns.
- [ ] **Step 24: [F2F] Fixed-to-Float Wrapper**: Encapsulate the LZC, shifter, and assembly logic into a standalone `src/fixed_to_float.v` module.
- [ ] **Step 25: [Integration] Protocol Update (Cycle 0)**: Update the FSM to sample a "Float32 Mode" bit from the Cycle 0 Metadata (e.g., `uio_in[4]`) and store it in a configuration register.
- [ ] **Step 26: [Integration] Output Mux & Hookup**: Integrate the F2F module into `src/project.v` and add a multiplexer to select between raw fixed-point and Float32 results based on the configuration bit.
- [ ] **Step 27: [Verification] Cocotb Float32 Reference Model**: Update `test/test.py` with a bit-accurate Float32 reference model and implement a `test_float32_basic` regression.
- [ ] **Step 28: [Verification] Final Compliance Validation**: Develop and run a comprehensive test suite targeting edge cases (subnormals, overflow-to-Inf, NaN propagation) to ensure 100% OCP MX and IEEE 754 compliance.

## 3. Verification & Benchmarking
- [ ] **Phase D: Benchmarking**: Perform gate-level power profiling and side-by-side area comparisons. ([details](docs/architecture/LNS_FP8_DESIGN.md#104-phase-d-benchmarking--physical-analysis))
- [ ] **Physical Verification**: Functional verification on FPGA (HIL) and silicon validation (Tiny Tapeout demo board). ([details](docs/architecture/MXFP8_CONCEPT.md#6-gaps-and-future-work))
- [ ] **LLM Serving Benchmarks**: Benchmark the system using `vLLM` methodologies for real-world utility. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#5-phase-4-robustness--benchmarking))

## 4. Bit-Serial Evolution (Tiny-Serial)
The goal is to achieve an ultra-minimal footprint (< 500 gates) by processing data one bit at a time, inspired by the SERV core.

- [ ] **Step 5.1: [Datapath] 1-bit Delay-Line Aligner**: Implement the core serial alignment logic using a delay-line approach. ([details](docs/architecture/OCP_MX_SERIAL.md#phase-2-bit-serial-module-integration))
- [ ] **Step 5.2: [Integration] Aligner Swap**: Integrate the serial aligner into the `Tiny-Serial` variant and verify functional parity. ([details](docs/architecture/OCP_MX_SERIAL.md#phase-2-bit-serial-module-integration))
- [ ] **Step 6.1: [Datapath] Circulating Shift Register Accumulator**: Implement the serial storage and 1-bit adder with carry-out FF. ([details](docs/architecture/OCP_MX_SERIAL.md#phase-2-bit-serial-module-integration))
- [ ] **Step 6.2: [Integration] Accumulator Swap**: Replace the parallel accumulator in the serial path and verify bit-serial accumulation. ([details](docs/architecture/OCP_MX_SERIAL.md#phase-2-bit-serial-module-integration))
- [ ] **Step 7.1: [Refactor] Serial Config Registers**: Convert format, rounding, and metadata registers to serial shift registers. ([details](docs/architecture/OCP_MX_SERIAL.md#phase-3-area-optimization--refinement))
- [ ] **Step 7.2: [Refactor] Serial Control Logic**: Optimize the FSM and pointers for bit-serial state management. ([details](docs/architecture/OCP_MX_SERIAL.md#phase-3-area-optimization--refinement))
- [ ] **Step 8: Final Area Benchmarking**: Target < 500 gates for the complete bit-serial implementation. ([details](docs/architecture/OCP_MX_SERIAL.md#phase-3-area-optimization--refinement))
- [ ] **Phase C: Serial Integration**: Swap the bit-serial multiplier into the Tiny-Serial variant and align timing. ([details](docs/architecture/LNS_FP8_DESIGN.md#103-phase-c-serial-integration--stretched-protocol))

## 5. RISC-V & ISA Integration
Integration with the SERV bit-serial CPU and compliance with the ZvfofpXmin concept.

- [ ] **Step 5.1.1: [ISA] Format & Scale Instructions**: Implement `MX.SETFMT` and `MX.LOADS`. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#2-phase-1-custom-scalar-extension-mxmac))
- [ ] **Step 5.1.2: [ISA] MAC Instruction**: Implement the packed `MX.MAC` instruction. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#2-phase-1-custom-scalar-extension-mxmac))
- [ ] **Step 5.1.3: [ISA] Read Instruction**: Implement `MX.READ` for accumulator retrieval. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#2-phase-1-custom-scalar-extension-mxmac))
- [ ] **Step 5.2.1: [CSR] vmxfmt Definition**: Implement the custom CSR bitfields and rounding control logic. ([details](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md#52-sub-step-1-csr-implementation))
- [ ] **Step 5.2.2: [Integration] SERV CSR Bridge**: Integrate CSR access via SERV's extension interface. ([details](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md#52-sub-step-1-csr-implementation))
- [ ] **VRF-to-Stream Bridge**: Hardware shim to automate the 41-cycle OCP protocol from the Vector Register File. ([details](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md#53-sub-step-2-vrf-to-stream-bridge))
- [ ] **Tightly-Coupled Snooping**: Optimize area by snooping SERV's internal data streams directly. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#4-phase-3-tightly-coupled-snooping-variant-b))
- [ ] **RVV 1.0 Compliance**: Support `vstart` and `vl` for standard vector compliance. ([details](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md#55-sub-step-4-rvv-10-compliance))

## 6. Numerical Robustness & Optimization
- [ ] **Dynamic Block Size**: Allow parameterization of the block size $k$ beyond the fixed 32/16 elements. ([details](docs/architecture/MXFP8_CONCEPT.md#6-gaps-and-future-work))

---
*Last updated: March 2025*
