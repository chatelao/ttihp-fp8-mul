import pya
import os
import sys

def colorize_gds(input_gds, output_png):
    # 1. Load the layout
    layout = pya.Layout()
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

    # 3. Setup View (Handles both GUI and Headless/CI modes)
    main_window = pya.Application.instance().main_window()
    view = main_window.create_layout_view() if main_window else pya.LayoutView()
    view.show_layout(layout, False)

    # 4. Identify and Annotate Submodules
    for pattern, config in submodule_config.items():
        # Create a unique visualization layer for this submodule category
        idx = layout.layer(config['layer'], 0, f"Highlight_{pattern}")

        # Search for instances matching the pattern
        found_instances = False
        # Search for instances in the top cell
        for inst in top_cell.each_inst():
            # Check instance name or cell name
            inst_name = inst.name.lower() if inst.name else ""
            cell_name = inst.cell.name.lower()

            if pattern in inst_name or pattern in cell_name:
                # Add a colored rectangle on the specific visualization layer
                top_cell.shapes(idx).insert(inst.bbox())
                found_instances = True
                print(f"Found {pattern} in instance {inst.name} (cell {inst.cell.name})")

        if found_instances:
            # Set layer properties for this specific layer index
            lp = pya.LayerPropertiesNode()
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
    # Search for GDS in multiple locations
    possible_paths = [
        "tt_um_chatelao_fp8_multiplier.gds",
        "gds/tt_um_chatelao_fp8_multiplier.gds",
        "runs/wokwi/results/final/gds/tt_um_chatelao_fp8_multiplier.gds"
    ]

    gds_path = None
    for path in possible_paths:
        if os.path.exists(path):
            gds_path = path
            break

    if gds_path:
        output_png = "gds_colored_zones.png"
        colorize_gds(gds_path, output_png)
    else:
        print(f"Error: GDS not found in {possible_paths}. Run hardening first.")
        # Don't exit with error if we just want to install the script
        # sys.exit(1)
