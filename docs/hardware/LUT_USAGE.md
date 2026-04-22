# LUT and Gate Usage Analysis

This document details the combinatorial logic complexity of the OCP MXFP8 Streaming MAC Unit, expressed in equivalent gates for ASIC (Tiny Tapeout) and Look-Up Tables (LUTs) for FPGA (Tang Nano 4K).

## 1. ASIC Gate Analysis (Tiny Tapeout / IHP SG13G2)

The following table breaks down the estimated gate count for the primary functional blocks in the **Full** configuration (~6800 gates total).

| Block | Function | Complexity | Est. Gates | % of Area |
| :--- | :--- | :--- | :---: | :---: |
| **Aligner Stage** | 40-bit Barrel Shifters (x2) | Left/Right shift, Rounding, Saturation | 3038 | 44% |
| **Multiplier Core**| Dual 8x8 Multipliers | Mantissa mul, Exponent add, MX+ logic | 2086 | 31% |
| **Control & Glue** | FSM, Metadata, Debug | Counter, Muxes, Probing logic | 1210 | 18% |
| **Accumulator** | 32-bit Adder | Core summation logic | 451 | 7% |
| **Total** | | | **6785** | **100%** |

### Gate Impact of Individual Features
| Feature Flag | Gate Delta | Description |
| :--- | :---: | :--- |
| `SUPPORT_VECTOR_PACKING` | -2426 | Removal of dual-lane datapath and muxing. |
| `SUPPORT_MX_PLUS` | -593 | Removal of repurposed exponent and index logic. |
| `ENABLE_SHARED_SCALING` | -296 | Removal of 32-bit absolute/shift logic at output. |
| `SUPPORT_DEBUG` | -247 | Removal of internal probing and metadata echo. |
| `USE_LNS_MUL_PRECISE` | +445 | Addition of 64x4 LUT for Mitchell correction. |

## 2. FPGA Resource Usage (Gowin GW1NSR-4C)

Targeting the **Tang Nano 4K**, the design is mapped to 4-input LUTs (LUT4).

| Variant | LUT4 Count (Est.) | ALU (Carry Chain) | Notes |
| :--- | :---: | :---: | :--- |
| **Full** | ~4700 | ~580 | High utilization; fits with routing margin. |
| **Lite** | ~2800 | ~350 | Balanced performance/area. |
| **Tiny** | ~1400 | ~225 | Minimal footprint. |

*Note: LUT1/LUT2/LUT3 counts are consolidated into LUT4 equivalents for simplicity. Results obtained using Yosys synth_gowin.*

## 3. Critical Path and Logic Depth

The combinatorial depth of the design impacts the maximum operating frequency ($F_{max}$):

- **Deepest Path**: Exponent summation $\rightarrow$ Significand multiplication $\rightarrow$ Aligner shift $\rightarrow$ Accumulator update.
- **Pipelining**: Enabling `SUPPORT_PIPELINING` inserts a register stage between the Multiplier and Aligner, reducing logic depth by ~40% and significantly increasing $F_{max}$ on both ASIC and FPGA.
- **LNS Path**: The Mitchell LNS multiplier has a shallower logic depth than the standard parallel multiplier, potentially allowing higher clock speeds in area-optimized variants.

## 4. Optimization Techniques

To keep the design within the 1x1 or 2x2 Tiny Tapeout tile limits, the following logic optimizations were applied:
1. **Resource Sharing**: The 32-bit adder in the accumulator is reused for shared scaling calculations in Cycle 36.
2. **Barrel Shifter Pruning**: Shifters are optimized based on the maximum possible shift range required by the OCP formats.
3. **Mux Minimization**: Metadata and configuration registers use localized decoding to reduce the global routing congestion and gate count.
