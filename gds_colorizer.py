import pya
import os

def colorize_gds(input_gds, output_png):
    # 1. Load the layout
    layout = pya.Layout()
    layout.read(input_gds)
    top_cell = layout.top_cell()

    # 2. Define Submodule Configuration
    # Mapping submodule patterns to colors and unique layer indices
    # Colors: Red (#E63946), Light (#F1FAEE), Blue (#457B9D), Cyan (#A8DADC)
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
        for inst in top_cell.each_inst():
            # Instance names are used to match the pattern
            name = inst.name.lower() if inst.name else inst.cell.name.lower()
            if pattern in name:
                # Add a colored rectangle on the specific visualization layer
                top_cell.shapes(idx).insert(inst.bbox())
                found_instances = True

        if found_instances:
            # Set layer properties for this specific layer index
            lp = pya.LayerPropertiesNode()
            lp.source_layer_index = idx
            lp.fill_color = config['color']
            lp.frame_color = 0x000000
            lp.width = 1
            lp.dither_pattern = 1 # Solid
            view.insert_layer(view.end_layers(), lp)

    # 5. Export Visualization
    view.zoom_fit()
    view.save_image(output_png, 1024, 768)
    print(f"Visualization saved to {output_png}")

def find_gds():
    # 1. Check current directory
    gds_path = "tt_um_chatelao_fp8_multiplier.gds"
    if os.path.exists(gds_path):
        return gds_path

    # 2. Search recursively (e.g., in runs/...)
    for root, dirs, files in os.walk('.'):
        for file in files:
            if file.endswith('.gds') and 'tt_um' in file:
                return os.path.join(root, file)

    # 3. Fallback to any GDS
    for root, dirs, files in os.walk('.'):
        for file in files:
            if file.endswith('.gds'):
                return os.path.join(root, file)

    return None

if __name__ == "__main__":
    gds_file = find_gds()
    if gds_file:
        print(f"Using GDS: {gds_file}")
        colorize_gds(gds_file, "gds_colored_zones.png")
    else:
        print(f"Error: No GDS file found.")
