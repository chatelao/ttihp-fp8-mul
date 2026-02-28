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
        idx = layout.layer(config['layer'], 0, f"Highlight_{pattern}")

        found_instances = False
        for inst in top_cell.each_inst():
            # In klayout.db, Instance objects don't have a 'name' attribute like they might in GUI
            # We match against the cell name they point to.
            cell_name = inst.cell.name.lower()

            if pattern in cell_name:
                top_cell.shapes(idx).insert(inst.bbox())
                found_instances = True
                print(f"Found {pattern} in instance pointing to cell {inst.cell.name}")

        if found_instances:
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
    possible_extensions = ["*.gds", "*.oas"]
    found_files = []
    for ext in possible_extensions:
        found_files.extend(glob.glob(f"**/{ext}", recursive=True))

    found_files = [f for f in found_files if ".git" not in f]
    print(f"Scanning for layout files. Found: {found_files}")

    gds_path = None
    if found_files:
        top_module = "tt_um_chatelao_fp8_multiplier"
        for f in found_files:
            if top_module in f:
                gds_path = f
                break
        if not gds_path:
            gds_path = found_files[0]

    if gds_path:
        output_png = "gds_colored_zones.png"
        colorize_gds(gds_path, output_png)
    else:
        print(f"Error: No GDS or OAS layout files found in recursive search.")
        sys.exit(1)
