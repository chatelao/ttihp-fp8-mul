import subprocess
import re

def get_yosys_stats(params):
    param_str = ""
    for k, v in params.items():
        param_str += f"chparam -set {k} {v} fp8_mul; "

    cmd = f"yosys -p \"read_verilog src/fp8_mul.v; {param_str} synth -top fp8_mul; stat\""
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    sections = result.stdout.split("design hierarchy")
    if len(sections) > 1:
        last_section = sections[-1]
        match = re.search(r"Number of cells:\s+(\d+)", last_section)
        if match:
            return int(match.group(1))
    return None

features = ["SUPPORT_MXFP6", "SUPPORT_MXFP4"]
baseline_params = {f: 1 for f in features}
baseline_gates = get_yosys_stats(baseline_params)

print(f"fp8_mul Sub-module Analysis")
print(f"Baseline: {baseline_gates} gates")

for feature in features:
    params = baseline_params.copy()
    params[feature] = 0
    gates = get_yosys_stats(params)
    print(f"Disable {feature}: {gates} gates (Delta: {gates - baseline_gates})")
