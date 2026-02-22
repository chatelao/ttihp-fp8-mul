# Local Setup & Build Instructions

This guide provides instructions for setting up your local environment and running simulations for the **8-bit (E4M3) Floating Point Multiplier** Tiny Tapeout project.

## Prerequisites

To run simulations and develop locally, you need the following tools:

- **Icarus Verilog**: Open-source Verilog simulation and synthesis tool.
- **Python 3**: For running `cocotb`-based tests.
- **pip**: Python package manager.
- **venv**: Python virtual environment module (often part of `python3-venv`).
- **GTKWave**: (Optional) For viewing simulation waveforms.

### Installation

#### Ubuntu / Debian
```bash
sudo apt-get update
sudo apt-get install iverilog python3 python3-pip python3-venv gtkwave
```

#### macOS (using Homebrew)
```bash
brew install icarus-verilog gtkwave
```

## Environment Setup

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd <repository-directory>
   ```

2. **Install Python dependencies**:
   It is recommended to use a virtual environment:
   ```bash
   cd test
   python3 -m venv venv
   source venv/bin/activate
   pip install -r requirements.txt
   ```

## Running Simulations

The project uses `cocotb` for testing. Simulations are run from the `test/` directory.

### RTL Simulation
To run the functional RTL simulation:
```bash
cd test
make
```

This will:
1. Compile the Verilog source code (`src/project.v`) and the testbench wrapper (`test/tb.v`).
2. Run the tests defined in `test/test.py`.
3. Generate a waveform file `tb.fst`.

### Gate-Level Simulation
Gate-level simulation requires the PDK and the synthesized netlist.
```bash
make GATES=yes
```
*Note: This step is typically performed after the GDS hardening process.*

## Viewing Waveforms

After running a simulation, you can view the resulting waveforms using GTKWave:
```bash
gtkwave tb.fst tb.gtkw
```

## ASIC Flow (GDS Generation)

The GDS generation (hardening) is handled by GitHub Actions using the Tiny Tapeout flow. To run it locally, you would need to set up the OpenLane/LibreLane environment. Refer to the [Tiny Tapeout documentation](https://tinytapeout.com/guides/local-hardening/) for more details.
