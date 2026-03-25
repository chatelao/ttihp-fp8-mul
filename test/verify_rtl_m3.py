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
        (r"`elsif\s+M3_MODE_AHB", "Missing `elsif M3_MODE_AHB"),
        (r"parameter\s+INTEGRATION_MODE\s*=\s*2", "Missing INTEGRATION_MODE = 2 in AHB branch"),
        (r"`else", "Missing `else for default APB mode"),
        (r"parameter\s+INTEGRATION_MODE\s*=\s*1", "Missing INTEGRATION_MODE = 1 in default branch")
    ]

    for pattern, error_msg in ifdef_patterns:
        if not re.search(pattern, content):
            print(f"Error: {error_msg} in {filepath}")
            return False

    # Verify parameter propagation (reusing from verify_rtl.py logic)
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
        (r"else\s*begin\s*:\s*gen_ahb_integration", "Missing gen_ahb_integration"),
        (r"Gowin_EMPU_M3\s+m3_inst", "Gowin_EMPU_M3 instance not found"),
        (r"\.ADDR\s*\(m3_addr\)", "ADDR port not connected in M3 instance"),
        (r"\.DATAOUT\s*\(m3_data_out\)", "DATAOUT port not connected in M3 instance"),
        (r"\.WRITE\s*\(m3_write\)", "WRITE port not connected in M3 instance"),
        (r"\.READ\s*\(m3_read\)", "READ port not connected in M3 instance"),
        (r"\.DATAIN\s*\(m3_data_in\)", "DATAIN port not connected in M3 instance"),
        (r"\.M_AHB_HADDR\s*\(m3_haddr\)", "M_AHB_HADDR port not connected in M3 instance"),
        (r"\.M_AHB_HTRANS\s*\(m3_htrans\)", "M_AHB_HTRANS port not connected in M3 instance"),
        (r"\.M_AHB_HWRITE\s*\(m3_hwrite\)", "M_AHB_HWRITE port not connected in M3 instance"),
        (r"\.M_AHB_HSIZE\s*\(m3_hsize\)", "M_AHB_HSIZE port not connected in M3 instance"),
        (r"\.M_AHB_HWDATA\s*\(m3_hwdata\)", "M_AHB_HWDATA port not connected in M3 instance"),
        (r"\.M_AHB_HSEL\s*\(m3_hsel\)", "M_AHB_HSEL port not connected in M3 instance"),
        (r"\.M_AHB_HREADY\s*\(m3_hready\)", "M_AHB_HREADY port not connected in M3 instance"),
        (r"\.M_AHB_HRDATA\s*\(m3_hrdata\)", "M_AHB_HRDATA port not connected in M3 instance"),
        (r"\.M_AHB_HREADYOUT\s*\(m3_hreadyout\)", "M_AHB_HREADYOUT port not connected in M3 instance"),
        (r"\.M_AHB_HRESP\s*\(m3_hresp\)", "M_AHB_HRESP port not connected in M3 instance")
    ]

    for pattern, error_msg in integration_patterns:
        if not re.search(pattern, content):
            print(f"Error: {error_msg} in {filepath}")
            return False

    if "tt_um_chatelao_fp8_multiplier #(" not in content:
        print(f"Error: tt_um_chatelao_fp8_multiplier not instantiated with parameters in {filepath}")
        return False

    # Check for original parameters only (some are internal to tt_gowin_top_m3)
    original_params = [p for p in expected_params if p not in ["parameter INTEGRATION_MODE", "parameter APB_BASE_ADDR", "parameter AHB_BASE_ADDR"]]
    for param in original_params:
        param_name = param.split()[-1]
        if f".{param_name}({param_name})" not in content:
            print(f"Error: Parameter {param_name} not passed to instance in {filepath}")
            return False

    print(f"Verification of {filepath} successful: 16-bit buses, parameters, and AHB/APB/GPIO modes verified.")
    return True

if __name__ == "__main__":
    if verify_gowin_m3_top():
        sys.exit(0)
    else:
        sys.exit(1)
