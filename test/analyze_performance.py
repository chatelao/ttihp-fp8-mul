import subprocess
import os
import re

def get_yosys_stats():
    cmd = "yosys -p \"read_verilog -Isrc src/project.v; synth -top tt_um_chatelao_fp8_multiplier; stat\""
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
    print("OCP MXFP8 MAC Unit Performance Analysis")
    print("========================================")

    gate_count = get_yosys_stats()
    if gate_count:
        print(f"Synthesized Gate Count (Total Cells): {gate_count}")

    # Architecture params
    CYCLES_PER_BLOCK = 41
    MAC_OPS_PER_BLOCK = 32

    # Theoretical Throughput
    freqs = [27e6, 50e6, 100e6] # Hz

    print("\nTheoretical Performance:")
    print(f"{'Freq (MHz)':<12} | {'Throughput (MOPS)':<20} | {'Latency (ns)':<15}")
    print("-" * 55)

    for f in freqs:
        # Each MAC is 2 FLOPs (Mul + Add)
        mflops = (f * MAC_OPS_PER_BLOCK * 2) / CYCLES_PER_BLOCK / 1e6
        latency_ns = (CYCLES_PER_BLOCK / f) * 1e9
        print(f"{f/1e6:<12.1f} | {mflops:<20.2f} | {latency_ns:<15.2f}")

    # Area Efficiency (1x2 tile = 167x216 um = 0.036 mm^2 approx)
    tile_area_mm2 = 167 * 216 * 1e-6
    if gate_count:
        density = gate_count / tile_area_mm2
        print(f"\nArea Efficiency (1x2 Tile): {density:.2f} Cells/mm²")

    print("\nProtocol Latency:")
    print(f"- Protocol cycles: {CYCLES_PER_BLOCK}")
    print(f"- Elements per block: {MAC_OPS_PER_BLOCK}")
    print(f"- Throughput: {MAC_OPS_PER_BLOCK/CYCLES_PER_BLOCK:.4f} MACs/cycle")

if __name__ == "__main__":
    main()
