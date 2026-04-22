# Project Roadmap: OCP MX Streaming MAC Unit

This document centralizes the open issues and development roadmaps across the project. It tracks the evolution from a standalone MAC unit to a fully integrated RISC-V vector accelerator.

## 1. Bit-Serial Evolution (Tiny-Serial)
The goal is to achieve an ultra-minimal footprint (< 500 gates) by processing data one bit at a time, inspired by the SERV core.

- [ ] **Step 5: Bit-Serial Aligner**: Replace parallel barrel shifter with a serial shifter/delay-line based aligner. ([details](docs/architecture/OCP_MX_SERIAL.md#phase-2-bit-serial-module-integration))
- [ ] **Step 6: Bit-Serial Accumulator**: Replace 32-bit parallel accumulator with a circulating shift register and a 1-bit adder. ([details](docs/architecture/OCP_MX_SERIAL.md#phase-2-bit-serial-module-integration))
- [ ] **Step 7: Register Pruning**: Convert internal state registers to bit-serial shift registers. ([details](docs/architecture/OCP_MX_SERIAL.md#phase-3-area-optimization--refinement))
- [ ] **Step 8: Final Area Benchmarking**: Target < 500 gates for the complete bit-serial implementation. ([details](docs/architecture/OCP_MX_SERIAL.md#phase-3-area-optimization--refinement))
- [ ] **Phase C: Serial Integration**: Swap the bit-serial multiplier into the Tiny-Serial variant and align timing. ([details](docs/architecture/LNS_FP8_DESIGN.md#103-phase-c-serial-integration--stretched-protocol))

## 2. RISC-V & ISA Integration
Integration with the SERV bit-serial CPU and compliance with the ZvfofpXmin concept.

- [ ] **Custom Scalar Extension (MX.MAC)**: Implement base OCP-MX-V ISA using SERV's extension interface. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#2-phase-1-custom-scalar-extension-mxmac))
- [ ] **CSR Implementation**: Implement the `vmxfmt` custom CSR for format and rounding control. ([details](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md#52-sub-step-1-csr-implementation))
- [ ] **VRF-to-Stream Bridge**: Hardware shim to automate the 41-cycle OCP protocol from the Vector Register File. ([details](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md#53-sub-step-2-vrf-to-stream-bridge))
- [ ] **Tightly-Coupled Snooping**: Optimize area by snooping SERV's internal data streams directly. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#4-phase-3-tightly-coupled-snooping-variant-b))
- [ ] **RVV 1.0 Compliance**: Support `vstart` and `vl` for standard vector compliance. ([details](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md#55-sub-step-4-rvv-10-compliance))

## 3. Numerical Robustness & Optimization
- [ ] **Dynamic Block Size**: Allow parameterization of the block size $k$ beyond the fixed 32/16 elements. ([details](docs/architecture/MXFP8_CONCEPT.md#6-gaps-and-future-work))

## 4. Verification & Benchmarking
- [ ] **Phase D: Benchmarking**: Perform gate-level power profiling and side-by-side area comparisons. ([details](docs/architecture/LNS_FP8_DESIGN.md#104-phase-d-benchmarking--physical-analysis))
- [ ] **Physical Verification**: Functional verification on FPGA (HIL) and silicon validation (Tiny Tapeout demo board). ([details](docs/architecture/MXFP8_CONCEPT.md#6-gaps-and-future-work))
- [ ] **LLM Serving Benchmarks**: Benchmark the system using `vLLM` methodologies for real-world utility. ([details](docs/integration/VMXDOTP_SERV_ROADMAP.md#5-phase-4-robustness--benchmarking))

## 5. Numerical Precision & FP32 Compliance
Address the gaps identified in the `FP32_AUDIT.md` to ensure full compliance with OCP MX and IEEE 754 expectations.

- [x] **Step 9: Wide Accumulator (40-bit)**: Increase internal accumulator width to 40 bits with 16 fractional bits to preserve subnormal precision. ([details](FP32_AUDIT.md#4-remediation-plan-technical))
- [ ] **Step 10: Hardware F2F Engine**: Implement a Leading Zero Count (LZC) and normalizer to convert the 40-bit fixed-point result to an IEEE 754 Float32 bit pattern. ([details](FP32_AUDIT.md#4-remediation-plan-technical))
- [x] **Step 11: Dynamic Aligner Range**: Update the `fp8_aligner` to support the increased dynamic range of the 40-bit accumulator and handle subnormal alignment correctly. ([details](FP32_AUDIT.md#4-remediation-plan-technical))
- [ ] **Step 12: Float32 Sticky Exceptions**: Implement hardware latching for NaN/Inf in the fixed-to-float path to ensure bit-accurate Float32 exception handling. ([details](docs/architecture/NAN_INF_PROPAGATION.md))

---
*Last updated: March 2025*
