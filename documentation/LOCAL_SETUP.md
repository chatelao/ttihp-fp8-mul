# LOCAL SETUP GUIDE (WSL2 / UBUNTU)

This guide provides instructions for setting up the development environment locally on Windows Subsystem for Linux (WSL2) with Ubuntu, or any Debian-based Linux distribution.

## 1. System Requirements

- **WSL2** with **Ubuntu 24.04** (recommended).
- **Python 3.11+**
- **Git**

## 2. Toolchain Installation

### A. RTL Simulation (Icarus Verilog & Cocotb)

Install Icarus Verilog and Python dependencies:

```bash
sudo apt-get update
sudo apt-get install -y iverilog python3-pip python3-venv
```

Install the Python testing framework (recommended to use a virtual environment):

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r test/requirements.txt
```

*Note: On Ubuntu 24.04+, `pip install` outside a virtual environment may fail with an "externally-managed-environment" error.*

### B. Synthesis & Gate Analysis (Yosys)

Install Yosys for gate-level estimation and analysis:

```bash
sudo apt-get install -y yosys
```

### C. FPGA Bitstream Generation (OSS CAD Suite)

For Gowin FPGA (Tang Nano 4K) support, it is recommended to use **OSS CAD Suite**, which provides a pre-built collection of open-source tools (Yosys, nextpnr-gowin, gowin_pack).

1. Download the latest release from [YosysHQ/oss-cad-suite-build](https://github.com/YosysHQ/oss-cad-suite-build/releases).
2. Extract the archive to a local directory (e.g., `~/oss-cad-suite`).
3. Add the `bin` directory to your `PATH`:

```bash
export PATH=$HOME/oss-cad-suite/bin:$PATH
```

### D. Waveform Viewing (GTKWave)

To view simulation results (`.fst` or `.vcd` files):

```bash
sudo apt-get install -y gtkwave
```

*Note: If using WSL, you will need an X-Server (like GWSL or VcXsrv) or use the WSLg feature in Windows 11 to run GUI applications.*

## 3. Running Common Tasks

### Run RTL Simulation

```bash
make -C test clean
make -C test
```

To test specific hardware variants (Lite, Tiny):

```bash
# Lite Configuration
export COMPILE_ARGS="-P tb.SUPPORT_MXFP6=0 -P tb.SUPPORT_MXFP4=0"
make -C test clean && make -C test

# Tiny Configuration
export COMPILE_ARGS="-P tb.SUPPORT_MXFP6=0 -P tb.SUPPORT_MXFP4=0 -P tb.SUPPORT_ADV_ROUNDING=0 -P tb.SUPPORT_MIXED_PRECISION=0 -P tb.ENABLE_SHARED_SCALING=0"
make -C test clean && make -C test
```

### Run Gate Impact Analysis

```bash
python3 test/gate_analysis.py
```

### Generate FPGA Bitstream (Gowin)

Ensure OSS CAD Suite is in your path, then run:

```bash
mkdir -p build
# Synthesis
yosys -p "read_verilog -sv src/project.v src_gowin/tt_gowin_top.v; hierarchy -top tt_gowin_top; synth_gowin -top tt_gowin_top; write_json build/gowin.json"
# Place and Route
nextpnr-gowin --json build/gowin.json --write build/gowin_pnr.json --device GW1NSR-LV4CQN48PC6/I5 --family GW1NS-4 --top tt_gowin_top --freq 27 --cst src_gowin/tangnano4k.cst
# Pack
gowin_pack -d GW1NS-4 -o build/tangnano4k.fs build/gowin_pnr.json
```

## 4. Local ASIC Hardening

To harden the design locally (generate GDSII) using the Tiny Tapeout toolchain:

1. Install [Docker](https://docs.docker.com/desktop/wsl/).
2. Follow the [Tiny Tapeout Local Hardening Guide](https://www.tinytapeout.com/guides/local-hardening/):
   - Use the `tt` command-line tool.
   - Or use the [LibreLane](https://github.com/TinyTapeout/tt-gds-action) environment directly.

```bash
# Example using tt tool (if installed)
tt harden
```
