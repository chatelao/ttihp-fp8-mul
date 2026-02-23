# Yosys Graphviz Logic Diagram Generation

This document describes how to generate and automate the creation of logic diagrams from the Verilog source code using Yosys and Graphviz.

## Overview
Visualizing the logic structure of a digital design helps in understanding the data flow and complexity. Yosys can generate a Graphviz `.dot` file representing the RTL schematic, which can then be converted to image formats like PNG or SVG.

## Local Generation

### Prerequisites
- [Yosys](https://yosyshq.net/yosys/)
- [Graphviz](https://graphviz.org/)

### Commands
To generate a logic diagram of the top-level module, run the following commands from the project root:

```bash
# 1. Use Yosys to generate a Graphviz .dot file
yosys -p "read_verilog src/project.v; hierarchy -top tt_um_chatelao_fp8_multiplier; proc; opt; show -format dot -prefix logic_diagram tt_um_chatelao_fp8_multiplier"

# 2. Use Graphviz 'dot' to convert to an image (PNG or SVG)
dot -Tpng logic_diagram.dot -o logic_diagram.png
# OR
dot -Tsvg logic_diagram.dot -o logic_diagram.svg
```

#### Explanation:
- `read_verilog src/project.v`: Loads the design.
- `hierarchy -top tt_um_chatelao_fp8_multiplier`: Sets the top module for the diagram.
- `proc`: Translates processes (always blocks) to netlist components.
- `opt`: Performs simple optimizations to make the diagram more readable.
- `show -format dot -prefix logic_diagram tt_um_chatelao_fp8_multiplier`: Generates the Graphviz file for the specified module.

### Flattened and Tech-Mapped Diagram
To generate a flattened diagram that shows the design mapped to the IHP SG13G2 standard cells, use the following commands:

```bash
# 1. Use Yosys with flatten and synth_ihp
yosys -p "read_verilog src/project.v; hierarchy -top tt_um_chatelao_fp8_multiplier; proc; flatten; synth_ihp -top tt_um_chatelao_fp8_multiplier; show -format dot -prefix logic_diagram_flattened tt_um_chatelao_fp8_multiplier"

# 2. Convert to PNG/SVG
dot -Tpng logic_diagram_flattened.dot -o logic_diagram_flattened.png
dot -Tsvg logic_diagram_flattened.dot -o logic_diagram_flattened.svg
```

- `flatten`: Replaces module instances with their contents.
- `synth_ihp`: Performs synthesis targeting the IHP SG13G2 technology. Note: This requires the IHP PDK and a compatible Yosys build.

## GitHub Actions Integration (Artifacts)

To automatically generate and attach the diagram as a build artifact on every push, you can add a new job to your GitHub Actions workflow.

### Example Workflow Snippet
Add this to a new file `.github/workflows/diagram.yaml` or append it to `.github/workflows/gds.yaml`:

```yaml
name: diagram
on:
  push:
  workflow_dispatch:

jobs:
  generate_diagram:
    runs-on: ubuntu-latest
    container: ghcr.io/tinytapeout/ttihp-sg13g2:latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install Graphviz
        run: apt-get update && apt-get install -y graphviz

      - name: Generate Logic Diagrams
        run: |
          # 1. Standard Logic Diagram
          yosys -p "read_verilog src/project.v; hierarchy -top tt_um_chatelao_fp8_multiplier; proc; opt; show -format dot -prefix logic_diagram tt_um_chatelao_fp8_multiplier"
          dot -Tpng logic_diagram.dot -o logic_diagram.png
          dot -Tsvg logic_diagram.dot -o logic_diagram.svg

          # 2. Flattened Logic Diagram targeting IHP SG13G2
          yosys -p "read_verilog src/project.v; hierarchy -top tt_um_chatelao_fp8_multiplier; proc; flatten; synth_ihp -top tt_um_chatelao_fp8_multiplier; show -format dot -prefix logic_diagram_flattened tt_um_chatelao_fp8_multiplier"
          dot -Tpng logic_diagram_flattened.dot -o logic_diagram_flattened.png
          dot -Tsvg logic_diagram_flattened.dot -o logic_diagram_flattened.svg

      - name: Upload Diagram Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: logic-diagram
          path: |
            logic_diagram.png
            logic_diagram.svg
            logic_diagram_flattened.png
            logic_diagram_flattened.svg
```

## Benefits
- **Documentation**: Easily include up-to-date schematics in `README.md` or `docs/info.md`.
- **Debugging**: Inspect the synthesized logic structure to verify that the RTL translates as expected.
- **Portability**: SVG format allows for high-quality, scalable diagrams that can be embedded in web pages.
