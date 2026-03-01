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
    else:
        # Fallback to general Number of cells
        match = re.search(r"Number of cells:\s+(\d+)", result.stdout)
        if match:
            return int(match.group(1))
    return None

def main():
    features = [
        "SUPPORT_E5M2",
        "SUPPORT_MXFP6",
        "SUPPORT_MXFP4",
        "SUPPORT_VECTOR_PACKING",
        "SUPPORT_INT8",
        "SUPPORT_PIPELINING",
        "SUPPORT_ADV_ROUNDING",
        "SUPPORT_MIXED_PRECISION",
        "ENABLE_SHARED_SCALING",
        "USE_LNS_MUL"
    ]

    baseline_params = {f: 1 for f in features}
    baseline_params["USE_LNS_MUL"] = 0 # Baseline is standard multiplier
    baseline_params["ALIGNER_WIDTH"] = 40
    baseline_params["ACCUMULATOR_WIDTH"] = 32
    baseline_params["USE_LNS_MUL"] = 0
    baseline_params["USE_LNS_MUL_PRECISE"] = 0

    print("OCP MXFP8 MAC Unit Gate Impact Analysis (POST-OPTIMIZATION)")
    print("==========================================================")

    baseline_gates = get_yosys_stats(baseline_params)
    if baseline_gates is None:
        print("Error: Baseline synthesis failed.")
        return

    print(f"{'Configuration':<30} | {'Gates':<10} | {'Delta':<10}")
    print("-" * 55)
    print(f"{'Baseline (Full)':<30} | {baseline_gates:<10} | {'0':<10}")

    for feature in features:
        params = baseline_params.copy()
        if feature == "USE_LNS_MUL":
            params[feature] = 1
            label = "Enable " + feature
        else:
            params[feature] = 0
            label = "Disable " + feature

        gates = get_yosys_stats(params)
        if gates is not None:
            delta = gates - baseline_gates
            print(f"{label:<30} | {gates:<10} | {delta:<10}")
        else:
            print(f"{label:<30} | {'FAILED':<10} | {'N/A':<10}")

    tiny_params = {f: 0 for f in features}
    tiny_params["ALIGNER_WIDTH"] = 40
    tiny_params["ACCUMULATOR_WIDTH"] = 32
    tiny_gates = get_yosys_stats(tiny_params)
    tiny_delta = tiny_gates - baseline_gates
    print(f"{'Tiny (All Disabled)':<30} | {tiny_gates:<10} | {tiny_delta:<10}")

    ultra_tiny_params = tiny_params.copy()
    ultra_tiny_params["ALIGNER_WIDTH"] = 32
    ultra_tiny_params["ACCUMULATOR_WIDTH"] = 24
    ultra_tiny_gates = get_yosys_stats(ultra_tiny_params)
    ultra_tiny_delta = ultra_tiny_gates - baseline_gates
    print(f"{'Ultra-Tiny (Red. Width)':<30} | {ultra_tiny_gates:<10} | {ultra_tiny_delta:<10}")

    lite_params = baseline_params.copy()
    lite_params["SUPPORT_MXFP6"] = 0
    lite_params["SUPPORT_MXFP4"] = 0
    lite_params["SUPPORT_VECTOR_PACKING"] = 0
    lite_params["SUPPORT_ADV_ROUNDING"] = 0
    lite_gates = get_yosys_stats(lite_params)
    lite_delta = lite_gates - baseline_gates
    print(f"{'Lite (MXFP6/4/Adv/VP Off)':<30} | {lite_gates:<10} | {lite_delta:<10}")

    one_tile_target = ultra_tiny_params.copy()
    one_tile_target["ALIGNER_WIDTH"] = 24
    one_tile_target["ACCUMULATOR_WIDTH"] = 20
    one_tile_gates = get_yosys_stats(one_tile_target)
    one_tile_delta = one_tile_gates - baseline_gates
    print(f"{'1x1 Tile Target (Min)':<30} | {one_tile_gates:<10} | {one_tile_delta:<10}")

    lns_mitchell_params = baseline_params.copy()
    lns_mitchell_params["USE_LNS_MUL"] = 1
    lns_mitchell_params["USE_LNS_MUL_PRECISE"] = 0
    lns_mitchell_gates = get_yosys_stats(lns_mitchell_params)
    lns_mitchell_delta = lns_mitchell_gates - baseline_gates
    print(f"{'LNS Multiplier (Mitchell)':<30} | {lns_mitchell_gates:<10} | {lns_mitchell_delta:<10}")

    lns_precise_params = baseline_params.copy()
    lns_precise_params["USE_LNS_MUL"] = 1
    lns_precise_params["USE_LNS_MUL_PRECISE"] = 1
    lns_precise_gates = get_yosys_stats(lns_precise_params)
    lns_precise_delta = lns_precise_gates - baseline_gates
    print(f"{'LNS Multiplier (Precise)':<30} | {lns_precise_gates:<10} | {lns_precise_delta:<10}")

if __name__ == "__main__":
    main()
