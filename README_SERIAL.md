![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg) [![Documentation Status](https://readthedocs.org/projects/ttihp-fp8-mul/badge/?version=latest)](https://ttihp-fp8-mul.readthedocs.io/en/latest/?badge=latest)

# Tiny Tapeout IHP 26a - OCP MXFP8 Bit-Serial Streaming MAC Unit

This project implements an ultra-minimal, bit-serial Streaming Multiply-Accumulate (MAC) Unit compatible with the OCP Microscaling Formats (MX) Specification (v1.0). It is inspired by the **SERV** bit-serial RISC-V core and designed to achieve the smallest possible footprint (< 500 gates) within a Tiny Tapeout tile.

## Philosophy: The SERV Approach

The fundamental principle of this bit-serial variant is that any N-bit operation can be decomposed into N 1-bit operations over N clock cycles.
- **Registers as Shift Registers**: Operands and the accumulator are stored in shift registers.
- **1-Bit Datapath**: All arithmetic (multiplication, alignment, accumulation) is performed using 1-bit logic.
- **Latency-Area Tradeoff**: By processing one bit at a time, we significantly reduce gate count and routing congestion at the cost of increased cycle count.

## System Context

![System Context Diagram](https://www.plantuml.com/plantuml/png/~1dLTRZnet57xdLvoYgW9f2MaLzQ5Dex0i9Ai0YnWsJPz6ncF0Me-DR4-ofCf_xpcUczc5H2elC_QS-_dEP_FMUMPzaIj89glRqImTtotMaq_hzEPsz6urcdT-afgh8XEmz_xW_XWEBVloOYVzljWKJbXkj1VQl-0c7nuKqsHgu7ocv6OuVZLOqjRzV3RCcVF2ubOwDld1QD8ve6odCnlzStU_Jl--NRzFPvDtayLDhzzn3r8Vc6KvMC4zqpibNh_Uc49dp1xVl85_Eu2_AJfFv5S1lxtiV3klG_4ngOLD_u-sEsBK-OzKxmyPy-Aw4ahyKObUjt7SlOAV_V4W_egs-kTrIdUjGhNkTpfBOPtHlRrn_Wgwx_41IItSdIxVZQvWBharvC8QfOIz0cEffnzXRAmW6-Ec5BNRNivuMcX9Dg-b7oJ2IgRWRho4-IUOZyPmZn-XTw-yPOEvr3B7pnyPIcdVx_Qn6g4SPonl7PPD6Vw0fXDlXUTxaS4qcSClGHo33FfG_HfKz3YQy1H_TtpaIk2NiAP4VnzifAUNjMNymO4oEyaneeCr7bDNm4d3lS1idzjzI5lB7mQHrGhu7zBfQBo-MuMjOZC8jg3IWIrM4vqFN5aYLwOazUwyCqe_H1VInqx3d96u8Eip-a0lOsDi9ZL-Th5nJ8SBvz0ucC_e-yDtyyAMR-KkjMBdo5bfOXmsOOMR8P-zt7fQIPh2SiiZB1muh1y-cCuenPnvV7V0fUM5Ofv2mC0kUCOYc8r8TqANJSO5HBdb6qhDK3oqiIoK4o0meUD9HetXbL3fJToc4_j1FGgZb8v5JcjE-y_46zEnxAn2KO142xEdkf7AQSbdXcN3K65IdcYsKRNdRnVd8ozKCn_HwCqBvUL1IUA8izEH2MuoR67RwfjgvmHPaqUSM8xDJAvWWjmGkWXRQtBmUm58TOKF86RvXTwc667h98eBDt-b0i4eoyebaXDXnq6Ej22TOv1NuXmXP7J0zkOOb7fpILIW5CmMIV-yR_5uI95Z_BxrFtailxNUSKI7646tbTb8GgwnnD_abJ0jAZrmHPw7OCv0hgrfdVMyJWHRuvuXePMF8wr3Z7KkzvyfkTCjGvOPZ6WJ1nuPOoSk0a2nOwhG6khTq68mmqMj6-gnWY6isG6xzaZhyCaHhMG5OM9pX625fflG4AZdUrZ0m2q5taQweYNgdu3kkgMmzMenN2qcO2kvaghFrhvD9_PJffD1c8qGsuzBolcpWd9Uv4Havj8yaKz6G6w0DIqGd0ssc-II8czAI1N36VBcX2XPw-ny7Ib05mwsI2i91ywhboMeQvwE6DeMMfCW8lZFnX_k6yq5710jGecShbFdJmTcxJ7TRiahlSBDT1g62Chd4bq8-ndj1Sc1GLxO2Fz52Dqm_rFERKlMP8JLeLOz6PNx9kMupBFa6gP2P1iymvyep6BZSUWOrXFHLPHQR7qizG-H8XwvE10PD7YPr3lm7cb34R8luCLB_d1i4PQ4TRY5JKiAPiHl3XPiCRpLMyWAMy-PQ-v1pwUjFivAwzKzhp0f9LxT8OgMLJ2rKg4KZ4-p-dA5hrnXQjRv50z7eHbgnqgdXzXSU8OtKaPwXKmbgXJIu1DwpVMj_yJ2cRFed0L2KDMns6MaFSSN5p5vUNjfl4LdvGdxBQjfFE685gCLbSJWY5Yb4QqX-hpc8HYyvMVO7OSd6YNoLkYC_hRy1m00)

*Source: [docs/diagrams/SERIAL_CONTEXT_DIAGRAM.PUML](docs/diagrams/SERIAL_CONTEXT_DIAGRAM.PUML)*

## Attributions

This project incorporates logic and concepts from several open-source resources:
- [SERV](https://github.com/olofk/serv) by Olof Kindgren (Bit-serial design philosophy).
- [fp8_mul](https://github.com/cchan/fp8_mul) by Clive Chan (Arithmetic logic).
- [Tiny Tapeout Verilog Template](https://github.com/TinyTapeout/ttihp-verilog-template) (Project structure).
- [OCP Microscaling Formats (MX) Specification v1.0](https://www.opencompute.org/documents/ocp-microscaling-formats-mx-v1-0-spec-final-pdf) (Numerical and Protocol Specification).

## Functional Block Overview

| Block | Component | Detailed Function & Mathematics |
| :--- | :--- | :--- |
| **FSM & Control** | Stretched FSM, Cycle Counter | Orchestrates the protocol using a **Stretched Protocol**. Each standard cycle is expanded into $K$ internal cycles (`SERIAL_K_FACTOR`). |
| **Bit-Serial Multiplier** | Serial-Parallel Mul | Performs mantissa multiplication bit-by-bit. For MXFP8, a 4-bit multiplication is distributed over multiple internal cycles. |
| **Serial Aligner Stage** | Delay-Line Aligner | Aligns products by delaying the bit-stream. The delay is proportional to the required shift, replacing area-intensive barrel shifters. |
| **Serial Accumulator** | 1-bit Adder, Circulating Register | Performs summation using a 1-bit full adder and a carry flip-flop. The 40-bit accumulator circulates in a shift register. |
| **Output Serializer** | Shift Register | Extracts results bit-by-bit or byte-by-byte for transmission over `uo_out`. |

### Internal Datapath

![Internal Datapath Diagram](https://www.plantuml.com/plantuml/png/~1lLPjRzis4FwkNy5v0-PYTUmCmTOMNL5PTh8WTcDO2RQX20IQEjj4A5AWJakr8l-zH-h5dkiKmx3ENqoUxfvxxkuXfRS5SejbfbWyNLw6isGIteIByERNP78PNYp3UV2Dr4ALAR0jObwy6WujVpZPIDoMgx80Aun6q7WYJ3RC5TSEQr1WgkHg69qD5ivqEvyDCruWM38baSboerrCJhv1C0l_kBwzINwxfAIpwSNqtQJ_B0Y-PnSMGBERBMJ0hly4QsKAHL3SIvrpopEsuk9-OqsfqyWeOzd3LYBiFHTj7lOnOFGR7_X_-t8qdRuSrS-CJS4szj7efxDHRJ-dwZgh-mMFUnai2EHwe-3rQzS6BZNODs_-ZtGhXyjjrMLpaR7y2zYF_tL1oTVFLLIaZUnh9GgjDGyDOksrKZIRWyZQzXW4jtdA4SODbnWh1VrUrutUS_OTLZdyicSYjQ94HIgD5cp--_dY1HjB7CHW9LTi7aPim2xfb5XDsmb7ddFSilxLG5I2eXRM22WAgJS457LjRndqgOuIarpguZdhBRPL8GNXUC0r5z1xrjNMwBrVoaHgSlR_xtz-DReZshrBXyCMXEDsBmOhYKniItrVCA3ZLR4hvWaLLD0Xdca1pRz5V3nQcskYDIfHPYC5OSHe0SKMKXRLJuvKTvy8ZUHxDOW81lrCUZC7u1PnkMhwYZAZdhBtevEJgy7ftMTLgGR7Xr97Zw7HRD08evewFDZPwEx9Uj9ckXIw9u5svaUAAPAiL8vs8vPIeSoLh6cS-evsPERIjKOfDdiNioOWJ5Elm4DKhkJ6JMm2YbSiTBiQCrwo7oZD1xVsveAjAfOwDzSjIaYtjmMU7GCLOaSr5A8axXpD3hScN7CYszd8xoDfXNDq-4lOIFSY-98YrdAJ59RY8xykBOKQpU9bSQI1wmnhvtDZCux3c4O9tjUHsierkfprpXEd-oHb6I1titgIXYdHdRfEbtNDrzvwR8pWA8mh1DPb-RkIfX_GSe6ksqX2MbkJ4Sidpabty4n2HDp1yulkuDKy3axU4WfI3nkw2sK5NdGz_o9rgxKo3y4IL39fRuTMUQTkvaEVtqFdOBbEMKYnhR_v9m7ZBg1nt8cG2AMbG1RNmZh0s8Kr_gtGQjMcNmoxRMNP1itYCJi7IDtNmUSXFcRP7lrzhSqCJzbKDx2pVHssXTToT7TxqK9DklHU08tW5_JUKGgK5nto3QIx8frVDzPwS96xCXtYMz2f-oJw1000)

*Source: [docs/diagrams/SERIAL_DATAPATH_DIAGRAM.PUML](docs/diagrams/SERIAL_DATAPATH_DIAGRAM.PUML)*

## Protocol Description (Stretched)

To maintain compatibility with the 8-bit streaming interface while using bit-serial internals, the unit uses a **Stretched Protocol**. 1 element is processed every $K$ clock cycles.

### Protocol State Machine

![Protocol State Machine Diagram](https://www.plantuml.com/plantuml/png/~1TLLTRvim57tdLrnfqfHaPKkWAoHggn42MjTae42bIbqLkU0sLWb6napAflttsK0I24aU8ii-z-CSphM_vHmnNcmI29pbdJLV-Kilz6nllWf2AtG2XHEUOF1i7nQFhc_2b70rm8mW4S4Pvj4Qn-0pocb4vHRY61OeMfCKG-_-nkmhIlvEqWmnj86yFFwh04nHzFx6Q976DaqekxxU9xkzXG_ko3MTiOHH5cDs2gBhL-EHe_nJbAV1CwZgBTpDveueLfQGwx8ELCi930Pp-aOYqRQzZGIZuM3GFlRNs_nmdiDGDTgGclK2SnGZZi166IyOdZGnAWHhyifLai8ClnHl5x2K74agLel7JstetQj0KyRtyatWHx79WDDIMhIHx4gqf3VthDagiAsg5uxI6B5OBXZ_bVOAiYBfa_5yC-mVGe9mwLYBrSmABHdJgWKjFPiPHlsTYesIbPQj7euKpM6aQhLYHxXZQKrLqqyXxT7ae5yW0Z1O5-1Ija4Sh1DuhOEVxl5JgLu3tXMaRGXznxe2rOoRMrLSjIz_xMmTENHLlwnPda8VYw9TgfenFXlGcBj5aS17iAAes1I9QEzCH6y4BuH3ncY4yrnCQOOPPBkgaQpQBqE5JXsgxlmX-DxbMcrtfqd_sctyWErGDOUgPXhdGtoIuKJU86vIv6lu0Yv9PJXYR7ksvQPH6pdFs1NqgsxzyvRLJ67QyGcMkv2gms2Dc51QUb7CFFIgBzQIkVcH6fuigIiTBGw0if3qTAkmpE0zXFv3s3MqiNDq3QYasQExXZNKozsrs41rf1XVgRfc70ChgkIFeB_4UP7mUZHfmTl04KoteYdy6xCjc72KNZAieVMTtY4sL9HNIhbmyq_nFm57F3UGr93Irn1Hnd2UqJJEo-kqUjlkLwvbXzwoCGK9ZTwhcFopyWsdiNWAbVy0)

*Source: [docs/diagrams/SERIAL_PROTOCOL_STATES.PUML](docs/diagrams/SERIAL_PROTOCOL_STATES.PUML)*

### Operational Sequence (Example K=8)

| Phase | Standard Cycles | Stretched Cycles (K=8) | Description |
|-------|-----------------|------------------------|-------------|
| **Metadata** | 3 | 24 | Load Shared scales, format, and MX+ metadata. |
| **Stream** | 32 | 256 | 32 pairs of elements streamed ($A_i, B_i$). |
| **Summation** | 2 | 16 | Pipeline flush and final alignment. |
| **Output** | 4 | 32 | 32-bit result output (1 byte every $K$ cycles). |

## OCP MX Feature Support

Despite its minimal size, the bit-serial unit aims for full OCP MX compliance:
- **Multiple Element Formats**: MXFP8, MXFP6, MXFP4, and MXINT8.
- **Shared Scaling**: Hardware-accelerated scaling using the UE8M0 format.
- **Rounding Modes**: Support for TRN and RNE (serialized).
- **Overflow Methods**: SAT (Saturation) and WRAP.

## Compilation Options

| Parameter | Description |
|-----------|-------------|
| `SUPPORT_SERIAL` | **Set to 1** to enable the bit-serial implementation. |
| `SERIAL_K_FACTOR` | The bit-serial period (typically 8 for 8-bit formats). |
| `ALIGNER_WIDTH` | Bit-width of the internal alignment (e.g., 40 bits). |
| `ACCUMULATOR_WIDTH`| Bit-width of the circulating accumulator. |

## Resources

- [Bit-Serial Concept Document](docs/architecture/OCP_MX_SERIAL.md)
- [Project Roadmap](ROADMAP.md)
- [OCP MX Specification](https://www.opencompute.org/documents/ocp-microscaling-formats-mx-v1-0-spec-final-pdf)
- [Tiny Tapeout FAQ](https://tinytapeout.com/faq/)

## Target Metrics
- **Area Goal**: < 500 gates (excluding shift registers).
- **Tile Target**: 1x1 Tiny Tapeout tile.
- **Frequency**: Designed for high-frequency operation (100MHz+) to offset serial latency.
