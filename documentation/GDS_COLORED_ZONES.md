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
The visualization is automated using a Python script interacting with the **KLayout** API. The script processes the GDS, identifies instances by their hierarchical names, and generates an annotated image by creating unique visualization layers for each submodule category.

### 4.1. Implementation Script (`gds_colorizer.py`)

```python
import klayout.db as db
import klayout.lay as lay
import os
import sys
import glob

def colorize_gds(input_gds, output_png):
    # 1. Load the layout
    layout = db.Layout()
    layout.read(input_gds)
    top_cell = layout.top_cell()
    print(f"Loaded {input_gds}, top cell: {top_cell.name}")

    # 2. Define Submodule Configuration
    # Mapping submodule patterns to colors and unique layer indices
    submodule_config = {
        'multiplier':   {'color': 0xE63946, 'layer': 1001}, # Red
        'aligner_inst': {'color': 0xF1FAEE, 'layer': 1002}, # Light
        'acc_inst':     {'color': 0x457B9D, 'layer': 1003}, # Blue
        'top_control':  {'color': 0xA8DADC, 'layer': 1004}  # Cyan
    }

    # 3. Setup View (Headless mode for standalone klayout pip package)
    view = lay.LayoutView()
    view.show_layout(layout, False)

    # 4. Identify and Annotate Submodules
    for pattern, config in submodule_config.items():
        # Create a unique visualization layer for this submodule category
        idx = layout.layer(config['layer'], 0, f"Highlight_{pattern}")

        # Search for instances matching the pattern
        found_instances = False
        # Search for instances in the top cell
        for inst in top_cell.each_inst():
            # In klayout.db, Instance objects don't have a 'name' attribute like they might in GUI
            # We match against the cell name they point to.
            cell_name = inst.cell.name.lower()

            if pattern in cell_name:
                # Add a colored rectangle on the specific visualization layer
                top_cell.shapes(idx).insert(inst.bbox())
                found_instances = True
                print(f"Found {pattern} in instance pointing to cell {inst.cell.name}")

        if found_instances:
            # Set layer properties for this specific layer index
            lp = lay.LayerPropertiesNode()
            lp.source_layer_index = idx
            lp.fill_color = config['color']
            lp.frame_color = 0x000000
            lp.width = 1
            lp.dither_pattern = 1 # Solid
            view.insert_layer(view.end_layers(), lp)
        else:
            print(f"Warning: No instances found for pattern '{pattern}'")

    # 5. Export Visualization
    view.zoom_fit()
    view.save_image(output_png, 1024, 768)
    print(f"Visualization saved to {output_png}")

if __name__ == "__main__":
    # Robust search for GDS/OAS files in current and subdirectories
    possible_extensions = ["*.gds", "*.oas"]
    found_files = []
    for ext in possible_extensions:
        found_files.extend(glob.glob(f"**/{ext}", recursive=True))

    # Filter out files in .git or other common hidden dirs if needed
    found_files = [f for f in found_files if ".git" not in f]

    print(f"Scanning for layout files. Found: {found_files}")

    gds_path = None
    if found_files:
        # Prioritize files that look like our top module
        top_module = "tt_um_chatelao_fp8_multiplier"
        for f in found_files:
            if top_module in f:
                gds_path = f
                break

        # Fallback to the first one found if no exact match
        if not gds_path:
            gds_path = found_files[0]

    if gds_path:
        output_png = "gds_colored_zones.png"
        colorize_gds(gds_path, output_png)
    else:
        print(f"Error: No GDS or OAS layout files found in recursive search.")
        sys.exit(1)
```

## 5. Integration with CI/CD
The `viewer` job in the `.github/workflows/gds.yaml` pipeline can be enhanced to execute this script. Since KLayout's image export requires a display, `xvfb-run` is used for headless environments.

```yaml
  viewer:
    needs: gds
    steps:
      - name: Generate Colored Visualization
        run: |
          sudo apt-get install -y xvfb
          pip install klayout
          xvfb-run python3 gds_colorizer.py
```

This allows for immediate visual confirmation of physical floorplan changes across different commits, ensuring that critical arithmetic components are optimally placed.
