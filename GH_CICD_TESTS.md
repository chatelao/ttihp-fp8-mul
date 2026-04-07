# GitHub CI/CD Tests and Workflows

This document provides a detailed description of the tests and build processes executed by the various GitHub Actions workflows in this repository.

## Overview of Workflows

| Workflow | Trigger | Description |
| :--- | :--- | :--- |
| [Linter](#linter-lintyaml) | Push, PR, Manual | Static analysis of Verilog code. |
| [Functional Tests](#functional-tests-testyaml) | Push, Manual | RTL simulation and functional verification across multiple configurations. |
| [GDS & ASIC Flow](#gds--asic-flow-gdsyaml) | Push, Manual | Hardening the design, pre-checks, and gate-level simulation. |
| [Gowin FPGA Build](#gowin-fpga-build-gowinyaml) | Push, Manual, Release | FPGA synthesis and bitstream generation for Tang Nano 4K. |
| [WASM Digital Twin](#wasm-digital-twin-wasmyaml) | Push, Manual, Release | Compiling the HDL to WebAssembly for the interactive demo. |
| [Diagram Generation](#diagram-generation-diagramyaml) | Push, Manual | Automatic generation of logic and RTL diagrams. |
| [Documentation](#documentation-docsyaml) | Push, Manual | Building project documentation from source files. |
| [FPGA ASIC Sim](#fpga-asic-sim-fpgayaml) | Manual | Building bitstream for iCE40UP5K for ASIC-like simulation. |

---

## Linter (lint.yaml)
- **Triggers**: `push`, `pull_request`, `workflow_dispatch`.
- **Purpose**: Ensures code quality and catches common Verilog errors early.
- **Key Steps**:
  - Installs `verilator`.
  - Executes: `verilator --lint-only -Wall -Isrc/ --top-module tt_um_chatelao_fp8_multiplier src/project.v`.
- **Artifacts**: None.

## Functional Tests (test.yaml)
- **Triggers**: `push`, `workflow_dispatch`.
- **Matrix**: Executes for 5 configurations: `Full`, `Lite`, `Tiny`, `Ultra-Tiny`, `Tiny-Serial`.
- **Specific Tests**:
  - **Gate Analysis** (Full config only): Runs `test/gate_analysis.py` to generate gate-level statistics.
  - **M3 Integration Check** (Full config only): Verifies that the design compiles correctly with Cortex-M3 integration flags (`M3_MODE_GPIO`, `M3_MODE_APB`, `M3_MODE_AHB`) using `iverilog`.
  - **Cocotb Tests**: Runs the `make` command in the `test/` directory. This executes the following test modules:
    - `test`: General functional tests.
    - `test_coverage`: Code coverage analysis.
    - `test_performance`: Latency and throughput measurements.
    - `test_short_protocol`: Verification of the "Short Protocol" feature.
    - `test_exhaustive`: Extensive randomized testing.
- **Artifacts**: `test-results-${config}` containing `tb.fst`, `tb.vcd`, `results.xml`, and the `output/` directory.

## GDS & ASIC Flow (gds.yaml)
- **Triggers**: `push`, `workflow_dispatch`.
- **Jobs**:
  - **Build GDS**: Uses `TinyTapeout/tt-gds-action` with the `ihp-sg13cmos5l` PDK to perform synthesis and place-and-route.
  - **Precheck**: Runs the Tiny Tapeout Precheck suite to ensure compliance with submission requirements.
  - **Gate-Level (GL) Test**: Runs functional tests against the generated gate-level netlist to ensure post-synthesis correctness.
  - **Viewer**: Generates a colored GDS visualization (`gds_colored_zones.png`) and deploys the GDS viewer to GitHub Pages.
- **Artifacts**: GDS files, precheck results, GL test results, and visualization images.

## Gowin FPGA Build (gowin.yaml)
- **Triggers**: `push`, `workflow_dispatch`, `release`.
- **Matrix**: Variants include standard configurations (`Full` to `Tiny-Serial`) and Cortex-M3 integration modes (`M3-GPIO`, `M3-APB`, `M3-AHB`, `M3-AHB-DMA`).
- **Key Steps**:
  - **RTL Verification**: Runs `test/verify_rtl.py`.
  - **Synthesis**: Uses Yosys with Gowin-specific parameters.
  - **Place & Route**: Uses `nextpnr-gowin` (targeting `GW1NSR-LV4CQN48PC6/I5`).
  - **Bitstream**: Generates `.fs` files using `gowin_pack`.
- **Artifacts**: `gowin_bitstream_${variant}` bitstream files.

## WASM Digital Twin (wasm.yaml)
- **Triggers**: `push`, `workflow_dispatch`, `release`.
- **Matrix**: All 5 standard configurations.
- **Key Steps**:
  - Compiles the Verilog source to C++ using `verilator`.
  - Compiles the C++ wrapper to WebAssembly (WASM) using `emscripten`.
  - For the `Full` variant, it deploys the interactive demo (including `index.html` and `main.js` from `docs/web/`) to the `/demo` subdirectory on GitHub Pages.
- **Artifacts**: `wasm_digital_twin_${variant}` (.js and .wasm files).

## Diagram Generation (diagram.yaml)
- **Triggers**: `push`, `workflow_dispatch`.
- **Purpose**: Visualizes the hardware architecture.
- **Outputs**:
  - **Standard Logic Diagram**: Top-level module visualization.
  - **Flattened RTL Diagram**: Mid-level resolution diagram.
  - **Full Render** (Optional): Gate-level and transitive reduction diagrams (enabled via manual trigger).
- **Artifacts**: `logic-diagram` (PNG and SVG files).

## Documentation (docs.yaml)
- **Triggers**: `push`, `workflow_dispatch`.
- **Process**: Uses the Tiny Tapeout documentation action to generate a datasheet and project documentation from `docs/info.md` and `info.yaml`.

## FPGA ASIC Sim (fpga.yaml)
- **Triggers**: `workflow_dispatch` (effectively).
- **Process**: Generates a bitstream for the iCE40UP5K FPGA (Lattice iCEBreaker or similar) that mimics the ASIC pinout for physical testing prior to tapeout.
