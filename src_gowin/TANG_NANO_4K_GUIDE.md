# Tang Nano 4K Deployment & Testing Guide

This guide provides instructions for building, flashing, and verifying the OCP MXFP8 Streaming MAC Unit on the **Sipeed Tang Nano 4K** FPGA development board.

## 1. Prerequisites

### Hardware
- **Sipeed Tang Nano 4K** (Gowin GW1NSR-LV4CQN48PC6/I5)
- USB-C cable for flashing and power.
- (Optional) Logic Analyzer or MicroPython-compatible MCU (e.g., Raspberry Pi Pico) for protocol verification.

### Software Toolchain
It is recommended to use the **OSS CAD Suite** for an open-source workflow:
- **Yosys**: Synthesis.
- **nextpnr-gowin**: Place and Route.
- **Gowin_pack**: Bitstream generation (part of Apycula/project-apicula).
- **openFPGALoader**: Flashing tool.

Alternatively, you can use the official **Gowin EDA**.

## 2. Building the Bitstream

The project supports multiple variants. Use the following commands to generate the bitstream (`.fs` file) using the open-source toolchain.

### Step 1: Synthesis (Yosys)
Replace `${PARAMS}` with the desired variant configuration (see `../.github/workflows/gowin.yaml` for exact sets).

```bash
# Example for 'Full' variant
yosys -p "read_verilog -I../src -sv ../src/project.v tt_gowin_top.v; \
         chparam -set ALIGNER_WIDTH 40 -set ACCUMULATOR_WIDTH 32 -set SUPPORT_E4M3 1 \
                 -set SUPPORT_E5M2 1 -set SUPPORT_MXFP6 1 -set SUPPORT_MXFP4 1 \
                 -set SUPPORT_INT8 1 -set SUPPORT_PIPELINING 1 -set SUPPORT_ADV_ROUNDING 1 \
                 -set SUPPORT_MIXED_PRECISION 1 -set SUPPORT_VECTOR_PACKING 1 \
                 -set ENABLE_SHARED_SCALING 1 -set SUPPORT_MX_PLUS 1 \
                 -set SUPPORT_INPUT_BUFFERING 1 -set SUPPORT_SERIAL 0 tt_gowin_top; \
         synth_gowin -top tt_gowin_top; \
         write_json build/gowin.json"
```

### Step 2: Place and Route (nextpnr-gowin)
```bash
nextpnr-gowin --json build/gowin.json \
              --write build/gowin_pnr.json \
              --device GW1NSR-LV4CQN48PC6/I5 \
              --family GW1NS-4 \
              --top tt_gowin_top \
              --freq 20 \
              --cst tangnano4k.cst
```

### Step 3: Pack Bitstream
```bash
gowin_pack -d GW1NS-4 -o build/tangnano4k.fs build/gowin_pnr.json
```

---

## 3. Flashing

Connect your Tang Nano 4K to your PC via USB and use `openFPGALoader`:

```bash
# Flash to SRAM (volatile, lost after power cycle)
openFPGALoader -b tangnano4k build/tangnano4k.fs

# Flash to Flash (persistent)
openFPGALoader -b tangnano4k -f build/tangnano4k.fs
```

---

## 4. Pin Mapping & Connections

The following table maps the Tiny Tapeout signals to the physical pins of the Tang Nano 4K.

| TT Signal | Direction | Tang Nano 4K Pin | Bank / Voltage | On-board Hardware |
|:---:|:---:|:---:|:---:|---|
| `clk` | Input | 45 | Bank 1 (3.3 V) | 27 MHz Oscillator (divided ÷2 internally to 13.5 MHz) |
| `rst_n` | Input | 15 | Bank 3 (1.8 V) | Button **S2** (active-low, 2-FF synchronized) |
| `ena` | Input | 14 | Bank 3 (1.8 V) | Button **S1** (active-low, 2-FF synchronized) |
| `ui_in[7:0]` | Input | 34, 33, 32, 31, 30, 29, 28, 27 | Bank 2 (2.5 V) | HDMI header pins (do not exceed 2.5 V) |
| `uo_out[7:0]` | Output | 10, 46, 44, 43, 42, 41, 40, 39 | Bank 0/1 (3.3 V) | Pin 10 = onboard LED |
| `uio[7:0]` | Inout | 22, 21, 20, 19, 18, 17, 16, 13 | Bank 3 (1.8 V) | **1.8 V only** (HyperRAM bank) |

---

## 5. Testing Steps

### Step A: Connectivity Loopback (The "Smoke Test")
Before running complex arithmetic, verify that your wiring and the FPGA are communicating correctly.

1. Hold the board in **Reset** (Press **S2**, Pin 15).
2. Set `ui_in[7:0]` and `uio_in[7:0]` to known values.
3. Pulse **Reset** High (Release **S2**).
4. In **Cycle 0** (immediately after reset release), set `ui_in = 0x50` (`ui_in[6] = 1` Debug Mode and `ui_in[4] = 1` Loopback Enable; note that `ui_in[5]` is `float32_mode`).
5. The unit enters **Loopback Mode**. `uo_out` should now reflect `ui_in ^ uio_in`.
6. Vary the input pins and observe if `uo_out` updates correctly.

### Step B: Metadata Echo
Verify that the configuration logic is correctly sampling your inputs.

1. Enable **Debug Mode** by setting `ui_in[6] = 1` (and `ui_in[4] = 0`) in Cycle 0.
2. Proceed through Cycles 1 and 2 to load formats and scales.
3. At **Cycle 35** (Pipeline Flush), observe `uo_out`. It should echo the latched configuration:
   - `uo_out[2:0]`: Latched `format_a`
   - `uo_out[4:3]`: Latched `round_mode`
   - `uo_out[5]`: Latched `overflow_wrap`
   - `uo_out[6]`: Latched `packed_mode`
   - `uo_out[7]`: Latched `mx_plus_en`

### Step C: Standard MAC Operation
Run a full 32-element dot product. You can use a MicroPython script (see `../test/TT_MAC_RUN.PY`) or a logic analyzer.

**Example: 32.0 Dot Product ($1.0 \times 1.0$ for 32 elements)**
1. **Cycle 0**: `ui_in = 0x00`, `uio_in = 0x00` (Standard Start).
2. **Cycle 1**: `ui_in = 127` (Scale A=1.0), `uio_in = 0x00` (E4M3).
3. **Cycle 2**: `ui_in = 127` (Scale B=1.0), `uio_in = 0x00` (E4M3).
4. **Cycles 3-34**: `ui_in = 0x38` (1.0 in E4M3), `uio_in = 0x38` (1.0 in E4M3).
5. **Cycle 35-36**: Wait (Wait for pipeline and shared scaling).
6. **Cycles 37-40**: Read 32-bit result from `uo_out` (MSB first).
   - Expected Result: `0x00002000` (8192 in fixed-point, which is $8192 / 256.0 = 32.0$).

## 6. Automating Tests with MicroPython

If you have a Raspberry Pi Pico or similar MCU connected to the Tang Nano 4K pins, you can use the `../test/TT_MAC_RUN.PY` script as a template.

**Connection Tip**: Ensure a common ground between the Tang Nano 4K and your test controller. Respect per-bank I/O voltages: **Bank 0/1 = 3.3 V**, **Bank 2 = 2.5 V**, and **Bank 3 (Pins 13–23) = 1.8 V** (use level shifters before connecting 3.3 V logic to Bank 2 or Bank 3).
