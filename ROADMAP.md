# Project Roadmap: OCP MX Streaming MAC Unit

This document tracks the evolution from a standalone MAC unit to a fully integrated RISC-V vector accelerator.

## 1. Bit-Serial Evolution (Tiny-Serial)
The goal is to achieve an ultra-minimal footprint (< 500 gates) by processing data one bit at a time, inspired by the SERV core.

- [x] **Step 4.1: [Datapath] Serial Aligner & Accumulator**: Implement individual modules (`fp8_aligner_serial`, `accumulator_serial`).
- [x] **Step 4.2: [Datapath] Serial LNS Multiplier**: Implement `fp8_mul_serial_lns`.
- [x] **Step 4.3: [Integration] Serial Input Buffering**: Implement 8-bit shift registers to feed the serial datapath.
- [x] **Step 4.4: [Integration] Multiplier Swap**: Connect `fp8_mul_serial_lns` in the top-level serial path.
- [ ] **Step 4.5: [Integration] Aligner Swap**: Connect `fp8_aligner_serial` and align timing.
- [ ] **Step 4.6: [Integration] Accumulator Swap**: Replace the parallel accumulator in the serial path.
- [ ] **Step 4.7: [Integration] Serial-to-Parallel Handoff**: Connect the serial accumulator's parallel output to the top-level result capture.
- [ ] **Step 4.8: [Verification] Serial Parity**: Verify functional parity between parallel and serial variants.
- [ ] **Phase C: Serial Integration (Advanced)**: Swap format, rounding, and metadata registers to serial shift registers for area optimization.

## 2. RISC-V & ISA Integration
Integration with the SERV bit-serial CPU and compliance with the ZvfofpXmin concept.

- [ ] **Step 5.1.1: [ISA] Format & Scale Instructions**: Implement `MX.SETFMT` and `MX.LOADS`. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#2-phase-1-custom-scalar-extension-mxmac))
- [ ] **Step 5.1.2: [ISA] MAC Instruction**: Implement the packed `MX.MAC` instruction. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#2-phase-1-custom-scalar-extension-mxmac))
- [ ] **Step 5.1.3: [ISA] Read Instruction**: Implement `MX.READ` for accumulator retrieval. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#2-phase-1-custom-scalar-extension-mxmac))
- [ ] **Step 5.2.1: [CSR] vmxfmt Definition**: Implement the custom CSR bitfields and rounding control logic. ([details](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md#52-sub-step-1-csr-implementation))
- [ ] **Step 5.2.2: [Integration] SERV CSR Bridge**: Integrate CSR access via SERV's extension interface. ([details](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md#52-sub-step-1-csr-implementation))
- [ ] **VRF-to-Stream Bridge**: Hardware shim to automate the 41-cycle OCP protocol from the Vector Register File. ([details](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md#53-sub-step-2-vrf-to-stream-bridge))
- [ ] **Tightly-Coupled Snooping**: Optimize area by snooping SERV's internal data streams directly. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#4-phase-3-tightly-coupled-snooping-variant-b))
- [ ] **RVV 1.0 Compliance**: Support `vstart` and `vl` for standard vector compliance. ([details](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md#55-sub-step-4-rvv-10-compliance))

## 3. Verification & Benchmarking
- [ ] **Phase D: Benchmarking**: Perform gate-level power profiling and side-by-side area comparisons.
- [ ] **Physical Verification**: Functional verification on FPGA (HIL) and silicon validation (Tiny Tapeout demo board).
- [ ] **LLM Serving Benchmarks**: Benchmark the system using `vLLM` methodologies for real-world utility.

---

## Completed Milestones

### Architectural Refactoring & Infrastructure Prep
- [x] **Step 8.1: [Refactor] Decouple Output Multiplexer**
- [x] **Step 8.2: [Refactor] Standardize Probing Interface**
- [x] **Step 8.3: [Refactor] Accumulator Port Expansion**

### Numerical Precision & FP32 Compliance
- [x] **Step 9: [Infra] Parameterize Datapath Widths** (40-bit upgrade)
- [x] **Step 10: [Datapath] 16-bit Fractional Alignment**
- [x] **Step 11: [F2F] Leading Zero Count (LZC40) Module**
- [x] **Step 12-23: [F2F] Sign-Magnitude to Assembly stages**
- [x] **Step 24: [F2F] Fixed-to-Float Wrapper**
- [x] **Step 25-26: [Integration] Protocol Update & Output Mux**
- [x] **Step 27-28: [Verification] Cocotb Reference Model & Compliance Validation**

---
*Last updated: March 2025*
