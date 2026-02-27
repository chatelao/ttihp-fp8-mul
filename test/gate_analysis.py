import subprocess
import os
import re

def get_yosys_stats(params):
    param_str = ""
    for k, v in params.items():
        param_str += f"chparam -set {k} {v} tt_um_chatelao_fp8_multiplier; "

    cmd = f"yosys -p \"read_verilog -Isrc src/project.v; {param_str} synth -top tt_um_chatelao_fp8_multiplier; stat\""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    # Extract total number of cells from the last "design hierarchy" section
    sections = result.stdout.split("design hierarchy")
    if len(sections) > 1:
        last_section = sections[-1]
        match = re.search(r"Number of cells:\s+(\d+)", last_section)
        if match:
            return int(match.group(1))
    return None

def main():
    features = [
        "SUPPORT_MXFP6",
        "SUPPORT_MXFP4",
        "SUPPORT_ADV_ROUNDING",
        "SUPPORT_MIXED_PRECISION",
        "ENABLE_SHARED_SCALING"
    ]

    baseline_params = {f: 1 for f in features}

    print("OCP MXFP8 MAC Unit Gate Impact Analysis")
    print("========================================")

    baseline_gates = get_yosys_stats(baseline_params)
    print(f"{'Configuration':<30} | {'Gates':<10} | {'Delta':<10}")
    print("-" * 55)
    print(f"{'Baseline (Full)':<30} | {baseline_gates:<10} | {'0':<10}")

    for feature in features:
        params = baseline_params.copy()
        params[feature] = 0
        gates = get_yosys_stats(params)
        delta = gates - baseline_gates
        print(f"{'Disable ' + feature:<30} | {gates:<10} | {delta:<10}")

    tiny_params = {f: 0 for f in features}
    tiny_gates = get_yosys_stats(tiny_params)
    tiny_delta = tiny_gates - baseline_gates
    print(f"{'Tiny (All Disabled)':<30} | {tiny_gates:<10} | {tiny_delta:<10}")

if __name__ == "__main__":
    main()
