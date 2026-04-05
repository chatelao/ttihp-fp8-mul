![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Tiny Tapeout IHP 26a - OCP MXFP8 Streaming MAC Unit

This project implements a Streaming Multiply-Accumulate (MAC) Unit compatible with the OCP Microscaling Formats (MX) Specification (v1.0). It is designed to fit within a 2x2 Tiny Tapeout tile using the IHP SG13G2 PDK.

## Attributions

This project incorporates logic and concepts from several open-source resources:
- [fp8_mul](https://github.com/cchan/fp8_mul) by Clive Chan (Arithmetic logic).
- [Tiny Tapeout Verilog Template](https://github.com/TinyTapeout/ttihp-verilog-template) (Project structure).
- [OCP Microscaling Formats (MX) Specification v1.0](https://www.opencompute.org/documents/ocp-microscaling-formats-mx-v1-0-spec-final-pdf) (Numerical and Protocol Specification).

We gratefully acknowledge these contributions to the open-source hardware and AI communities.

## System Context

![System Context Diagram](https://www.plantuml.com/plantuml/proxy?cache=no&src=https://raw.githubusercontent.com/chatelao/ttihp-fp8-mul/main/docs/diagrams/CONTEXT_DIAGRAM.PUML)

*Source: [docs/diagrams/CONTEXT_DIAGRAM.PUML](docs/diagrams/CONTEXT_DIAGRAM.PUML)*

- [Read the documentation for project](docs/info.md)
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

*\*Note: For 4-bit formats (MXFP4), the unit supports **Vector Packing** (uio_in[6]=1 in Cycle 1). This reduces the STREAM phase to 16 cycles (Cycles 3-18) and the total sequence to 25 cycles.*

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

For a full list of available probes and the metadata echo bit-mapping, see [DEBUG_TT.md](DEBUG_TT.md).

- [Silicon Online Viewer](https://gds-viewer.tinytapeout.com/?pdk=ihp-sg13g2&model=https%3A%2F%2Fchatelao.github.io%2Fttihp-fp8-mul%2F%2Ftinytapeout.oas)
- [Interactive Digital Twin (WASM Demo)](https://chatelao.github.io/ttihp-fp8-mul/)

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

```python
import machine
import os
import time

# Identify board version based on machine info
is_rp2350 = "RP2350" in os.uname().machine

# Pin Mapping for TT DevKit
if is_rp2350: # v3.2 (RP2350)
    UI_IN = [machine.Pin(i, machine.Pin.OUT) for i in range(17, 25)]
    UO_OUT = [machine.Pin(i, machine.Pin.IN) for i in range(33, 41)]
    UIO = [machine.Pin(i, machine.Pin.OUT) for i in range(25, 33)]
    CLK, RST_N, ENA = machine.Pin(16, machine.Pin.OUT), machine.Pin(14, machine.Pin.OUT), machine.Pin(15, machine.Pin.OUT)
else: # v2.0/v3.1 (RP2040)
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
