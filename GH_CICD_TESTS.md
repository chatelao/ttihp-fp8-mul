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
  - **Cocotb Tests**: Runs the `make` command in the `test/` directory. See the [Cocotb Test Suite Details](#cocotb-test-suite-details) section for a full list of verified scenarios.
- **Artifacts**: `test-results-${config}` containing `tb.fst`, `tb.vcd`, `results.xml`, and the `output/` directory.

---

## Cocotb Test Suite Details

The project utilizes `cocotb` for RTL verification, with tests categorized into functional modules.

### General Functional & Arithmetic (`test.py`)
| Test Function | Description |
| :--- | :--- |
| `test_mxfp8_mac_shared_scale` | Verifies basic MAC operation with shared scaling for E4M3 elements. |
| `test_mxfp8_mac_e4m3` | Validates standard E4M3 MAC execution. |
| `test_mxfp8_mac_e5m2` | Validates standard E5M2 MAC execution. |
| `test_rounding_modes` | Tests TRN (Truncate), CEL (Ceiling), FLR (Floor), and RNE (Round to Nearest Even) modes. |
| `test_overflow_saturation` | Verifies result saturation on exponent overflow. |
| `test_accumulator_saturation` | Checks 32-bit signed fixed-point accumulator saturation and wrap-around. |
| `test_mixed_precision` | Validates MAC operations between different formats (e.g., E4M3 x E5M2). |
| `test_mxfp8_subnormals` | Verifies correct handling of subnormal numbers in E4M3. |
| `test_mxfp8_sticky_flags` | Validates NaN and Infinity sticky flag propagation. |
| `test_lns_modes` | Tests Mitchell-based Logarithmic Number System (LNS) and Hybrid multiplication modes. |
| `test_lane_overflow` | Checks saturation logic in dual-lane vector packing to prevent intermediate wrap-around. |
| `test_yaml_cases` | Executes end-to-end test cases defined in `TEST_MX_E2E.yaml`. |
| `test_mx_fp4_yaml` | Executes FP4-specific test cases from `TEST_MX_FP4.yaml`. |
| `test_min_max_zero_yaml` | Validates extreme numerical boundaries from `TEST_MIN_MAX_ZERO.yaml`. |
| `test_mxplus_yaml` | Verifies OCP MX+ (Extended Mantissa) functionality using `TEST_MXPLUS.yaml`. |

### Protocol & Features (`test_short_protocol.py`, `test.py`)
| Test Function | Description |
| :--- | :--- |
| `test_mxfp4_packed` | Verifies hardware vector packing for FP4 elements. |
| `test_mxfp4_packed_serial` | Validates serial-packed protocol for resource-constrained configurations. |
| `test_mxfp4_input_buffering` | Tests the input buffering mechanism for burst data loading. |
| `test_short_protocol_metadata` | Verifies Cycle 0 metadata capture and skip-ahead in the Short Protocol. |
| `test_short_protocol_nan_scale_reuse` | Validates scale reuse and NaN sticky bit persistence across Short Protocol blocks. |
| `test_fast_start_scale_compression` | Tests "Fast Start" (Cycle 0 [7]=1) for reusing previous scales and configurations. |

### Debug & Observability (`test_debug.py`)
| Test Function | Description |
| :--- | :--- |
| `test_debug_loopback` | Verifies the connectivity loopback mode (ui_in to uo_out). |
| `test_debug_probes` | Validates internal signal observability via logic analyzer probes (FSM state, cycles, control signals). |
| `test_debug_metadata_echo` | Verifies that internal configuration state is echoed correctly at the end of a block. |
| `test_uio_loopback` | Checks loopback functionality specifically for the bidirectional UIO pins. |
| `test_loopback_persistence` | Ensures debug modes persist across multiple operation cycles until reset. |

### Exhaustive & Coverage (`test_exhaustive.py`, `test_coverage.py`)
| Test Function | Description |
| :--- | :--- |
| `test_fp4_exhaustive` | Tests all 256 possible bit-pattern combinations for FP4 (E2M1). |
| `test_fp8_e4m3_mantissa_exhaustive` | Exhaustively tests the mantissa space for E4M3 normal numbers. |
| `test_fp8_e5m2_mantissa_exhaustive` | Exhaustively tests E5M2 mantissas, including subnormals. |
| `test_randomized_coverage` | Drives randomized inputs across all supported formats and modes to maximize code coverage. |
| `test_edge_cases` | Specifically targets numerical edge cases (Min/Max/NaN/Inf) for coverage. |

### Performance (`test_performance.py`)
| Test Function | Description |
| :--- | :--- |
| `performance_sweep` | Measures MAC throughput and cycles-per-block across multiple workloads. |
| `high_switching_activity` | Generates high-toggling input patterns for power analysis simulation. |

---

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
