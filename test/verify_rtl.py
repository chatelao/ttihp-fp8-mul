import sys
import os

def verify_gowin_top():
    filepath = "src_gowin/tt_gowin_top.v"
    if not os.path.exists(filepath):
        print(f"Error: {filepath} not found")
        return False

    with open(filepath, "r") as f:
        content = f.read()

    expected_params = [
        "parameter ALIGNER_WIDTH",
        "parameter ACCUMULATOR_WIDTH",
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
        "parameter USE_LNS_MUL_PRECISE"
    ]

    missing_params = []
    for param in expected_params:
        if param not in content:
            missing_params.append(param)

    if missing_params:
        print(f"Error: Missing parameters in {filepath}: {', '.join(missing_params)}")
        return False

    if "tt_um_chatelao_fp8_multiplier #(" not in content:
        print(f"Error: tt_um_chatelao_fp8_multiplier not instantiated with parameters in {filepath}")
        return False

    for param in expected_params:
        param_name = param.split()[-1]
        if f".{param_name}({param_name})" not in content:
            print(f"Error: Parameter {param_name} not passed to instance in {filepath}")
            return False

    print(f"Verification of {filepath} successful: All parameters present and propagated.")
    return True

if __name__ == "__main__":
    if verify_gowin_top():
        sys.exit(0)
    else:
        sys.exit(1)
