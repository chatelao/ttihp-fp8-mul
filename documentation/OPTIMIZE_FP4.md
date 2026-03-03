# Concept: OPTIMIZE_FP4 - Minimal Silicon for FP4-Only Variant

## 1. Introduction
This concept outlines the strategy for optimizing the OCP MX MAC unit into a highly efficient, minimal-area FP4-only (E2M1) variant. By leveraging existing parameterization and introducing targeted pruning, we can reduce the silicon footprint by up to 68% compared to the multi-format baseline, while still maintaining the ability to build the full "Swiss Army Knife" unit for other use cases.

## 2. Theoretical Efficiency Gains
Using Yosys synthesis targets (Sky130/IHP SG13G2), we estimate the following savings when the unit is configured for FP4-only operation:

| Component | Baseline (FP8/INT8) | FP4-Only Optimized | Area Reduction |
|---|---|---|---|
| **Multiplier Core** | ~824 Gates | ~180 Gates | **78%** |
| **Product Aligner** | ~1541 Gates | ~850 Gates | **45%** |
| **Total Unit** | **~5852 Gates** | **~1853 Gates** | **68%** |

## 3. Targeted Optimizations for Minimal FP4 Silicon

### 3.1. Fixed-Bit Extraction Decoders
In the "FP4-only" configuration, the `decode_operand` task's complex `case` statement is pruned. The hardware simplifies to static bit-range extraction:
- `sign = data[3]`
- `exponent = data[2:1]`
- `mantissa = data[0]`
This eliminates approximately 200 gates of multiplexing and format-selection logic that would otherwise handle 7 different formats.

### 3.2. 2x2 Significand Multiplier Scaling
Standard FP8/INT8 requires an 8x8 integer multiplier to handle the 7-bit mantissas and 8-bit integers. For FP4 (E2M1), the significand (1.M) is only 2 bits wide.
- A **2x2 multiplier** (producing a 4-bit product) is sufficient.
- This is the single largest area saver, reducing the multiplier block by >600 gates.

### 3.3. Pruned Exponent Arithmetic
FP8 requires handling multiple biases (1, 3, 7, 15) and 5-bit exponents.
- FP4-only uses a **fixed Bias 1** and 2-bit exponents.
- The 6-bit exponent adder/subtractor path is replaced with a tiny **3-bit adder**, saving ~80 gates.

### 3.4. Narrower Datapath (16-bit to 20-bit)
While FP8 requires a 32-bit or 40-bit accumulator to maintain precision across 32 elements, many FP4-quantized LLM inference tasks are stable with 16-bit or 20-bit internal accumulation.
- Reducing `ACCUMULATOR_WIDTH` to 20 bits and `ALIGNER_WIDTH` accordingly shaves hundreds of gates from the barrel shifter and the main accumulator register.

## 4. Implementation Roadmap (5-Step Strategy)

### Step 1: Aggressive Parameter-Driven Pruning
- **Action**: Audit all internal modules (`fp8_mul`, `fp8_aligner`, `project.v`) to ensure all non-FP4 logic is guarded by `SUPPORT_E5M2`, `SUPPORT_MXFP6`, and `SUPPORT_INT8` parameters.
- **Goal**: Allow the synthesizer to automatically remove all wide-format decoders and bias muxing when these flags are set to `0`.

### Step 2: Adaptive Multiplier Scaling
- **Action**: Refactor the multiplier in `fp8_mul.v` to use a hierarchical structure that scales its bit-width based on the feature parameters.
- **Goal**: Automatically instantiate a minimal 2x2 multiplier for FP4-only builds, while preserving 8x8 capability for multi-format builds.

### Step 3: Minimal Exponent Path Refactoring (COMPLETED)
- **Action**: Parameterize the internal exponent bit-width and bias constants throughout the datapath.
- **Goal**: Shrink the exponent arithmetic logic from 6 bits to 3 bits when only narrow formats are enabled.

### Step 4: Datapath Width Tuning
- **Action**: Conduct a sensitivity analysis to find the optimal `ALIGNER_WIDTH` and `ACCUMULATOR_WIDTH` for FP4 inference.
- **Goal**: Minimize the area of the barrel shifter and accumulation registers without compromising model accuracy (target: 20-bit accumulation).

### Step 5: Protocol Short-Circuiting
- **Action**: Introduce a `SHORT_PROTOCOL` mode that skips Cycle 1 (Format Load) and reduces the streaming phase to 16 cycles (for $k=32$ blocks) by leveraging the "Packed Mode" natively.
- **Goal**: Reduce total operation latency from 41 cycles to ~20 cycles, effectively doubling the unit's throughput-per-area.

## 5. Backward Compatibility
This optimization concept is designed as an extension of the existing parameterization. By setting `SUPPORT_E5M2=1`, `SUPPORT_MXFP6=1`, and `SUPPORT_INT8=1`, the unit remains the full OCP MX "Swiss Army Knife." Minimal silicon is achieved only when the user explicitly opts for the `FP4_ONLY` configuration by disabling the wider format flags.

---
*Concept developed for OCP MX-PLUS MAC project.*
