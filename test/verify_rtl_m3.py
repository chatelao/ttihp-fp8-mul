import sys
import os
import re

def verify_gowin_m3_top():
    filepath = "src_gowin/tt_gowin_top_m3.v"
    if not os.path.exists(filepath):
        print(f"Error: {filepath} not found")
        return False

    with open(filepath, "r") as f:
        content = f.read()

    # Verify bus widths
    bus_patterns = [
        (r"wire\s+\[15:0\]\s+m3_gpio_o;", "m3_gpio_o width should be [15:0]"),
        (r"wire\s+\[15:0\]\s+m3_gpio_i;", "m3_gpio_i width should be [15:0]"),
        (r"wire\s+\[15:0\]\s+m3_gpio_oe;", "m3_gpio_oe width should be [15:0]"),
        (r"assign\s+m3_gpio_i\[15:8\]\s*=\s*8'b0;", "m3_gpio_i upper bits should be tied to 0")
    ]

    for pattern, error_msg in bus_patterns:
        if not re.search(pattern, content):
            print(f"Error: {error_msg} in {filepath}")
            return False

    # Verify compile-time flags for INTEGRATION_MODE
    ifdef_patterns = [
        (r"`ifdef\s+M3_MODE_GPIO", "Missing `ifdef M3_MODE_GPIO"),
        (r"parameter\s+INTEGRATION_MODE\s*=\s*0", "Missing INTEGRATION_MODE = 0 in GPIO branch"),
        (r"`elsif\s+M3_MODE_AHB\n", "Missing `elsif M3_MODE_AHB"),
        (r"parameter\s+INTEGRATION_MODE\s*=\s*2", "Missing INTEGRATION_MODE = 2 in AHB branch"),
        (r"`elsif\s+M3_MODE_AHB_DMA", "Missing `elsif M3_MODE_AHB_DMA"),
        (r"parameter\s+INTEGRATION_MODE\s*=\s*3", "Missing INTEGRATION_MODE = 3 in AHB DMA branch"),
        (r"`else", "Missing `else for default APB mode"),
        (r"parameter\s+INTEGRATION_MODE\s*=\s*1", "Missing INTEGRATION_MODE = 1 in default branch")
    ]

    for pattern, error_msg in ifdef_patterns:
        if not re.search(pattern, content):
            print(f"Error: {error_msg} in {filepath}")
            return False

    # Verify integration logic blocks
    integration_patterns = [
        (r"generate", "Missing generate block"),
        (r"if\s*\(INTEGRATION_MODE\s*==\s*0\)\s*begin\s*:\s*gen_gpio_integration", "Missing gen_gpio_integration"),
        (r"else\s+if\s*\(INTEGRATION_MODE\s*==\s*1\)\s*begin\s*:\s*gen_apb_integration", "Missing gen_apb_integration"),
        (r"else\s+if\s*\(INTEGRATION_MODE\s*==\s*2\)\s*begin\s*:\s*gen_ahb_integration", "Missing gen_ahb_integration"),
        (r"else\s+if\s*\(INTEGRATION_MODE\s*==\s*3\)\s*begin\s*:\s*gen_ahb_dma_integration", "Missing gen_ahb_dma_integration"),
        (r"ahb2_mac_bridge\s+#\(", "ahb2_mac_bridge not instantiated"),
        (r"Gowin_EMPU_M3\s+m3_inst", "Gowin_EMPU_M3 instance not found"),
        (r"if\s*\(INTEGRATION_MODE\s*==\s*2\s*\|\|\s*INTEGRATION_MODE\s*==\s*3\)\s*begin\s*:\s*gen_m3_ahb", "Missing gen_m3_ahb block for combined AHB modes"),
        (r"\.ADDR\s*\(m3_addr\)", "ADDR port not connected in M3 instance"),
        (r"\.M_AHB_HADDR\s*\(m3_haddr\)", "M_AHB_HADDR port not connected in M3 instance"),
        (r"\.M_AHB_HREADY\s*\(m3_hready_in\)", "M_AHB_HREADY port not connected in M3 instance"),
        (r"\.S_AHB_HADDR\s*\(m3_s_haddr\)", "S_AHB_HADDR port not connected in M3 instance"),
        (r"\.S_AHB_HREADYOUT\s*\(m3_s_hreadyout\)", "S_AHB_HREADYOUT port not connected in M3 instance")
    ]

    for pattern, error_msg in integration_patterns:
        if not re.search(pattern, content):
            print(f"Error: {error_msg} in {filepath}")
            return False

    print(f"Verification of {filepath} successful: AHB/APB/GPIO modes verified.")
    return True

if __name__ == "__main__":
    if verify_gowin_m3_top():
        sys.exit(0)
    else:
        sys.exit(1)
