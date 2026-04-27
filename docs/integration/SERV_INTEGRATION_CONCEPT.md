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

![SERV Variant A: Extension Interface](https://www.plantuml.com/plantuml/png/ZLHTZvf057tdLqnvqgGiqVPXiqcJPT6sfhfhG6txD1bWn4c76J8VMqtJ_zuxu2BQDLbU72_dd7iuzyAzDaGPMt6KJfCDtaJ9B7fSuSXxnqJERK7HpfXQtuMX8hzlIcPsDhEQgbmAGuMvoMKLrfm89n5eKt2MXV77OEbAwyKyh8WsL449nxAgfN2S6h2UDuz-FgrN-FjizHNFfr-cZvF1qFCCCvmsNj0CEfIA62O52j26A0QQABf3qpsqrgxi86fBSee6iQoLpAdMKe5C3FO84rJX1sb5GTHX0AQViPRvU-Gx-I0ZcXOebR4_H7yy15VdiCNcKj4Z66ufwiEV1sO2kCa8HyaiZOEDAoxRnbIZ4SgO2VD3pgaFBbhH_voGWjJW6sTSvhySdoZ2EUM1aK7QYaSjfBDsRa_H4Yiz0kg7SG0TKPAEK4BBng7TRXtnActSfutVGDCxjZMOov8rsHb5ISL4YUQkuhYVquNxIHrEerkNWKP6egTuYHO_hbifUauc5qRW54C4La6ghGw2e-NcAFVNknYPp6jSxO5sHAy5CqvbnSJX9TN1jq-tmuinBY9O00_a4ihnf3_vKyeIqxrnP__a-6LeGBx27FUOupSopxEMk2eiVYQS5KqWi4fAEbv3J4vxq3syPPW9XxrjMhN3EZPAJWlGmylhX7aNQZSkAx6qvXLyGrXtS-s_GApDeBWUmVfynruXKr8S_7RxPDQyM_TK5EuxyWy0)

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

![SERV Variant B: Internal Snooping](https://www.plantuml.com/plantuml/png/VPDTQzim58Rl_IlESZ4SY9jczA841atSP0jBcf2lRemX55jnn6p9I4TjGzb_tv7o1Litt-ZpVVMSL_ATHMxGLIKi1lCrM_Vcezx3alMZTr9bfSi5x11hssst3N--AYJktCPPOJAjK2YyodJLhakkl4LYCI_bfftU93C_jPgCsnMtA0nDiLHNjLPUKzFUA1htlarNI_OuMdvcuy6dmSDzt8mYb5YAm08ZEg4m7ALMaC2Q6qcUqE-61QCu8IkjQwaAY9Uos66vXrIxkXGv6QK4oAKIXlMrKpat-vYmdrYcZMX18voGKX_YarspqOJN2EWxeyPco-IMjiz58NqXC9I4DnesQ2xOXGr-j134Ly96eaKZU0MrqKyo5wRH_CEJ4iU0u5juxvazmTaohFlHu4LaBfIFXcS_Gw6PmkyttUiV11lzUhDAdTMiUc7FXjUrC6GpJMSm-Ne9w_6myaQr6Q_HXNZIGm_6kf1PA6ydjmWKWmqZNb7C5ZGpEKT-tUx0XbkH0x4IuLyb7vWkB2ibqViifTedn-JYBnzlctvoPdGch2Lx2ZEnXzL9BprKF1Sbkp_TomNuH0AniPrWqqb83WTpalvVr_6w3__M7U_ieZlTGmk42ediLGOBMT0xigGwoixxpm4uoQHgWPEQMY-y3STTdZGQlH77SrVdu4xlq6cc7K8y5zQL67YdjNyY91qAaUFEQ5ViFC6TKBd_qNu3)

- **Mechanism**: Instead of waiting for 32-bit parallel values, the OCP MX unit snoops the `o_rdata0` and `o_rdata1` 1-bit streams directly from the `serv_rf_if` (Register File Interface).
- **Interface**: The OCP MX unit acts as a 1-bit serial consumer.
    - **Bit-by-Bit Accumulation**: As bits are read from the RF during SERV's 32-cycle "Execute" phase, the OCP MX unit shifts them into its internal registers.
    - **Stretched Processing**: If `SERIAL_K_FACTOR=8`, the unit matches the 32-cycle window of SERV perfectly for a 4-byte transfer (4 elements x 8 bits/element = 32 bits).
- **Synchronization**: The unit uses SERV's internal `cnt[4:0]` execution cycle counter to synchronize the arrival of bits and the start of element processing.
- **Pros**: Eliminates 32-bit parallel registers at the interface, saving significant area (estimated ~1000 gates across the system).
- **Cons**: High coupling; requires internal knowledge of SERV's pipeline and state machine to handle multi-cycle latency.

#### Variant B: Snooping Logic & Timing
The OCP MX unit monitors the following signals from the SERV core:
- `o_rdata0`: 1-bit serial stream for `rs1`.
- `o_rdata1`: 1-bit serial stream for `rs2`.
- `cnt[4:0]`: SERV's execution cycle counter (0 to 31).
- `en`: High during the 32-cycle execution phase.

**Mapping Logic**:
Over the 32-cycle execution window, the OCP MX unit captures 4 elements per register:
- **Cycles 0-7**: Capture bits into **Element 0** buffer.
- **Cycles 8-15**: Capture bits into **Element 1** buffer.
- **Cycles 16-23**: Capture bits into **Element 2** buffer.
- **Cycles 24-31**: Capture bits into **Element 3** buffer.

As each 8-bit element is completed, the `strobe` signal in the OCP MX datapath is triggered, initiating the $K$-cycle bit-serial MAC operation for that element pair.

## 4. Proposed Custom ISA (OCP-MX-V)
To support OCP MX operations in RISC-V, we define a set of custom instructions using the `custom-0` (0x0b) opcode. All instructions follow the standard R-type format.

### 4.1. Instruction Encodings
The following table defines the bitfields for the OCP-MX-V extension:

| Instruction | Opcode | funct3 | funct7 | rs2 | rs1 | rd | Description |
|-------------|--------|--------|--------|-----|-----|----|-------------|
| `MX.SETFMT` | 0x0b   | 0x0    | 0x00   | 0x0 | src | dst| Set format/rounding mode from `rs1`. |
| `MX.LOADS`  | 0x0b   | 0x1    | 0x00   | src2| src1| 0x0| Load Shared Scale A (`rs1`) and B (`rs2`). |
| `MX.MAC`    | 0x0b   | 0x2    | 0x00   | src2| src1| 0x0| Stream 4+4 packed elements for MAC. |
| `MX.READ`   | 0x0b   | 0x3    | 0x00   | 0x0 | 0x0 | dst| Read 32-bit accumulator into `rd`. |

### 4.2. Register Bit-Mapping

![MX.SETFMT Bitfield](https://www.plantuml.com/plantuml/png/SoWkIImgISeiISjCpKdXCj0rib9myms9T-GorZMnKWZovJArKl0FS-Coir88S7JsvZAtKd2D2E6oq3Ks14gd5gSMbQMcS3cavgN03G40)

- **`MX.SETFMT`**: `rs1[2:0]` = format_a, `rs1[4:3]` = round_mode, `rs1[5]` = overflow_wrap, `rs1[6]` = packed_mode, `rs1[7]` = mx_plus_en.
- **`MX.MAC`**: `rs1` contains 4x 8-bit elements (A0-A3), `rs2` contains 4x 8-bit elements (B0-B3).

## 5. Synchronization & Stretched Protocol
SERV's execution stage is 32 cycles long. The OCP MX Tiny-Serial unit uses $K$ cycles per element.

- **Alignment**: By setting `SERIAL_K_FACTOR = 8`, a 4-byte packed register transfer (32 bits) perfectly matches the 32-cycle SERV execution window.
- **Burst Processing**: When `SUPPORT_INPUT_BUFFERING` is enabled, the unit can buffer 16 bytes while the CPU is fetching the next set of instructions, effectively overlapping I/O and computation.

## 6. Implementation Recommendation
For a 1x1 Tiny Tapeout tile, **Variant B (Internal Snooping)** combined with **Tiny-Serial (K=8)** is recommended. This setup provides the smallest possible footprint for an AI-accelerated RISC-V core by sharing the bit-serial infrastructure for both general-purpose and tensor arithmetic, avoiding the area overhead of parallel 32-bit interfaces.

## 7. Detailed Timing & Synchronization (K=8)
When `SERIAL_K_FACTOR=8`, the internal clock cycles of the OCP MX unit are aligned with SERV's 32-cycle execution phase.

| SERV Cycle (cnt) | OCP MX Element | OCP MX Internal Activity (K=8) |
|------------------|----------------|-------------------------------|
| 0                | Element 0      | Start Capture (Bit 0)         |
| 7                | Element 0      | End Capture (Bit 7)           |
| 8                | Element 1      | MAC Element 0 / Start Capture Bit 8 |
| 15               | Element 1      | End Capture (Bit 15)          |
| 16               | Element 2      | MAC Element 1 / Start Capture Bit 16|
| 23               | Element 2      | End Capture (Bit 23)          |
| 24               | Element 3      | MAC Element 2 / Start Capture Bit 24|
| 31               | Element 3      | End Capture (Bit 31)          |
| 32-39            | -              | MAC Element 3                 |

This alignment ensures that exactly 4 MAC operations are performed for every 32-bit register transfer instruction, maintaining a 1:1 ratio between CPU instruction throughput and MAC element throughput (in terms of architecture cycles).

## 8. Software Usage Example
The following C code snippet demonstrates how to perform a vector-vector dot product using the OCP-MX-V custom instructions on a SERV-based system.

```c
#include <stdint.h>

// Assembly Macros for OCP-MX-V (Opcode 0x0b)
#define MX_SETFMT(fmt) asm volatile (".insn r 0x0b, 0, 0, x0, %0, x0" :: "r"(fmt))
#define MX_LOADS(sa, sb) asm volatile (".insn r 0x0b, 1, 0, x0, %0, %1" :: "r"(sa), "r"(sb))
#define MX_MAC(va, vb)  asm volatile (".insn r 0x0b, 2, 0, x0, %0, %1" :: "r"(va), "r"(vb))
#define MX_READ(res)    asm volatile (".insn r 0x0b, 3, 0, %0, x0, x0" : "=r"(res))

void compute_dot_product(uint32_t* vec_a, uint32_t* vec_b, int len, uint32_t fmt, uint32_t sa, uint32_t sb) {
    uint32_t result;

    // 1. Configure the MAC unit
    MX_SETFMT(fmt);
    MX_LOADS(sa, sb);

    // 2. Perform 4 MACs per loop iteration (32-bit packed registers)
    for (int i = 0; i < len/4; i++) {
        MX_MAC(vec_a[i], vec_b[i]);
    }

    // 3. Read the 32-bit accumulated result
    MX_READ(result);
}
```

## 9. Comparison of Integration Variants

| Feature | Variant A: Extension | Variant B: Snooping |
|---------|----------------------|----------------------|
| **Logic Area** | Medium (+1000 gates for buffers) | **Minimal** (Uses core registers) |
| **Control Complexity**| Low (Standard MDU protocol) | High (Requires pipeline tracking) |
| **Throughput** | 1 element / K cycles | 1 element / K cycles |
| **Integration** | Tightly coupled (External) | **Fully Integrated** (Internal) |
| **Tile Target** | 1x2 Tiny Tapeout Tile | **1x1 Tiny Tapeout Tile** |

By choosing **Variant B** and **Tiny-Serial (K=8)**, the OCP-MX-V extension can be integrated into a SERV-based SoC with minimal silicon impact, enabling energy-efficient AI acceleration in ultra-constrained ASIC environments.
