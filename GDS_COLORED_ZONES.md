# Concept: GDS Submodule Colored Zones

## 1. Overview
This concept outlines the visualization of the physical layout for the OCP MXFP8 Streaming MAC Unit. To facilitate physical verification and area analysis, each submodule is assigned a distinct color in the GDS (Graphic Database System) viewer. This methodology improves observability by highlighting the relative placement and density of each functional block within the silicon layout.

## 2. Functional Submodules
The Streaming MAC Unit is organized into several key modules, as defined in `src/project.v`:

- **Multiplier (`multiplier`)**: Implements the `fp8_mul.v` core for signed 8x8 multiplication with independent format decoding.
- **Aligner (`aligner_inst`)**: Implements the `fp8_aligner.v` logic for 32-bit alignment and hardware-accelerated shared scaling.
- **Accumulator (`acc_inst`)**: Implements the `accumulator.v` module for 32-bit signed storage and overflow handling.
- **Control Logic**: Includes the 41-cycle Finite State Machine (FSM) and protocol management.

## 3. Proposed Coloring Scheme
To distinguish submodules, the following color scheme is proposed for the layout visualization:

| Submodule | Color (Hex) | Purpose |
|-----------|-------------|---------|
| `multiplier` | #E63946 | High-activity arithmetic core (Red) |
| `aligner_inst` | #F1FAEE | Data normalization and shifting (Light) |
| `acc_inst` | #457B9D | 32-bit state storage and addition (Blue) |
| `top_control` | #A8DADC | FSM and synchronization logic (Cyan) |

## 4. Visualization Methodology
The visualization can be automated using the **KLayout** Python API during the ASIC hardening flow.

### 4.1. Identification Strategy
Submodules are identified by their hierarchical names in the synthesized netlist:
- `tt_um_chatelao_fp8_multiplier/multiplier`
- `tt_um_chatelao_fp8_multiplier/aligner_inst`
- `tt_um_chatelao_fp8_multiplier/acc_inst`

### 4.2. Implementation via KLayout API (Conceptual)
```python
import pya

# Load the GDS layout from the hardening run
layout = pya.Layout()
layout.read("tt_um_chatelao_fp8_multiplier.gds")

# Apply coloring logic based on submodule hierarchy
# ... (Automated highlighting script)
```

## 5. Integration with CI/CD
The `viewer` job in the `.github/workflows/gds.yaml` pipeline can be enhanced to output colored layout snapshots (`logic_diagram_colored.png`) automatically. This allows for immediate visual confirmation of physical floorplan changes across different commits.
