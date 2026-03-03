import sys
import re
import os

def configure_variant(variant):
    features = [
        "SUPPORT_E4M3",
        "SUPPORT_E5M2",
        "SUPPORT_MXFP6",
        "SUPPORT_MXFP4",
        "SUPPORT_VECTOR_PACKING",
        "SUPPORT_PACKED_SERIAL",
        "SUPPORT_INT8",
        "SUPPORT_PIPELINING",
        "SUPPORT_ADV_ROUNDING",
        "SUPPORT_MIXED_PRECISION",
        "SUPPORT_INPUT_BUFFERING",
        "SUPPORT_MX_PLUS",
        "ENABLE_SHARED_SCALING",
        "USE_LNS_MUL",
        "SUPPORT_SERIAL"
    ]

    params = {}
    if variant == "baseline":
        params = {f: 1 for f in features}
        params["USE_LNS_MUL"] = 0
        params["SUPPORT_SERIAL"] = 0
        params["SUPPORT_PACKED_SERIAL"] = 0
        params["ALIGNER_WIDTH"] = 40
        params["ACCUMULATOR_WIDTH"] = 32
    elif variant == "light" or variant == "lite":
        params = {f: 1 for f in features}
        params["SUPPORT_MXFP6"] = 0
        params["SUPPORT_VECTOR_PACKING"] = 0
        params["SUPPORT_ADV_ROUNDING"] = 0
        params["SUPPORT_MX_PLUS"] = 0
        params["USE_LNS_MUL"] = 0
        params["SUPPORT_SERIAL"] = 0
        params["SUPPORT_PACKED_SERIAL"] = 0
        params["ALIGNER_WIDTH"] = 40
        params["ACCUMULATOR_WIDTH"] = 32
    elif variant == "tiny":
        params = {f: 0 for f in features}
        params["ALIGNER_WIDTH"] = 40
        params["ACCUMULATOR_WIDTH"] = 32
    else:
        print(f"Unknown variant: {variant}")
        sys.exit(1)

    project_file = "src/project.v"
    if not os.path.exists(project_file):
        print(f"Error: {project_file} not found.")
        sys.exit(1)

    with open(project_file, "r") as f:
        content = f.read()

    for p, v in params.items():
        # Match parameter name and replace its value
        # Pattern: parameter NAME = VALUE
        pattern = rf"(parameter\s+{p}\s*=\s*)(\d+)"
        content = re.sub(pattern, rf"\g<1>{v}", content)

    # Also handle ALIGNER_WIDTH and ACCUMULATOR_WIDTH specifically
    for p in ["ALIGNER_WIDTH", "ACCUMULATOR_WIDTH"]:
        if p in params:
            pattern = rf"(parameter\s+{p}\s*=\s*)(\d+)"
            content = re.sub(pattern, rf"\g<1>{params[p]}", content)

    with open(project_file, "w") as f:
        f.write(content)

    print(f"Configured {project_file} for {variant} variant.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python scripts/configure_variant.py <variant>")
        sys.exit(1)
    configure_variant(sys.argv[1])
