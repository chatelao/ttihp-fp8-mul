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
        (r"wire\s+\[15:0\]\s+m3_gpio_oe;", "m3_gpio_oe width should be [15:0]")
    ]

    for pattern, error_msg in bus_patterns:
        if not re.search(pattern, content):
            print(f"Error: {error_msg} in {filepath}")
            return False

    # Verify parameter propagation
    expected_params = [
        "parameter ALIGNER_WIDTH",
        "parameter ACCUMULATOR_WIDTH",
        "parameter SUPPORT_E4M3",
        "parameter SUPPORT_E5M2",
        "parameter SUPPORT_MXFP6",
        "parameter SUPPORT_MXFP4",
        "parameter SUPPORT_INT8",
        "parameter SUPPORT_PIPELINING",
        "parameter SUPPORT_ADV_ROUNDING",
        "parameter SUPPORT_MIXED_PRECISION",
        "parameter SUPPORT_VECTOR_PACKING",
        "parameter SUPPORT_PACKED_SERIAL",
        "parameter SUPPORT_INPUT_BUFFERING",
        "parameter SUPPORT_MX_PLUS",
        "parameter SUPPORT_SERIAL",
        "parameter SERIAL_K_FACTOR",
        "parameter ENABLE_SHARED_SCALING",
        "parameter USE_LNS_MUL",
        "parameter USE_LNS_MUL_PRECISE",
        "parameter INTEGRATION_MODE",
        "parameter APB_BASE_ADDR",
        "parameter AHB_BASE_ADDR"
    ]

    missing_params = []
    for param in expected_params:
        if param not in content:
            missing_params.append(param)

    if missing_params:
        print(f"Error: Missing parameters in {filepath}: {', '.join(missing_params)}")
        return False

    # Verify integration logic blocks
    integration_patterns = [
        (r"generate", "Missing generate block"),
        (r"if\s*\(INTEGRATION_MODE\s*==\s*0\)\s*begin\s*:\s*gen_gpio_integration", "Missing gen_gpio_integration"),
        (r"else\s+if\s*\(INTEGRATION_MODE\s*==\s*1\)\s*begin\s*:\s*gen_apb_integration", "Missing gen_apb_integration"),
        (r"else\s+if\s*\(INTEGRATION_MODE\s*==\s*2\)\s*begin\s*:\s*gen_ahb_integration", "Missing gen_ahb_integration"),
        (r"else\s*begin\s*:\s*gen_ahb2_dma_integration", "Missing gen_ahb2_dma_integration"),
        (r"Gowin_EMPU_M3\s+m3_inst", "Gowin_EMPU_M3 instance not found")
    ]

    for pattern, error_msg in integration_patterns:
        if not re.search(pattern, content):
            print(f"Error: {error_msg} in {filepath}")
            return False

    print(f"Verification of {filepath} successful: 4 integration modes and parameters verified.")
    return True

if __name__ == "__main__":
    if verify_gowin_m3_top():
        sys.exit(0)
    else:
        sys.exit(1)
