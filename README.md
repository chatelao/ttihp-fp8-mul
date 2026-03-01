![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Tiny Tapeout IHP 26a - OCP MXFP8 Streaming MAC Unit

This project implements a Streaming Multiply-Accumulate (MAC) Unit compatible with the OCP Microscaling Formats (MX) Specification (v1.0). It is designed to fit within a single 1x2 Tiny Tapeout tile using the IHP SG13G2 PDK.

## Attributions

This project incorporates logic and concepts from several open-source resources:
- [fp8_mul](https://github.com/cchan/fp8_mul) by Clive Chan (Arithmetic logic).
- [Tiny Tapeout Verilog Template](https://github.com/tinytapeout/tt-verilog-template) (Project structure).
- [OCP Microscaling Formats (MX) Specification v1.0](https://www.opencompute.org/documents/ocp-microscaling-formats-mx-v1-0-spec-final-pdf) (Numerical and Protocol Specification).

We gratefully acknowledge these contributions to the open-source hardware and AI communities.

## System Context

![System Context Diagram](https://www.plantuml.com/plantuml/proxy?cache=no&src=https://raw.githubusercontent.com/chatelao/ttihp-fp8-mul/main/documentation/CONTEXT_DIAGRAM.PUML)

*Source: [documentation/CONTEXT_DIAGRAM.PUML](documentation/CONTEXT_DIAGRAM.PUML)*

- [Read the documentation for project](documentation/INFO.md)
- [Project Concept & Roadmap](documentation/MXFP8_CONCEPT.md)
- [RISC-V CSR Mapping Concept](documentation/CSR_MAPPING.md)

## Protocol Description (MCU to TT/FPGA)

The MAC unit follows a **41-cycle streaming protocol** (Cycles 0–40) to process a block of 32 elements.

### Operational Sequence

| Cycle | Input `ui_in[7:0]` | Input `uio_in[7:0]` | Output `uo_out[7:0]` | Description |
|-------|--------------------|---------------------|----------------------|-------------|
| 0     | -                  | -                   | 0x00                 | **IDLE**: Waiting for start. |
| 1     | **Scale A**        | **Config Byte**     | 0x00                 | Load Scale A and Operation Mode. |
| 2     | **Scale B**        | **Format B**        | 0x00                 | Load Scale B and Format B. |
| 3-34  | **Element $A_i$**  | **Element $B_i$**   | 0x00                 | Stream 32 pairs of elements. |
| 35    | -                  | -                   | 0x00                 | Pipeline flush. |
| 36    | -                  | -                   | 0x00                 | Final Shared Scaling calculation. |
| 37    | -                  | -                   | **Result [31:24]**   | Output Byte 3 (MSB). |
| 38    | -                  | -                   | **Result [23:16]**   | Output Byte 2. |
| 39    | -                  | -                   | **Result [15:8]**    | Output Byte 1. |
| 40    | -                  | -                   | **Result [7:0]**     | Output Byte 0 (LSB). |

### Configuration Byte (Cycle 1, `uio_in`)
- `[2:0]`: **Format A** (0: E4M3, 1: E5M2, 2: E3M2, 3: E2M3, 4: E2M1, 5: INT8, 6: INT8_SYM)
- `[4:3]`: **Rounding Mode** (0: TRN, 1: CEL, 2: FLR, 3: RNE)
- `[5]`: **Overflow Mode** (0: SAT, 1: WRAP)

### Format B Byte (Cycle 2, `uio_in`)
- `[2:0]`: **Format B** (Same encoding as Format A)

### Fast Start (Scale Compression)
If `ui_in[7]` is set to `1` during **STATE_IDLE** (Cycle 0), the unit immediately jumps to **Cycle 3**. It reuses the **Scales**, **Formats**, and **Rounding Modes** from the previous operation, saving 3 clock cycles.

- [MX+ Implementation Roadmap](documentation/MX_PLUS.md)
- [Local Setup Guide (WSL2)](documentation/LOCAL_SETUP.md)
- [Silicon Online Viewer](https://gds-viewer.tinytapeout.com/?pdk=ihp-sg13g2&model=https%3A%2F%2Fchatelao.github.io%2Fttihp-fp8-mul%2F%2Ftinytapeout.oas)

### MicroPython Example (TT DevKit)

You can run a single MAC operation on the Tiny Tapeout DevKit using the onboard RP2040 with MicroPython. The following script performs a 32-element dot product of $1.0 \times 1.0$ with no scaling.

```python
import machine
import time

# Pin Mapping for TT DevKit RP2040
UI_IN = [machine.Pin(i, machine.Pin.OUT) for i in range(8)]
UO_OUT = [machine.Pin(i, machine.Pin.IN) for i in range(8, 16)]
UIO = [machine.Pin(i, machine.Pin.OUT) for i in range(16, 24)]
CLK, RST_N, ENA = machine.Pin(24, machine.Pin.OUT), machine.Pin(25, machine.Pin.OUT), machine.Pin(26, machine.Pin.OUT)

def clock_step():
    CLK.value(1); time.sleep_us(10); CLK.value(0); time.sleep_us(10)

def run_mac():
    ENA.value(1); RST_N.value(0); CLK.value(0); time.sleep_ms(10); RST_N.value(1)

    clock_step() # Cycle 0 -> 1
    # Cycle 1: Scale A (127=1.0) & Config (0x00=E4M3)
    for i in range(8): UI_IN[i].value((127 >> i) & 1); UIO[i].value(0)
    clock_step()
    # Cycle 2: Scale B (127=1.0) & Format B (0x00=E4M3)
    for i in range(8): UI_IN[i].value((127 >> i) & 1); UIO[i].value(0)
    clock_step()
    # Cycle 3-34: Stream 32 elements (0x38=1.0 in E4M3)
    for i in range(8): UI_IN[i].value((0x38 >> i) & 1); UIO[i].value((0x38 >> i) & 1)
    for _ in range(32): clock_step()
    # Cycle 35-36: Flush and Scale
    for i in range(8): UI_IN[i].value(0); UIO[i].value(0)
    clock_step(); clock_step()
    # Cycle 37-40: Read 32-bit Result (MSB first)
    res = 0
    for _ in range(4):
        byte = 0
        for i in range(8):
            if UO_OUT[i].value(): byte |= (1 << i)
        res = (res << 8) | byte
        clock_step()
    print(f"Result: {res} (Fixed-point), {res/256.0} (Float)")

run_mac()
```

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
- **Efficiency**: 41-cycle pipelined streaming protocol with **Fast Start** (Scale Compression) to reuse scales/formats across consecutive blocks.

### Omitted Features & Deviations
- **Subnormal Support**: Subnormal elements are **flushed to zero** (Denormals-Are-Zero) to reduce hardware area.
- **Fixed Block Size**: The unit is hard-coded for a block size of **$k=32$** elements.
- **NaN/Infinity Handling**:
  - **E5M2** fully supports IEEE-754 style Infinities and NaNs.
  - For other formats, the unit prioritizes **saturation** for out-of-range values, consistent with OCP MX "Saturation-only" modes for narrower formats.
- **Accumulator Precision**: A **32-bit signed fixed-point accumulator** is used, providing sufficient range for 32-element dot products of all supported formats.

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

## Set up your Verilog project

1. Add your Verilog files to the `src` folder.
2. Edit the [info.yaml](info.yaml) and update information about your project, paying special attention to the `source_files` and `top_module` properties. If you are upgrading an existing Tiny Tapeout project, check out our [online info.yaml migration tool](https://tinytapeout.github.io/tt-yaml-upgrade-tool/).
3. Edit [documentation/INFO.md](documentation/INFO.md) and add a description of your project.
4. Adapt the testbench to your design. See [test/README.md](test/README.md) for more information.

The GitHub action will automatically build the ASIC files using [LibreLane](https://www.zerotoasiccourse.com/terminology/librelane/).

## FPGA Support

This project includes support for generating an FPGA bitstream for the **Sipeed Tang Nano 9K** (Gowin GW1NR-9C).

The bitstream is automatically generated by the GitHub Action defined in `.github/workflows/gowin.yaml`.

### Pin Mapping for Tang Nano 9K

| Signal | Tang Nano 9K Pin | Description |
|--------|------------------|-------------|
| `ui_in[7:0]` | 28, 27, 26, 25, 39, 36, 37, 38 | Scale A / Elements A |
| `uo_out[7:0]` | 80, 81, 82, 83, 84, 85, 86, 63 | Serialized Result |
| `uio[7:0]` | 42, 41, 35, 40, 34, 33, 30, 29 | Scale B / Elements B |
| `clk` | 52 | Onboard 27MHz Clock |
| `rst_n` | 4 | Button S1 (Reset) |
| `ena` | 3 | Button S2 (Enable) |

*Note: Pins are listed in MSB-to-LSB order where applicable.*

## Resources

- [FAQ](https://tinytapeout.com/faq/)
- [Digital design lessons](https://tinytapeout.com/digital_design/)
- [Learn how semiconductors work](https://tinytapeout.com/siliwiz/)
- [Join the community](https://tinytapeout.com/discord)
- [Build your design locally](https://www.tinytapeout.com/guides/local-hardening/)

## Glossary

- **OCP MX**: Open Compute Project Microscaling Formats, a specification for block-based scaling in deep learning.
- **MXFP8 / MXFP6 / MXFP4**: 8-bit, 6-bit, and 4-bit floating-point formats defined under the OCP MX specification.
- **Shared Scale**: A single scaling factor applied to a block of elements to reduce memory bandwidth.
- **UE8M0**: An 8-bit unsigned biased exponent format (Bias 127) used for shared scaling factors.
- **Fast Start (Scale Compression)**: A protocol optimization that allows the reuse of previously loaded scales and formats to increase throughput.
- **RNE (Round-to-Nearest-Ties-to-Even)**: A rounding mode that rounds to the nearest value, breaking ties by rounding to the nearest even number.
- **SAT (Saturation)**: An overflow handling method that clamps out-of-range values to the maximum or minimum representable values.
- **Block Size (k)**: The number of elements that share a single scaling factor (fixed at 32 in this design).
- **BM (Block Max)**: The element with the largest magnitude in a block, whose exponent determines the shared scale.
- **MX+**: An extension to OCP MX that repurposes the exponent bits of the Block Max element for additional mantissa precision.
- **Tiny Tapeout**: An educational project that facilitates low-cost ASIC manufacturing.
- **IHP SG13G2**: A 130nm BiCMOS Open Source PDK used for the ASIC implementation.
- **Streaming MAC**: A Multiply-Accumulate unit that processes elements sequentially over a timed protocol.

## What next?

- [Submit your design to the next shuttle](https://app.tinytapeout.com/).
- Edit [this README](README.md) and explain your design, how it works, and how to test it.
- Share your project on your social network of choice:
  - LinkedIn [#tinytapeout](https://www.linkedin.com/search/results/content/?keywords=%23tinytapeout) [@TinyTapeout](https://www.linkedin.com/company/100708654/)
  - Mastodon [#tinytapeout](https://chaos.social/tags/tinytapeout) [@matthewvenn](https://chaos.social/@matthewvenn)
  - X (formerly Twitter) [#tinytapeout](https://twitter.com/hashtag/tinytapeout) [@tinytapeout](https://twitter.com/tinytapeout)
  - Bluesky [@tinytapeout.com](https://bsky.app/profile/tinytapeout.com)
