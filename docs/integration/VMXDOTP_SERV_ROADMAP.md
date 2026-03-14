# Roadmap: VMXDOTP Integration for RISC-V SERV Core

This roadmap defines the architectural integration of the **VMXDOTP (Vector Microscaling Dot Product)** engine into the **SERV** bit-serial RISC-V core. It focuses on achieving extreme area efficiency for AI acceleration in Tiny Tapeout tiles.

## 1. Goal: The "Stretched" Bit-Serial Pipeline
The primary goal is to align the 32-cycle execution window of the SERV core with a 32-cycle bit-serial dot product of four packed 8-bit elements.

- **CPU**: SERV (Processes 1 bit/cycle).
- **Accelerator**: OCP MX-V (Processes 1 bit/cycle, $K=8$).
- **Instruction**: `vdot.mx` (custom vectorized opcode).

## 2. Phase 1: Custom Scalar Extension (MX.MAC)
Implement the base **OCP-MX-V** ISA as a scalar extension to SERV.

- **Mechanism**: Use SERV's **Extension Interface (Variant A)**.
- **Opcode**: `0x0b` (custom-0).
- **Instructions**:
  - `MX.SETFMT rs1`: Configure format and rounding.
  - `MX.LOADS rs1, rs2`: Load shared scales.
  - `MX.MAC rs1, rs2`: Perform 4 MACs (packed 8-bit elements).
  - `MX.READ rd`: Retrieve 32-bit accumulator.
- **Hardware**: Parallel-to-Serial adapter between SERV's 32-bit `o_ext_rs` ports and the OCP MX unit's 8-bit streaming ports.

## 3. Phase 2: Vectorized Bridge (ZvfofpXmin)
Expand the scalar logic to support true vector instructions and the **VMXDOTP** paper recommendations.

- **Instruction**: `vdot.mx v1, v2, v3`.
- **Bridge Unit**: Implement a hardware shim that automates the 41-cycle OCP protocol.
- **State Management**:
  - Integrate **MX+ (Phase 1-3)** logic to handle outliers by repurposing exponent bits.
  - Manage `bm_index` loading during the Scale Loading phase (Cycles 1-2).
- **Compliance**: Map configuration to the `vmxfmt` CSR.

## 4. Phase 3: Tightly-Coupled Snooping (Variant B)
Optimize area by removing 32-bit parallel buffers and snooping the RF directly.

- **Area Target**: Fit the entire SERV + MAC unit into a **1x1 Tiny Tapeout tile**.
- **Execution**:
  - Snoop SERV's 1-bit `o_rdata0` and `o_rdata1` streams.
  - Synchronize with SERV's `cnt[4:0]` counter.
  - Trigger `strobe` every 8 cycles to initiate bit-serial MAC on the current element pair.
- **Pipelining**: Enable **Stretched Protocol** where `SERIAL_K_FACTOR = 8`.

## 5. Phase 4: Robustness & Benchmarking
Ensure the implementation adheres to the shared-scale rules and handles exceptions.

- **Special Values**: Implement sticky registers for NaN/Infinity propagation as defined in `../architecture/LNS_FP8_DESIGN.md`.
- **LLM Serving**: Benchmark the system using the `vLLM` and `lm-evaluation-harness` methodologies described in the VMXDOTP paper.
- **Verification**: Run the full `test/test_lns_robustness.py` and `test/test_short_protocol.py` suite on the integrated core.

## 6. Summary of Key Parameters
| Parameter | Value | Description |
|:---|:---|:---|
| `SUPPORT_SERIAL` | 1 | Enable bit-serial multiplier core. |
| `SERIAL_K_FACTOR`| 8 | Align element processing with SERV bit-serial cycles. |
| `SUPPORT_MX_PLUS`| 1 | Enable outlier precision enhancement. |
| `BLOCK_SIZE` | 32 | Standard OCP MX block size. |
| `ISA_EXT` | OCP-MX-V | Custom RISC-V extension. |
