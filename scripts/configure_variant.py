import sys
import re
import os
import json

ALIASES = {
    "baseline": "Full",
    "full": "Full",
    "light": "Lite",
    "lite": "Lite",
    "tiny": "Tiny",
    "ultra-tiny": "Ultra-Tiny",
    "tiny-serial": "Tiny-Serial",
    "lns": "LNS",
}

def configure_variant(variant, format_mode="patch"):
    variants_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "variants.json")
    with open(variants_path, "r") as f:
        variants = json.load(f)

    canonical = ALIASES.get(variant.lower(), variant)
    if canonical not in variants:
        print(f"Unknown variant: {variant}. Available: {', '.join(variants.keys())}", file=sys.stderr)
        sys.exit(1)

    params = variants[canonical]

    if format_mode == "iverilog":
        print(" ".join(f"-P tb.{k}={v}" for k, v in params.items()))
        return
    if format_mode == "verilator":
        print(" ".join(f"-G{k}={v}" for k, v in params.items()))
        return
    if format_mode == "yosys":
        print(" ".join(f"-set {k} {v}" for k, v in params.items()))
        return

    project_file = "src/project.v"
    if not os.path.exists(project_file):
        print(f"Error: {project_file} not found.")
        sys.exit(1)

    with open(project_file, "r") as f:
        content = f.read()

    for p, v in params.items():
        pattern = rf"(parameter\s+{p}\s*=\s*)(\d+)"
        content = re.sub(pattern, rf"\g<1>{v}", content)

    with open(project_file, "w") as f:
        f.write(content)

    print(f"Configured {project_file} for {canonical} variant.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python scripts/configure_variant.py <variant> [--format=patch|iverilog|verilator|yosys]")
        sys.exit(1)
    fmt = "patch"
    for arg in sys.argv[2:]:
        if arg.startswith("--format="):
            fmt = arg.split("=", 1)[1]
    configure_variant(sys.argv[1], fmt)
