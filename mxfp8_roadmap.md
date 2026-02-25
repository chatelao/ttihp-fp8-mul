# Roadmap: MXFP8 Implementation on Tiny Tapeout

This roadmap outlines the steps required to implement the OCP MXFP8 Streaming MAC Unit on a single 1x1 tile.

## Phase 1: Specification & Design
- [ ] **Protocol Finalization**: Define exact signal timing for `ui_in` and `uio_in` transitions.
- [ ] **Arithmetic Precision**: Determine the internal bit-width of the fixed-point accumulator to prevent overflow during 32-element summation.
- [ ] **Rounding Policy**: Implement rounding logic (e.g., Round-to-Nearest-Even) or justify truncation for area savings.

## Phase 2: RTL Development
- [ ] **FSM Implementation**: Create the state machine for the 38-cycle streaming protocol (IDLE, LOAD_SCALE, STREAM, OUTPUT).
- [ ] **Multiplier Core**: Write the combinatorial logic for MXFP8 (E4M3/E5M2) multiplication (Sign XOR, Exp Add, Mantissa Mult).
- [ ] **Alignment Logic**: Implement the barrel shifter to convert floating-point products to the fixed-point accumulator format.
- [ ] **Accumulator Unit**: Integrate the 32-bit register and adder.
- [ ] **Top-Level Wrapper**: Connect the core to `tt_um_` template and handle UIO configurations.

## Phase 3: Verification (Cocotb)
- [ ] **Python Model**: Develop a bit-accurate Python reference model for OCP MXFP8.
- [ ] **Basic Testbench**: Verify that the FSM correctly transitions through all 38 states.
- [ ] **Randomized Testing**: Run 10,000+ randomized vector tests against the Python model.
- [ ] **Corner Cases**: Verify behavior with zeros, infinities (if supported), and maximum/minimum values.

## Phase 4: Synthesis & Physical Design
- [ ] **Initial Synthesis**: Run OpenLane and evaluate area utilization (target < 320 DFFs).
- [ ] **Timing Closure**: Ensure the design meets setup/hold requirements at 50 MHz.
- [ ] **Gate-Level Simulation (GLS)**: Run the Cocotb testbench against the synthesized netlist.
- [ ] **LVS/DRC Check**: Verify that the layout passes all IHP SG13G2 / Sky130 design rules.

## Phase 5: Documentation & Integration
- [ ] **info.yaml**: Update project metadata, source file list, and pinout descriptions.
- [ ] **Documentation**: Write detailed "How it works" and "How to test" sections in `docs/info.md`.
- [ ] **Diagrams**: Generate a logic diagram for the streaming architecture.

## Phase 6: Submission
- [ ] **Pre-check**: Run the Tiny Tapeout pre-check actions locally or in CI.
- [ ] **Final Submission**: Tag the repository and submit to the desired shuttle.
