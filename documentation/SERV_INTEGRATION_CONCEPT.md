# Concept: Integrating OCP MX-PLUS into RISC-V SERV Core

## 1. Introduction
This document outlines the architectural synergy and integration strategies for combining the **OCP MX-PLUS (Tiny-Serial)** MAC unit with the **SERV** bit-serial RISC-V core. Both designs share a common philosophy: trading throughput for extreme area efficiency using bit-serial or low-bandwidth streaming datapaths.

## 2. Architectural Synergy
SERV and OCP MX-PLUS Tiny-Serial are naturally compatible due to their temporal execution models:
- **SERV**: Decomposes 32-bit RISC-V instructions into 32 one-bit cycles.
- **OCP MX-PLUS Tiny-Serial**: Decomposes OCP MX MAC operations into a "Stretched Protocol" where internal cycles are scaled by `SERIAL_K_FACTOR`.

By aligning these temporal windows, we can create an AI-capable RISC-V system that fits in a fraction of the area required by traditional parallel designs.

## 3. Integration Variants

### Variant A: Extension Interface (Coprocessor)
This is the most standard and least intrusive method. It uses SERV's built-in **Extension Interface**.

- **Mechanism**: SERV detects a custom R-type instruction and presents `rs1` and `rs2` as 32-bit parallel values on `o_ext_rs1` and `o_ext_rs2`.
- **Parallel-to-Serial Adapter**: A small wrapper module is required to bridge the 32-bit parallel interface to the OCP MX's 8-bit streaming ports.
    - **Buffer Phase**: The adapter captures the 32-bit values into registers during the first stage of the extension call.
    - **Streaming Phase**: It then shifts out 8 bits per cycle (or per $K$ cycles if `SUPPORT_SERIAL=1`) to `ui_in` and `uio_in`.
- **Interface**:
    - `o_ext_rs1` (32-bit) -> Adapter -> `ui_in` (8-bit).
    - `o_ext_rs2` (32-bit) -> Adapter -> `uio_in` (8-bit).
- **Control**: SERV raises `o_mdu_valid` (or a custom valid signal). The OCP MX unit processes the data and returns the 32-bit result on `i_ext_rd` while strobing `i_ext_ready`.
- **Pros**: Clean separation, compliant with SERV's MDU extension pattern.
- **Cons**: Requires 32-bit parallel buffers at the boundary, increasing area by ~1000 gates compared to purely serial variants.

### Variant B: Internal Snooping (Tightly Coupled)
This variant taps into the 1-bit streams of SERV's register file, aligning with the bit-serial nature of both cores.

- **Mechanism**: Instead of waiting for 32-bit parallel values, the OCP MX unit snoops the `o_rdata0` and `o_rdata1` 1-bit streams directly from the `serv_rf_if` (Register File Interface).
- **Interface**: The OCP MX unit acts as a 1-bit serial consumer.
    - **Bit-by-Bit Accumulation**: As bits are read from the RF during SERV's 32-cycle "Execute" phase, the OCP MX unit shifts them into its internal registers.
    - **Stretched Processing**: If `SERIAL_K_FACTOR=8`, the unit matches the 32-cycle window of SERV perfectly for a 4-byte transfer (4 elements x 8 bits/element = 32 bits).
- **Synchronization**: The unit uses SERV's internal `cnt[4:0]` execution cycle counter to synchronize the arrival of bits and the start of element processing.
- **Pros**: Eliminates 32-bit parallel registers at the interface, saving significant area (estimated ~1000 gates across the system).
- **Cons**: High coupling; requires internal knowledge of SERV's pipeline and state machine to handle multi-cycle latency.

## 4. Proposed Custom ISA (OCP-MX-V)
To support OCP MX operations in RISC-V, we define a set of custom instructions using the `custom-0` (0x0b) or `custom-1` (0x2b) opcodes.

| Instruction | Format | Description |
|-------------|--------|-------------|
| `MX.SETFMT rd, rs1` | R-Type | Sets the MX format and rounding mode (from `rs1`). |
| `MX.LOADS  rs1, rs2`| R-Type | Loads Shared Scale A (from `rs1`) and Scale B (from `rs2`). |
| `MX.MAC    rs1, rs2`| R-Type | Streams two 8-bit elements (packed in `rs1`, `rs2`) into the MAC unit. |
| `MX.READ   rd`      | R-Type | Reads the 32-bit accumulator result into `rd`. |

## 5. Synchronization & Stretched Protocol
SERV's execution stage is 32 cycles long. The OCP MX Tiny-Serial unit uses $K$ cycles per element.

- **Alignment**: By setting `SERIAL_K_FACTOR = 8`, a 4-byte packed register transfer (32 bits) perfectly matches the 32-cycle SERV execution window.
- **Burst Processing**: When `SUPPORT_INPUT_BUFFERING` is enabled, the unit can buffer 16 bytes while the CPU is fetching the next set of instructions, effectively overlapping I/O and computation.

## 6. Implementation Recommendation
For a 1x1 Tiny Tapeout tile, **Variant B (Internal Snooping)** combined with **Tiny-Serial (K=8)** is recommended. This setup provides the smallest possible footprint for an AI-accelerated RISC-V core by sharing the bit-serial infrastructure for both general-purpose and tensor arithmetic, avoiding the area overhead of parallel 32-bit interfaces.
