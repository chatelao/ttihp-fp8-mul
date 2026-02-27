import pya
import os
import sys

def colorize_gds(input_gds, output_png):
    print(f"Loading GDS: {input_gds}")

    # 1. Load the layout
    layout = pya.Layout()
    layout.read(input_gds)
    top_cell = layout.top_cell()
    print(f"Top cell: {top_cell.name}")

    # 2. Define Submodule Configuration
    # Mapping submodule patterns to colors and unique layer indices
    submodule_config = {
        'multiplier':   {'color': 0xE63946, 'layer': 1001}, # Red
        'fp8_mul':      {'color': 0xE63946, 'layer': 1001}, # Red
        'aligner_inst': {'color': 0xF1FAEE, 'layer': 1002}, # Light
        'fp8_aligner':  {'color': 0xF1FAEE, 'layer': 1002}, # Light
        'acc_inst':     {'color': 0x457B9D, 'layer': 1003}, # Blue
        'accumulator':  {'color': 0x457B9D, 'layer': 1003}, # Blue
        'top_control':  {'color': 0xA8DADC, 'layer': 1004}  # Cyan
    }

    # 3. Setup View (Headless mode via xvfb-run is assumed in CI)
    # Important: In standalone mode, we must instantiate LayoutView
    view = pya.LayoutView()
    view.show_layout(layout, False)

    # 4. Identify and Annotate Submodules
    # We use high layer indices to avoid conflicts with manufacturing layers
    for pattern, config in submodule_config.items():
        idx = layout.layer(config['layer'], 0, f"Highlight_{pattern}")
        found_instances = False
        print(f"Searching for pattern: {pattern}")

        for inst in top_cell.each_inst():
            # Match both instance name and cell name (case-insensitive)
            name = inst.name.lower() if inst.name else ""
            cell_name = inst.cell.name.lower()
            if pattern in name or pattern in cell_name:
                # Add a colored rectangle on the specific visualization layer
                top_cell.shapes(idx).insert(inst.bbox())
                found_instances = True
                print(f"  Found instance: name='{name}', cell='{cell_name}'")

        if found_instances:
            # Set visual properties for the highlight layer
            lp = pya.LayerPropertiesNode()
            lp.source_layer_index = idx
            lp.fill_color = config['color']
            lp.frame_color = 0x000000
            lp.width = 1
            lp.dither_pattern = 1 # Solid
            view.insert_layer(view.end_layers(), lp)
        else:
            print(f"  No instances found for {pattern}")

    # 5. Export Visualization
    # Ensure zoom is correct and save the image
    print(f"Saving image to: {output_png}")
    view.zoom_fit()
    view.save_image(output_png, 1024, 768)
    print("Export completed successfully.")

def find_gds():
    print("Searching for GDS files...")
    # 1. Check current directory for the expected top module name
    gds_path = "tt_um_chatelao_fp8_multiplier.gds"
    if os.path.exists(gds_path):
        return gds_path

    # 2. Search recursively in subdirectories (common in OpenLane runs)
    for root, dirs, files in os.walk('.'):
        for file in files:
            if file.endswith('.gds') and 'tt_um' in file:
                path = os.path.join(root, file)
                print(f"Found candidate GDS: {path}")
                return path

    # 3. Fallback to any GDS file
    for root, dirs, files in os.walk('.'):
        for file in files:
            if file.endswith('.gds'):
                path = os.path.join(root, file)
                print(f"Found fallback GDS: {path}")
                return path

    return None

if __name__ == "__main__":
    gds_file = find_gds()
    if gds_file:
        try:
            colorize_gds(gds_file, "gds_colored_zones.png")
        except Exception as e:
            print(f"Error during colorization: {e}")
            sys.exit(1)
    else:
        print("Error: No GDS file found.")
        sys.exit(1)
