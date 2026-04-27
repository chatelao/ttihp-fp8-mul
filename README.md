![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg) [![Documentation Status](https://readthedocs.org/projects/ttihp-fp8-mul/badge/?version=latest)](https://ttihp-fp8-mul.readthedocs.io/en/latest/?badge=latest)

# Tiny Tapeout IHP 26a - OCP MXFP8 Streaming MAC Unit

This project implements a Streaming Multiply-Accumulate (MAC) Unit compatible with the OCP Microscaling Formats (MX) Specification (v1.0). It is designed to fit within a 2x2 Tiny Tapeout tile using the IHP SG13G2 PDK.

## Attributions

This project incorporates logic and concepts from several open-source resources:
- [fp8_mul](https://github.com/cchan/fp8_mul) by Clive Chan (Arithmetic logic).
- [Tiny Tapeout Verilog Template](https://github.com/TinyTapeout/ttihp-verilog-template) (Project structure).
- [OCP Microscaling Formats (MX) Specification v1.0](https://www.opencompute.org/documents/ocp-microscaling-formats-mx-v1-0-spec-final-pdf) (Numerical and Protocol Specification).

We gratefully acknowledge these contributions to the open-source hardware and AI communities.

## System Context

![System Context Diagram](https://www.plantuml.com/plantuml/png/~1dLTPZnf747xdLrHMaGKocBsyNaME5PR39W8MSSZE4sfw6kZipFIekoS6H_xlgUevMOPTARp0D5tNLryTyuUnJDiuyA7xE5dqlorMlM7dywmphlqYG-x7de2TjP7vhTtMxFkxhRIxU1qReRaAhGZjEww2TkIpa7IqZFLykMvtRrjJEbgEH-s06Iiq7gswAeXKI38HtgtLHfs_7fUBrTVXuijgrF_Sd_JgZPfvac74D0j02svPkFN5nuzh5OSUquTFd-3V6k1dWCRdyeU0wylQpsePye_9KEZL_v4s1_GwU4rq6NdCYeVqqjmUV56_o0rVDE5NUuZ4xwMZHhLCOguGI9yRjTfKQAF2-auPsuIBB_W5y-ponM3wkTE4iUHQaGcjV5_e9YWD2s7iMeHyHpgwEHIPsNh0-2eE9Ubyx4vX_6qmlOUvrO85Cjp2kDE59VuDzTkhEnWC32oKPNxZee4uE20gT6uC0kOh_aIUpSVmnbr2fw3-_WCfISGX_UHqg7FKOCdnY-w1-mB_SSyKuLrhZLwqmJb11mlD-9E1I2kBCVl0IS90VOwPGo-yzXJ_5rxZ7GP-QebSzDLMSjI44bR0cF4TXa6gyTfQXimgBPbF1yFUgD-4qMEdruJvOjRlZ9k0Z9qk5s0r2usqKeMcsXBcOoEtAossngcc9vY9hQHgS96ylyfYcgD9ZC5mXg4qOQDqm2p-29H7pnWO9kWj1C8ov0ux4nhMsSeLCsdSAMrXce4qef39KluZ0VeormcSHJRM0fD6Yi0f8aEvfPdmLxqZAqNQ_eo3gD1wK_8laSflbl5tMSvpV29JkdgCvKWnZyJw8Llx8fNxUPQLGUpdhEp5p6-DM8XfZtqh8ryAZUIyUucSdk2O1asM7oEXAHczz2X75EgNYGg2FeuY1DyaDTM-QzysOJXPt1Tvr2AATQICy43i4ojdI1Iiq7lIARUXt4ZkDEIULvgVOYV3Bk1J4tYGjZKNn6OOJURWqAmsX7wicCRUJhYcFi6KsTsP40CaA7A_2Ml9333lxzZO06No8D-2scoCE1iO9YLDvrH6miUKFIkElE2lMgx4mSTg3Vc1cBcb5bL7TdjDG6-nE14V-iaR5PGj4bW1fpdXNN6z2fJJ-wdISaJesCcrahBILLJR9czUPJ7pyTOHZw53HyXVx6DRaQUdciHc9pT9gJumhP4Ty-IWciB48MmCo9mVoD7wrs5lyQK1pWLAClO8ulOjgCZAGFvmLAZEioR_iq4pemTAtHkOCsmsJgxIWTa4--vYDcb2jpzgmc0qIteXl8Mkpu88bLGaEW_oo6e24nOjThdNOUOy1xd3UOofeda0zPlhb-1bdkV0dIUcElHuhd8CU9GzN8ym7XbQ1Hkv5ruhKlW0h31QZIXvYEGf-uSeKl6G_iJDqapHSHWIv2OEA0Zgj5KraWPGA4-sb6SiNXRMiuW7GdXhdBYl8YlsN4JaQevlFpj1FimKxfGM4S59VlCYaQtaJmSN7_quRXetMV0ZPlaEev-mINiORc2ZLK1bbpPEuxgK6xSuxJWYTQPDgN-4rj8JrFjZ6yKMk---Ch6FwKr4N1WqPE0xrZhGRcKYmQa5HyoYeyc-y9ovQLGbUmijjrktCBwCgt7zFGVr8TviA40iCVS7LZ2oz_hk_YLGDtAZieuq32dCmN3mw91C9LqZljlVkssixYPef_tGm7gSMarbcMnTWERFGBa-M86TSay-7cm-WCN-JANqzxXYSSGniSbtSOXh7wv64AkLYaztasN9H0d7cKl7SVKZcWdkoLPzl9IuZPKyu3u2gd7TmT4YGf8k2ntl9EDqZIAvMAuaYiHIuJVKkyc2UjcwRZnJKOQzMBrxrMgI_HEY7JE253bDi-CrixIg398TiesZ-ABiN-R1aLnrbnwZBaU1T3qxMSkARj6rsa4cq66Cbc5dy75BQu9hoPctlTBOBmOI3XjBvK5JC-Q5eR9JMRV9UddV5q4wZ9_rfK9ltfdSEimqYisnuYaojzXaTdBH4aEJHWb3Mbf3V1V8p1IyIj_74Yxcgw-1cm-jsqjyNxc-QbtVKk1_YD2Zjzt_0000)

*Source: [docs/diagrams/CONTEXT_DIAGRAM.PUML](docs/diagrams/CONTEXT_DIAGRAM.PUML)*

### Functional Block Overview

| Block | Component | Detailed Function & Mathematics |
| :--- | :--- | :--- |
| **FSM & Control** | Cycle Counter, State Machine, Config Regs | Orchestrates the 41-cycle protocol. Captures scales and metadata (Rounding, Overflow, LNS, MX+). Supports **Short Protocol** (Cycle 0) to bypass scale loading for weight-stationary kernels. |
| **Dual-Lane Multiplier** | Decoders, Significand Mul, Exponent Path | Decodes elements and calculates products. Supports **Mitchell's LNS Approximation**: <br> $(1+m_a)(1+m_b) \approx \begin{cases} 1 + m_a + m_b & m_a+m_b \lt 1 \\\\ 2(m_a + m_b) & m_a+m_b \ge 1 \end{cases}$ <br> Handles **MX+ Extended Mantissa**: $V(A_{BM}) = S \cdot 2^{E_{max} - \text{Bias}} \cdot \left(1 + \frac{\text{concat}(E_i, M_i)}{2^{E_{bits} + M_{bits}}}\right) \cdot 2^{X_A - 127}$ |
| **Dual Aligner Stage** | Barrel Shifters, Rounding & Saturation | Aligns products to a common 40-bit fixed-point grid. Applies **Shared Scaling** ($2^{X_A - 127}$) and **MX++ Exponent Offsets**. Supports RNE, TRN, CEL, and FLR rounding modes. |
| **Accumulator** | Signed Adder, 32-bit Accumulation Reg | Performs 32-element summation. In **Packed Mode**, two 4-bit elements (FP4) are processed per cycle across dual lanes to double throughput. |
| **Exception & Robustness** | Sticky Registers, Output Override | Latches `nan_sticky` and `inf_sticky` flags. Overrides the final result with OCP special patterns if an exception occurs during the streaming block. |
| **Output Serializer** | Byte Multiplexer | Extracts 8-bit chunks from the 32-bit accumulator for Big-Endian transmission over `uo_out` during Cycles 37-40. |

### Internal Datapath

![Internal Datapath Diagram](https://www.plantuml.com/plantuml/png/~1lLThR-965FtEhxXDgzRHmWBc4RBQhjRciKM218L4RLLLQB37PfInnngF6zXg_tll-8KNXysgwZOVY3s-vznxpzmvXlUn8b8b0OU9TM-jhFjVDfEvzU7EMZQ-Ow734vV2JgaeVjDkI_BqscTgbsoJc4f7X8g6whKZWdR4IQX9Mh5oETksn_tMIYyzB1VjWCIAIbpQZ4KGYL1Z8enjD1RMxxSFzvjVvvXqCVqmlPaObut6J_11KXh2_Ou656x_eb8obyQD-9654P4aW2rn7dqfaj0T2ouaFEsOefNdJf47_cu0_jadyTzVTwRJwqxsJ4YNodozqndsEzdw3BihL_LVurCbWwIE8g7FwTktMWR2GYhVlVi_qcqrBv67Cfj6hjb72kP_tT3cs-UA3pWRmRTAP4afddB6B6hBSMzEaDbQ5SUfJqFtt6vEHxF1zBfUbZczclHC96eyH2vHrCwRMgi3fyP5AUj54tvGXuZ-N5d2iLTCSHptyGgMlyrM8rXQOtW8cO8MpF6WoP3W4IMAH4JjmBYZFjF7AeOVOIM5G-EOXJxIZClTA_8Rs5QYDX4BuoPSh7Q7c3d8bP9wnA4NbwL4-R4n4hPX8GQd__-uUjFv4uk-c6iUM26FlbjIHR1DqeGrqb6mcd0RKKbGE0kC4MoPYY-niLDcKL2Bh-UsZznsbVlJi_rAwcyynYaIuLEF-OaaYeaGfTBHKd0m1bSmcscEMk-Evs-GeQFH1mUJTm35Jiio1nfKBH2CxlKbl88iSemLeAXW3EkDvxJTahPRqdQ71Msk9BPusSG9bG5H-gw7T_OITyobUtq_E4jlblJcMNhxCthxXDxEwP-Nriq7K0zIENMLiUmDXkTqzPWdoess4y_3uKr57OwA-hh3_QY5Umkp-Ums1iCS3BMuAuLZRlJJIpoCrDNmM7THao58EF9C4fplPS8LYpZBqoo4pnmmEbbvk33QZw0D_NqVFnStwnfLn2Ag9TMjuYL78Kf91wMavjxCIaOvtCHHi5R4rveOUg49qts4GypyK5ywzO89Jvzb9Llwvboz_KwQXnLUO1CfAOVrZddQ1-hCZeEedfcYBCT9K1kYXBOVN2tgpv_h2b7N6TjJjnK9J0Bh93Wx1Y9HsbAuhX59RjDRo4lkdPk0M37dyQ3dCBqerUmLnQ12D4fFwemJ7tVuXjmqSIwzL-bdgouVVWtHV5Go5F9ZwgrrvUo3eh2c75yxGXOzbOOaDjYDDgJqeZIalAV2aSeKBiodqobS3VfOf20AfMp3X6uJNu_0biPLVyBlClfiU1nVG-dBA6xSKRwP50PRyPeCX5oTGetSVP2cm8X_0wfYkb_0TCyb-bfG5MD-0MEUI_GIwFDCkP_K0MibAGbgILwEpm5POEOaw9sduVcBA2uJ76NACBqQf73oKuZv8iG-bfL6LanfK9PsTACxybGOqR6-8wOmcq6zAsrREDjwMdFWej9O0Nn6lEoDTOenNyPKMij32yUg0J9VTFCa3vcrdOsUKUhgNmWdqfNkKufTzvsZQ2bxvYxFfBYZCRvTok22Ee-lZqp-6-POKHfPMazTeinzTFnx_2QgVopz0m00)

*Source: [docs/diagrams/DATAPATH_DIAGRAM.PUML](docs/diagrams/DATAPATH_DIAGRAM.PUML)*

- [Read the documentation for project](docs/info.md)
- [Die Size & Area Analysis](docs/hardware/DIE_SIZE_ANALYSIS.md)
- [Flip-Flop Usage Analysis](docs/hardware/FLIP_FLOP_USAGE.md)
- [LUT and Gate Usage Analysis](docs/hardware/LUT_USAGE.md)
- [Consolidated Project Roadmap](ROADMAP.md)
- [Project Concept & Detailed Roadmap](docs/architecture/MXFP8_CONCEPT.md)
- [MX+ Implementation Roadmap](docs/architecture/MX_PLUS.md)
- [VMXDOTP Paper Summary](docs/research/VMXDOTP_PAPER.md)
- [VMXDOTP SERV Integration Roadmap](docs/integration/VMXDOTP_SERV_ROADMAP.md)
- [RISC-V CSR Mapping Concept](docs/integration/CSR_RVV_CONCEPT_AND_ROADMAP.md)
- [Tang Nano 4K Deployment & Testing Guide](src_gowin/TANG_NANO_4K_GUIDE.md)
- [Cortex-M3 Testbench Roadmap](src_m3/TANG_M3_ROADMAP.md)
- [Cortex-M3 Testbench Guide](src_m3/TANG_NANO_M3_TESTBENCH.md)
- [Local Setup Guide (WSL2)](docs/hardware/LOCAL_SETUP.md)

## Protocol Description (MCU to TT/FPGA)

The MAC unit follows a **41-cycle streaming protocol** (Cycles 0–40) to process a block of 32 elements.

### Protocol State Machine

![Protocol State Machine Diagram](https://www.plantuml.com/plantuml/png/~1TLLTRw9057tdLznaNy2LhVXHRTDjYYXP4wb6QDAasvYfZ7LIPCmmTBkxsV--bm41g_fWSEQUE-USEHVl4ac4JBSHp1UpOERCfai_i8Enhqac8mepPmxUepiVW6SxC1TSyXMFm9T4Kl38QiDYgcd96ujtH90j96hZhmOm9AktLy7JE7HunCNDZR_XGjxUmfUnvVRSSLR2HKZ5v-sMrUjV3RL_clRKU0RJl8N9Q3h6GrJhx5drX_pn6XeDv_SAgROQZVgoGtOo5KYIIX8IIK2thi1r4-EwNcN2YBwahqsOlLEnZlYl9YmopYp6DU_nws7jP0sAPcM4dh8bYv_wpzyjephJvM9B9DWNIeQ2PpgcCtkqz1rRTKCBuv28C7l0Zle0NfXCZ9znrR9bL5W_M8njRpco0pi37xAet3lLnZBsvjK8v1OUC2gCJC0osuMN1_kEXGUl25fjDqk9JHXwC8b3-W4sMdofB3w1RU-nmn8xh6675HOTgq6FjUUttIcbxiNbLOMm-b8EpDUpps6xKdN7x7H1zsLem0N-i0QWpz-CmeXZd2y5nS1tsZ2Ew9R6U1s4YGHqUybGs98PUuP0SKwCCstcR4SZ7A8i1g-OEj1xDG_HYoCrxlJ1_t4i9r-kng7JAyLWy4zBsMDA4cwK9fjpLUKaZLSRNjb_ZcSzPxLkdz86dSkIPxjrXkSUuxAOuCjdGmGDLPoKONW55PCJg0LDqaYMmvdLVpQuVYUrn2dbsf4LLO4w8alimP5PXzb3C7y8ghZsAvMMKhcFRL6O-rIYgbJspMwhXZNRtRf99S2dWg4VVz2OJjj4FmhPXrK3jREZeg2bU_uGrXXRgUQkg2jUkILvFF-UVk30HdoL4LzpBh75FNvVGy0btWcBSIMxd5nKcY3rRZRH4TkPRiHtE1Xk6aNmJf1dB8rlsXsDG_pZqVu3)

*Source: [docs/diagrams/PROTOCOL_STATES.PUML](docs/diagrams/PROTOCOL_STATES.PUML)*

### Operational Sequence

| Cycle | Input `ui_in[7:0]` | Input `uio_in[7:0]` | Output `uo_out[7:0]` | Description |
|-------|--------------------|---------------------|----------------------|-------------|
| 0     | **Metadata 0**     | **Metadata 1**      | 0x00 / Probe Data    | **IDLE**: Load MX+ / Debug or Start Fast Protocol. |
| 1     | **Scale A**        | **Format A / BM A** | 0x00 / Probe Data    | Load Scale A, Format A, and BM Index A. |
| 2     | **Scale B**        | **Format B / BM B** | 0x00 / Probe Data    | Load Scale B, Format B, and BM Index B. |
| 3-34  | **Element $A_i$**  | **Element $B_i$**   | 0x00 / Probe Data    | Stream 32 pairs of elements (Standard).* |
| 35    | -                  | -                   | 0x00 / Meta Echo     | Pipeline flush. |
| 36    | -                  | -                   | 0x00                 | Final Shared Scaling calculation. |
| 37    | -                  | -                   | **Result [31:24]**   | Output Byte 3 (MSB). |
| 38    | -                  | -                   | **Result [23:16]**   | Output Byte 2. |
| 39    | -                  | -                   | **Result [15:8]**    | Output Byte 1. |
| 40    | -                  | -                   | **Result [7:0]**     | Output Byte 0 (LSB). |

*\*Note: For 4-bit formats (MXFP4), the unit supports **Vector Packing** (uio_in[6]=1 in Cycle 0). This reduces the STREAM phase to 16 cycles (Cycles 3-18) and the total sequence to 25 cycles.*

### Metadata Mapping

#### Cycle 0: IDLE / Initial Metadata
##### UI_IN 
![Metadata 0 (ui_in) Diagram](https://svg.wavedrom.com/%7B%22reg%22%3A%20%5B%7B%22name%22%3A%20%22NBM%20Offset%20A%22%2C%20%22bits%22%3A%203%7D%2C%20%7B%22name%22%3A%20%22LNS%20Mode%22%2C%20%22bits%22%3A%202%7D%2C%20%7B%22name%22%3A%20%22Loopback%20En%22%2C%20%22bits%22%3A%201%7D%2C%20%7B%22name%22%3A%20%22Debug%20En%22%2C%20%22bits%22%3A%201%7D%2C%20%7B%22name%22%3A%20%22Short%20Protocol%22%2C%20%22bits%22%3A%201%7D%5D%2C%20%22config%22%3A%20%7B%22bits%22%3A%208%7D%7D)
*Source: [docs/diagrams/METADATA_C0_UI_BITFIELD.json](docs/diagrams/METADATA_C0_UI_BITFIELD.json)*

- **Short Protocol (`ui_in[7]=1`)**:
  - Immediately jumps to Cycle 3, reusing previous Scales.
- **Standard Start (`ui_in[7]=0`)**:
  - `ui_in[2:0]`: **NBM Offset A** (MX++)
- **Common Metadata** (captured in both Standard and Short protocols):
  - `ui_in[4:3]`: **LNS Mode** (0: Normal, 1: LNS, 2: Hybrid)
  - `ui_in[5]`: **Loopback Enable** (Bypasses unit; `uo_out = ui_in ^ uio_in`)
  - `ui_in[6]`: **Debug Enable** (Enables probing and metadata echo)

##### UIO_IN
![Metadata 1 (uio_in) Diagram](https://svg.wavedrom.com/%7B%20%22reg%22%3A%20%5B%20%7B%22name%22%3A%20%22NBM%20Offset%20B%22%2C%20%22bits%22%3A%203%7D%2C%20%7B%22name%22%3A%20%22Rounding%20Mode%22%2C%20%22bits%22%3A%202%7D%2C%20%7B%22name%22%3A%20%22Overflow%20Mode%22%2C%20%22bits%22%3A%201%7D%2C%20%7B%22name%22%3A%20%22Packed%20Mode%22%2C%20%22bits%22%3A%201%7D%2C%20%7B%22name%22%3A%20%22MX%2B%20Enable%22%2C%20%22bits%22%3A%201%7D%20%5D%2C%20%22config%22%3A%20%7B%22bits%22%3A%208%7D%7D)
*Source: [docs/diagrams/METADATA_C0_UIO_BITFIELD.json](docs/diagrams/METADATA_C0_UIO_BITFIELD.json)*

- **Short Protocol (`ui_in[7]=1`)**:
  - `uio_in[2:0]` is captured as **Format A & B**.
- **Standard Start (`ui_in[7]=0`)**:
  - `uio_in[2:0]`: **NBM Offset B** (MX++)
- **Common Metadata** (captured in both Standard and Short protocols):
  - `uio_in[4:3]`: **Rounding Mode** (0: TRN, 1: CEL, 2: FLR, 3: RNE)
  - `uio_in[5]`: **Overflow Mode** (0: SAT, 1: WRAP)
  - `uio_in[6]`: **Packed Mode** (1: Enable Vector Packing for FP4/MXFP4)
  - `uio_in[7]`: **MX+ Enable** (1: Enable MX+ extensions)


#### Cycle 1: Configuration Byte (`uio_in`)
![Configuration Byte Diagram](https://svg.wavedrom.com/%7B%20%22reg%22%3A%20%5B%20%7B%22name%22%3A%20%22Format%20A%22%2C%20%22bits%22%3A%203%7D%2C%20%7B%22name%22%3A%20%22BM%20Index%20A%22%2C%20%22bits%22%3A%205%7D%20%5D%2C%20%22config%22%3A%20%7B%22bits%22%3A%208%7D%7D)
*Source: [docs/diagrams/OCP_MX_CONFIG_BITFIELD.json](docs/diagrams/OCP_MX_CONFIG_BITFIELD.json)*
- `ui_in[7:0]`: **Scale A**
- `uio_in[2:0]`: **Format A** (0: E4M3, 1: E5M2, 2: E3M2, 3: E2M3, 4: E2M1, 5: INT8, 6: INT8_SYM)
- `uio_in[7:3]`: **BM Index A** (MX+)

#### Cycle 2: Scale B / MX+ Metadata
![Metadata 2 (uio_in) Diagram](https://svg.wavedrom.com/%7B%22reg%22%3A%20%5B%7B%22name%22%3A%20%22Format%20B%22%2C%20%22bits%22%3A%203%7D%2C%20%7B%22name%22%3A%20%22BM%20Index%20B%22%2C%20%22bits%22%3A%205%7D%5D%2C%20%22config%22%3A%20%7B%22bits%22%3A%208%7D%7D)
*Source: [docs/diagrams/METADATA_C2_UIO_BITFIELD.json](docs/diagrams/METADATA_C2_UIO_BITFIELD.json)*
- `ui_in[7:0]`: **Scale B**
- `uio_in[2:0]`: **Format B** (Enabled if `SUPPORT_MIXED_PRECISION=1`)
- `uio_in[7:3]`: **BM Index B** (MX+)

### Debugging Output

When enabled via `ui_in[6]` in Cycle 0, the `uo_out[7:0]` port provides real-time observability into the unit's internal state during the phases that are normally silent (Cycles 0-35).

- **Enable**: Set `ui_in[6] = 1` during Cycle 0.
- **Probe Selection**: Set `uio_in[3:0]` during Cycle 0 to select the internal signal to monitor.
- **Cycles 0-34 (Standard)** or **0-18 (Packed)**: `uo_out` outputs the selected **Probe Data** (e.g., Accumulator MSB, Multiplier outputs, FSM state).
- **Cycle 35 (Standard)** or **19 (Packed)**: `uo_out` outputs a **Metadata Echo**, confirming the captured configuration.

For a full list of available probes and the metadata echo bit-mapping, see [DEBUG_TT.md](docs/DEBUG_TT.md).

- [Silicon Online Viewer](https://gds-viewer.tinytapeout.com/?pdk=ihp-sg13g2&model=https%3A%2F%2Fchatelao.github.io%2Fttihp-fp8-mul%2Ftinytapeout.oas)
- [Interactive Digital Twin (WASM Demo)](https://chatelao.github.io/ttihp-fp8-mul/demo/)
- [MAC Generator & Predictor](https://chatelao.github.io/ttihp-fp8-mul/demo/mac.html)

### MicroPython Example (TT DevKit)

You can run a single MAC operation on the Tiny Tapeout DevKit using the onboard RP2040 or RP2350 with MicroPython. The following script performs a 32-element dot product of $1.0 \times 1.0$ with no scaling.

#### Tiny Tapeout DevKit Pin Mapping

| Signal | RP2040 (v2.0/v3.1) | RP2350 (v3.2) |
|--------|-------------------|---------------|
| `ui_in[7:0]` | GPIO 0-7 | GPIO 17-24 |
| `uo_out[7:0]` | GPIO 8-15 | GPIO 33-40 |
| `uio[7:0]` | GPIO 16-23 | GPIO 25-32 |
| `clk` | GPIO 24 | GPIO 16 |
| `rst_n` | GPIO 25 | GPIO 14 |
| `ena` | GPIO 26 | GPIO 15 |

*For the full script and advanced usage, see [test/TT_MAC_RUN.PY](test/TT_MAC_RUN.PY).*

## OCP MX Feature Support

This implementation follows the **OCP Microscaling Formats (MX) Specification (v1.0)**.

### Implemented Features
- **Multiple Element Formats**:
  - **MXFP8**: E4M3 (Bias 7) and E5M2 (Bias 15).
  - **MXFP6**: E3M2 (Bias 3) and E2M3 (Bias 1).
  - **MXFP4**: E2M1 (Bias 1).
  - **MXINT8**: Standard and Symmetric 8-bit signed integers.
- **Shared Scaling**: Hardware-accelerated application of shared scales ($X_A, X_B$) using the UE8M0 format (8-bit unsigned biased exponent, Bias 127).
- **Rounding Modes**: Support for all four OCP MX rounding modes:
  - **TRN**: Truncate (Towards Zero).
  - **CEL**: Ceil (Towards $+\infty$).
  - **FLR**: Floor (Towards $-\infty$).
  - **RNE**: Round-to-Nearest-Ties-to-Even.
- **Overflow Methods**: Configurable behavior for out-of-range results:
  - **SAT**: Saturation (Clamp to Max/Min representable value).
  - **WRAP**: Wrapping (Modulo arithmetic).
- **Mixed-Precision Operations**: Independent format selection for Operand A and Operand B within a single MAC block.
- **OCP MX+ (Extended Mantissa)**: Higher precision for "Block Max" (BM) elements by repurposing exponent bits as an extended mantissa:
  $$V(A_{BM}) = S \cdot 2^{E_{max} - \text{Bias}} \cdot \left(1 + \frac{\text{concat}(E_i, M_i)}{2^{E_{bits} + M_{bits}}}\right) \cdot 2^{X_A - 127}$$
- **Efficiency**: 41-cycle pipelined streaming protocol with **Fast Start** (Scale Compression) to reuse scales/formats across consecutive blocks.

### Omitted Features & Deviations
- **Subnormal Support**: The RTL fully supports subnormal elements (denormals) for all floating-point formats, providing high numerical accuracy for small values.
- **Fixed Block Size**: The unit is hard-coded for a block size of **$k=32$** elements.
- **NaN/Infinity Handling**:
  - **E5M2** fully supports IEEE-754 style Infinities and NaNs.
  - For other formats, the unit prioritizes **saturation** for out-of-range values, consistent with OCP MX "Saturation-only" modes for narrower formats.
- **Accumulator Precision**: A **32-bit signed fixed-point accumulator** is used, providing sufficient range for 32-element dot products of all supported formats.

## FPGA Support

This project includes support for generating an FPGA bitstream for the **Sipeed Tang Nano 4K** (Gowin GW1NSR-4C).

For detailed build, flash, and test instructions, see the **[Tang Nano 4K Deployment & Testing Guide](src_gowin/TANG_NANO_4K_GUIDE.md)**.

The bitstream is automatically generated by the GitHub Action defined in `.github/workflows/gowin.yaml`.

### Pin Mapping for Tang Nano 4K

| Signal | Tang Nano 4K Pin | Description |
|--------|------------------|-------------|
| `ui_in[7:0]` | 40-39, 35-30 | Scale A / Elements A |
| `uo_out[7:0]` | 9-7, 22, 44-41 | Serialized Result |
| `uio[7:0]` | 21-16, 13, 10 | Scale B / Elements B |
| `clk` | 45 | Onboard 27MHz Clock (Target: 20MHz for timing closure) |
| `rst_n` | 15 | Button S1 (Reset) |
| `ena` | 14 | Button S2 (Enable) |

*Note: Pins are listed in MSB-to-LSB order where applicable.*

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## Glossary

A comprehensive list of terms and acronyms used in this project can be found in the [Project Glossary](docs/GLOSSARY.md).

## Compilation Options

The MAC unit is highly configurable through Verilog parameters. These can be adjusted to balance feature support against hardware area (gate count).

### Hardware Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ALIGNER_WIDTH` | 32 | Bit-width of the internal alignment datapath. |
| `ACCUMULATOR_WIDTH` | 24 | Bit-width of the fixed-point accumulator. |
| `SUPPORT_E4M3` | 1 | Enable support for E4M3 (MXFP8) format. |
| `SUPPORT_E5M2` | 0 | Enable support for E5M2 (MXFP8) format. |
| `SUPPORT_MXFP6` | 0 | Enable support for E3M2 and E2M3 (MXFP6) formats. |
| `SUPPORT_MXFP4` | 1 | Enable support for E2M1 (MXFP4) format. |
| `SUPPORT_INT8` | 0 | Enable support for INT8 and INT8_SYM formats. |
| `SUPPORT_PIPELINING` | 0 | Enable multiplier pipelining for higher clock frequencies. |
| `SUPPORT_ADV_ROUNDING` | 0 | Enable advanced rounding modes (RNE, CEL, FLR). |
| `SUPPORT_MIXED_PRECISION`| 0 | Allow different formats for Operand A and B. |
| `SUPPORT_VECTOR_PACKING` | 0 | Enable 2x throughput for FP4 using vector packing. |
| `SUPPORT_PACKED_SERIAL` | 0 | Enable bit-serial throughput for packed FP4 formats. |
| `SUPPORT_INPUT_BUFFERING` | 0 | Enable input buffering for FP4 formats. |
| `SUPPORT_MX_PLUS` | 0 | Enable MX+ extensions (Repurposed Exponents). |
| `SUPPORT_SERIAL` | 1 | Enable bit-serial multiplier core (reduces area). |
| `SERIAL_K_FACTOR` | 8 | Bit-serial period (typically 8 for FP8). |
| `ENABLE_SHARED_SCALING` | 0 | Enable OCP MX Shared Scaling logic. |
| `USE_LNS_MUL` | 0 | Use Logarithmic Number System (LNS) multiplier core. |
| `USE_LNS_MUL_PRECISE` | 0 | Use precise LUT-based LNS (higher area). |

### Pre-defined Variants

The project includes a configuration script (`scripts/configure_variant.py`) to quickly switch between common profiles:

- **Baseline**: Full feature set enabled, 40-bit aligner, 32-bit accumulator, parallel multipliers.
- **Light/Lite**: Balanced configuration with MXFP6, Vector Packing, and MX+ disabled.
- **Tiny**: Minimal footprint with only essential FP8 support enabled.
