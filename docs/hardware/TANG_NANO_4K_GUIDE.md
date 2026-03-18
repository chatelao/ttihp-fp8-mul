# Tang Nano 4K - OCP MXFP8 MAC Guide

This guide provides comprehensive instructions for building, flashing, and testing the OCP MXFP8 Streaming MAC Unit on the **Sipeed Tang Nano 4K** (Gowin GW1NSR-4C).

## 1. Introduction

The OCP MXFP8 Streaming MAC Unit is a high-performance, area-efficient arithmetic core designed for Tiny Tapeout. This guide allows you to run the same hardware logic on a Tang Nano 4K FPGA for real-time verification and testing.

## 2. Prerequisites

### A. Hardware Requirements
- **Sipeed Tang Nano 4K** board.
- **USB-C Cable** for flashing and power.
- **External Controller** (optional, e.g., Arduino, ESP32, or RP2040) for driving the 41-cycle protocol.

### B. Software Toolchain (OSS CAD Suite)
The project uses an open-source toolchain for Gowin FPGAs. It is highly recommended to use the **OSS CAD Suite**.

1. **Download**: Get the latest release from [YosysHQ/oss-cad-suite-build](https://github.com/YosysHQ/oss-cad-suite-build/releases).
2. **Setup**: Extract the archive and add the `bin` directory to your `PATH`:
   ```bash
   export PATH=$HOME/oss-cad-suite/bin:$PATH
   ```
3. **Dependencies**: Install Python dependencies for Apycula (Gowin documentation project):
   ```bash
   pip install numpy fastcrc
   ```

### C. Flashing Tool
To flash the generated bitstream (`.fs` file) to the Tang Nano 4K, you can use:
- **openFPGALoader**: A universal utility for flashing FPGAs (highly recommended).
- **Gowin Programmer**: The official (proprietary) tool from Gowin Semiconductor.

## 3. Build Process (Synthesis, P&R, and Packing)

The OCP MXFP8 Streaming MAC Unit is available in several pre-configured hardware variants. The build process involves three main stages: synthesis (Yosys), place-and-route (nextpnr-gowin), and bitstream packing (gowin_pack).

### A. Define Your Hardware Variant

The following table summarizes the key parameter configurations for each variant:

| Parameter | Full | Lite | Tiny | Ultra-Tiny | Tiny-Serial |
|-----------|------|------|------|------------|-------------|
| ALIGNER_WIDTH | 40 | 40 | 40 | 32 | 32 |
| ACCUMULATOR_WIDTH | 32 | 32 | 32 | 24 | 24 |
| SUPPORT_E4M3 | 1 | 1 | 1 | 1 | 0 |
| SUPPORT_E5M2 | 1 | 1 | 0 | 0 | 0 |
| SUPPORT_MXFP6 | 1 | 0 | 0 | 0 | 0 |
| SUPPORT_MXFP4 | 1 | 1 | 0 | 0 | 1 |
| SUPPORT_INT8 | 1 | 1 | 0 | 0 | 0 |
| SUPPORT_PIPELINING | 1 | 1 | 0 | 0 | 0 |
| SUPPORT_ADV_ROUNDING | 1 | 0 | 0 | 0 | 0 |
| SUPPORT_MIXED_PRECISION | 1 | 1 | 0 | 0 | 0 |
| SUPPORT_VECTOR_PACKING | 1 | 0 | 0 | 0 | 0 |
| ENABLE_SHARED_SCALING | 1 | 1 | 0 | 0 | 0 |
| SUPPORT_MX_PLUS | 1 | 0 | 0 | 0 | 0 |
| SUPPORT_INPUT_BUFFERING | 1 | 0 | 0 | 0 | 0 |
| SUPPORT_SERIAL | 0 | 0 | 0 | 0 | 1 |

### B. Synthesis (Yosys)

Use the following command to synthesize the design. Replace `${PARAMS}` with the specific set of parameters for your chosen variant (e.g., `-set ALIGNER_WIDTH 40 -set SUPPORT_E5M2 1 ...`).

```bash
mkdir -p build
yosys -p "read_verilog -Isrc -sv src/project.v src_gowin/tt_gowin_top.v; chparam ${PARAMS} tt_gowin_top; synth_gowin -top tt_gowin_top; write_json build/gowin.json"
```

### C. Place and Route (nextpnr-gowin)

Run the place-and-route tool to generate a P&R JSON file. The target frequency is set to **27MHz** (Tang Nano 4K onboard clock).

```bash
nextpnr-gowin --json build/gowin.json \
              --write build/gowin_pnr.json \
              --device GW1NSR-LV4CQN48PC6/I5 \
              --family GW1NS-4 \
              --top tt_gowin_top \
              --freq 27 \
              --cst src_gowin/tangnano4k.cst
```

### D. Pack Bitstream (gowin_pack)

Finally, generate the `.fs` bitstream file that will be flashed to the FPGA:

```bash
gowin_pack -d GW1NS-4 -o build/tangnano4k.fs build/gowin_pnr.json
```

## 4. Physical Connection and Wiring

The following table maps the design's internal signals to the physical pins on the Tang Nano 4K.

### A. Pin Mapping Table

| Design Signal | Tang Nano 4K Pin | Description |
|---------------|------------------|-------------|
| `ui_in[7]`    | 40               | Metadata / Scale A / Element A [7] |
| `ui_in[6]`    | 39               | Metadata / Scale A / Element A [6] |
| `ui_in[5]`    | 35               | Metadata / Scale A / Element A [5] |
| `ui_in[4]`    | 34               | Metadata / Scale A / Element A [4] |
| `ui_in[3]`    | 33               | Metadata / Scale A / Element A [3] |
| `ui_in[2]`    | 32               | Metadata / Scale A / Element A [2] |
| `ui_in[1]`    | 31               | Metadata / Scale A / Element A [1] |
| `ui_in[0]`    | 30               | Metadata / Scale A / Element A [0] |
| `uo_out[7]`   | 9                | Output Result Byte [7] |
| `uo_out[6]`   | 8                | Output Result Byte [6] |
| `uo_out[5]`   | 7                | Output Result Byte [5] |
| `uo_out[4]`   | 22               | Output Result Byte [4] |
| `uo_out[3]`   | 44               | Output Result Byte [3] |
| `uo_out[2]`   | 43               | Output Result Byte [2] |
| `uo_out[1]`   | 42               | Output Result Byte [1] |
| `uo_out[0]`   | 41               | Output Result Byte [0] |
| `uio[7]`      | 21               | Metadata / Scale B / Element B [7] |
| `uio[6]`      | 20               | Metadata / Scale B / Element B [6] |
| `uio[5]`      | 19               | Metadata / Scale B / Element B [5] |
| `uio[4]`      | 18               | Metadata / Scale B / Element B [4] |
| `uio[3]`      | 17               | Metadata / Scale B / Element B [3] |
| `uio[2]`      | 16               | Metadata / Scale B / Element B [2] |
| `uio[1]`      | 13               | Metadata / Scale B / Element B [1] |
| `uio[0]`      | 10               | Metadata / Scale B / Element B [0] |
| `clk`         | 45               | System Clock (27MHz Onboard) |
| `rst_n`       | 15               | Active-Low Reset (Button S1) |
| `ena`         | 14               | Active-High Enable (Button S2) |

*Note: For `uio` pins, ensure they are configured as inputs on your controller when the MAC unit is in the input phase (Cycles 0-34).*

### B. Suggested Connections
- **Ground (GND)**: Connect the ground of your controller to any GND pin on the Tang Nano 4K.
- **Power (3.3V/5V)**: The Tang Nano 4K is typically powered via USB-C. Ensure common power levels if interfacing with 5V logic (use level shifters if necessary, as the Tang Nano 4K is 3.3V).

## 5. Flashing the Bitstream

Once you have generated the `build/tangnano4k.fs` file, use one of the following methods to flash it.

### A. Using a Compatible FPGA Loader
You can use any open-source tool compatible with the Gowin GW1NSR-4C, such as those that interface with the onboard BL702 JTAG bridge.

```bash
# General command for flashing to SRAM (temporary)
<loader_tool> --device tangnano4k build/tangnano4k.fs

# General command for flashing to External Flash (persistent)
<loader_tool> --device tangnano4k --flash build/tangnano4k.fs
```

### B. Using the Official Gowin Programmer
1. Open the **Gowin Programmer** tool.
2. Click **Scan Device** and select the GW1NSR-4C.
3. In the **Operation** column, select **Embedded Flash Mode**.
4. Browse to your `build/tangnano4k.fs` file and click **Program/Configure**.

---

## 6. Testing Methodology (41-Cycle Protocol)

The MAC unit operates on a fixed 41-cycle protocol for each dot product calculation. This section details how to drive the design using an external controller.

### A. Operational Phases

| Phase | Cycles | Description |
|-------|--------|-------------|
| **Init** | - | Drive `rst_n` LOW for 10ms, then HIGH. Keep `ena` HIGH. |
| **IDLE** | 0 | **Cycle 0**: Load initial metadata (Rounding, Overflow, etc.) on `uio_in`. |
| **Scale A** | 1 | **Cycle 1**: Drive Scale A on `ui_in` and Format A / BM Index A on `uio_in`. |
| **Scale B** | 2 | **Cycle 2**: Drive Scale B on `ui_in` and Format B / BM Index B on `uio_in`. |
| **Stream** | 3–34 | **Cycles 3–34**: Drive 32 pairs of elements ($A_i$ on `ui_in`, $B_i$ on `uio_in`). |
| **Flush** | 35 | **Cycle 35**: Pipeline flush. Drive all inputs to 0x00. |
| **Scale** | 36 | **Cycle 36**: Final shared scaling calculation. Drive all inputs to 0x00. |
| **Output** | 37–40 | **Cycles 37–40**: Read 32-bit result (signed fixed-point) from `uo_out` (MSB first). |

### B. Sample Walkthrough (1.0 * 1.0 Dot Product)

This example calculates the dot product of two 32-element vectors where every element is 1.0.

- **Format**: E4M3 (0x38 = 1.0)
- **Scale A & B**: 127 (1.0 multiplier)
- **Expected Result**: 32.0 (Stored as 0x2000 in 24.8 fixed-point)

**Step-by-Step Sequence:**

1. **Cycle 1**: Set `ui_in = 127` (Scale A) and `uio_in = 0x00` (Format A = E4M3). Clock the unit.
2. **Cycle 2**: Set `ui_in = 127` (Scale B) and `uio_in = 0x00` (Format B = E4M3). Clock the unit.
3. **Cycles 3-34**: Set `ui_in = 0x38` and `uio_in = 0x38`. Clock the unit 32 times.
4. **Cycles 35-36**: Set `ui_in = 0x00` and `uio_in = 0x00`. Clock the unit 2 times.
5. **Cycle 37**: Read `uo_out` -> Expected: `0x00` (Byte 3, MSB).
6. **Cycle 38**: Read `uo_out` -> Expected: `0x00` (Byte 2).
7. **Cycle 39**: Read `uo_out` -> Expected: `0x20` (Byte 1).
8. **Cycle 40**: Read `uo_out` -> Expected: `0x00` (Byte 0, LSB).

**Final Result Construction:**
`0x00002000` = 8192.
Dividing by the fractional scale (2^8 = 256): `8192 / 256.0 = 32.0`.
