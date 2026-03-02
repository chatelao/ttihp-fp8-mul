import subprocess
import re

def get_yosys_stats(module, params, file):
    param_str = ""
    for k, v in params.items():
        param_str += f"chparam -set {k} {v} {module}; "

    cmd = f"yosys -p \"read_verilog -Isrc {file}; {param_str} synth -top {module}; stat\""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    sections = result.stdout.split("design hierarchy")
    if len(sections) > 1:
        last_section = sections[-1]
        match = re.search(r"Number of cells:\s+(\d+)", last_section)
        if match:
            return int(match.group(1))
    else:
        match = re.search(r"Number of cells:\s+(\d+)", result.stdout)
        if match:
            return int(match.group(1))
    return None

print("Sub-module FP4-only Analysis")
print("===========================")

# fp8_mul analysis
mul_features = ["SUPPORT_E5M2", "SUPPORT_MXFP6", "SUPPORT_MXFP4", "SUPPORT_INT8", "SUPPORT_MIXED_PRECISION", "SUPPORT_MX_PLUS"]
mul_baseline = {f: 1 for f in mul_features}
mul_baseline["SUPPORT_MX_PLUS"] = 0
mul_fp4_only = {f: 0 for f in mul_features}
mul_fp4_only["SUPPORT_MXFP4"] = 1

mul_base_gates = get_yosys_stats("fp8_mul", mul_baseline, "src/fp8_mul.v")
mul_fp4_gates = get_yosys_stats("fp8_mul", mul_fp4_only, "src/fp8_mul.v")

print(f"fp8_mul (Full): {mul_base_gates} gates")
print(f"fp8_mul (FP4-only): {mul_fp4_gates} gates")
print(f"fp8_mul Savings: {mul_base_gates - mul_fp4_gates} gates")

# fp8_aligner analysis
# Aligner doesn't really have format-specific logic, but WIDTH matters.
align_params_40 = {"WIDTH": 40, "SUPPORT_ADV_ROUNDING": 1}
align_params_32 = {"WIDTH": 32, "SUPPORT_ADV_ROUNDING": 0}
align_params_24 = {"WIDTH": 24, "SUPPORT_ADV_ROUNDING": 0}

align_40_gates = get_yosys_stats("fp8_aligner", align_params_40, "src/fp8_aligner.v")
align_32_gates = get_yosys_stats("fp8_aligner", align_params_32, "src/fp8_aligner.v")
align_24_gates = get_yosys_stats("fp8_aligner", align_params_24, "src/fp8_aligner.v")

print(f"fp8_aligner (40-bit, Adv): {align_40_gates} gates")
print(f"fp8_aligner (32-bit, Basic): {align_32_gates} gates")
print(f"fp8_aligner (24-bit, Basic): {align_24_gates} gates")

# Full Unit Analysis
full_features = [
    "SUPPORT_E5M2", "SUPPORT_MXFP6", "SUPPORT_MXFP4", "SUPPORT_VECTOR_PACKING",
    "SUPPORT_INT8", "SUPPORT_PIPELINING", "SUPPORT_ADV_ROUNDING",
    "SUPPORT_MIXED_PRECISION", "SUPPORT_MX_PLUS", "ENABLE_SHARED_SCALING"
]
full_baseline = {f: 1 for f in full_features}
full_baseline["SUPPORT_MX_PLUS"] = 0
full_baseline["ALIGNER_WIDTH"] = 40
full_baseline["ACCUMULATOR_WIDTH"] = 32

full_fp4_only = {f: 0 for f in full_features}
full_fp4_only["SUPPORT_MXFP4"] = 1
full_fp4_only["ALIGNER_WIDTH"] = 24
full_fp4_only["ACCUMULATOR_WIDTH"] = 24

full_base_gates = get_yosys_stats("tt_um_chatelao_fp8_multiplier", full_baseline, "src/project.v")
full_fp4_gates = get_yosys_stats("tt_um_chatelao_fp8_multiplier", full_fp4_only, "src/project.v")

print(f"Full Unit (Baseline): {full_base_gates} gates")
print(f"Full Unit (FP4-only Optimized): {full_fp4_gates} gates")
print(f"Total Savings: {full_base_gates - full_fp4_gates} gates")
