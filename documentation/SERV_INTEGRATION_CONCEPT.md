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
- **Interface**:
    - `o_ext_rs1` -> `ui_in` (via a small adapter that streams 4 bytes over 32 cycles).
    - `o_ext_rs2` -> `uio_in` (via the same adapter).
- **Control**: SERV raises `o_mdu_valid` (or a custom valid signal). The OCP MX unit processes the data and returns the 32-bit result on `i_ext_rd` while strobing `i_ext_ready`.
- **Pros**: Clean separation, compliant with SERV's MDU extension pattern.
- **Cons**: Requires 32-bit parallel buffers at the boundary.

### Variant B: Internal Snooping (Tightly Coupled)
This variant taps into the 1-bit streams of SERV's register file.

- **Mechanism**: Instead of waiting for 32-bit parallel values, the OCP MX unit snoops the `o_rdata0` and `o_rdata1` 1-bit streams from the `serv_rf_if`.
- **Interface**: The OCP MX unit acts as a 1-bit serial consumer, accumulating bits as they are read from the RF.
- **Pros**: Eliminates 32-bit parallel registers, saving ~1000 gates across the system.
- **Cons**: High coupling; requires modifying `serv_state` to handle the OCP MX operation's multi-cycle latency.

### Variant C: Memory-Mapped Peripheral (Bus-based)
Integration via the Wishbone DBUS.

- **Mechanism**: The OCP MX unit is placed on the Wishbone bus as a slave.
- **Interface**: The CPU uses `sw` (store word) to load scales and elements into the unit and `lw` (load word) to read the result.
- **Protocol**: Leverages the existing "Stretched Protocol" where the unit signals `i_dbus_ack` only after the required number of internal cycles have passed.
- **Pros**: Simplest software model; no changes to SERV core.
- **Cons**: Highest latency due to bus overhead.

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

- **Alignment**: By setting `SERIAL_K_FACTOR = 1` or `8`, we can synchronize the OCP MX unit to the SERV stage.
- **Burst Processing**: When `SUPPORT_INPUT_BUFFERING` is enabled, the unit can buffer 16 bytes while the CPU is fetching the next set of instructions, effectively overlapping I/O and computation.

## 6. Implementation Recommendation
For a 1x1 Tiny Tapeout tile, **Variant B (Internal Snooping)** combined with **Tiny-Serial (K=8)** is recommended. This setup provides the smallest possible footprint for an AI-accelerated RISC-V core by sharing the bit-serial infrastructure for both general-purpose and tensor arithmetic.
