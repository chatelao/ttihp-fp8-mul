# Roadmap: Implementing MX+ Features on OCP MX MAC Unit

This roadmap outlines the incremental implementation of the **MX+** extension, as proposed in the paper *"MX+: Pushing the Limits of Microscaling Formats for Efficient Large Language Model Serving"* (Lee et al., 2025). MX+ enhances the base OCP MX format by providing higher precision for "Block Max" (BM) elements—the outliers that typically dominate quantization error.

## Introduction: The MX+ Concept
In standard MX formats, the exponent of the largest magnitude value in a block (the Block Max) determines the shared scale. For this BM element, its own exponent field always contains the maximum representable value ($e_{max}$).

**MX+** leverages this redundancy by repurposing the exponent bits of the BM element as an extended mantissa, significantly increasing its precision without increasing the total bit width of the format.

### Illustrative Example: MXFP4 vs. MXFP4+
Consider a 4-element block from a Mistral-7B activation tensor:
**Original (BF16)**: `[-0.39, -9.84, -0.20, 0.99]`

In this block, the **Block Max (BM)** is `-9.84` (at index 1).

#### 1. Shared Scale Determination
The shared scale is determined by the BM element's magnitude. For MXFP4 (E2M1), which has a maximum representable exponent ($e_{max}$) of 2:
- $\lfloor \log_2(9.84) \rfloor = 3$
- $shared\_exp = 3 - 2 = 1$
- **Shared Scale ($X$)** = $2^1 = \mathbf{2.0}$

#### 2. Quantization Results Comparison

| Index | BF16 Value | Standard MXFP4 ($X=2.0$) | MXFP4+ ($X=2.0$) |
| :--- | :--- | :--- | :--- |
| 0 | -0.39 | 0.0 (`0b1000`) | 0.0 (`0b1000`) |
| **1 (BM)** | **-9.84** | **-8.0** (`0b1110`) | **-10.0** (`0b1010`) |
| 2 | -0.20 | 0.0 (`0b1000`) | 0.0 (`0b1000`) |
| 3 | 0.99 | 1.0 (`0b0001`) | 1.0 (`0b0001`) |

**Numerical Analysis**:
- **Standard MXFP4**: The BM element uses standard E2M1 ($P_i \in \{4.0, 6.0\}$ after scaling). Nearest value to $9.84/2.0 = 4.92$ is $4.0$, resulting in $X \cdot P_i = -8.0$. **Error = 1.84**.
- **MXFP4+**: The BM element repurposes its 2 exponent bits as mantissa, allowing 3 mantissa bits ($P_i \in \{4.0, 4.5, 5.0, 5.5, 6.0, 6.5, 7.0, 7.5\}$). Nearest value to $4.92$ is $5.0$, resulting in $X \cdot P_i = -10.0$. **Error = 0.16**.

By preserving the precision of the outlier, MX+ achieves a **10x reduction in quantization error** for the most critical value in the block while maintaining a 4-bit footprint.

---

## Phase 1: Metadata & Protocol Extension

### Step 1: Protocol Update for BM Indices (Status: **COMPLETED**)
- **Goal**: Load the position of the BM element for both Operand A and Operand B.
- **Preparation**:
  - Audit `uio_in` usage in Cycles 1 and 2 of the FSM.
  - Define the bit-mapping for the 5-bit index and 3-bit reserved field within the 41-cycle protocol.
- **Variant Analysis**:
  - **Variant A (Extended Protocol)**: Increase protocol length to 43 cycles, adding two dedicated metadata cycles after scaling.
  - **Variant B (Metadata Multiplexing)**: Utilize unused bits in `uio_in` during Cycle 2 (where `scale_b` is loaded on `ui_in`).
  - **Variant C (Serial Shift-In)**: Use a dedicated 1-bit input to shift in the index over 5 cycles during the streaming phase.
  - **Variant D (Header Cycle Extension)**: Add a dedicated "Metadata Cycle" (Cycle 0) before Scale A.
- **Reasoning**: **Variant B** is selected. It maintains the 41-cycle standard protocol, ensuring backward compatibility with existing software drivers and minimizing the latency impact of the extension.

### Step 2: Internal Storage & Parameterization (Status: **COMPLETED**)
- **Goal**: Add parameterized hardware support for MX+.
- **Preparation**:
  - Define `bm_index_a` and `bm_index_b` registers in `src/project.v`.
  - Implement a `SUPPORT_MX_PLUS` feature flag.
- **Variant Analysis**:
  - **Variant A (Shared Metadata Register)**: Use a single 16-bit register for all MX+ metadata (indices + offsets).
  - **Variant B (Split Gated Registers)**: Separate registers for `bm_index` and `nbm_offset`, each guarded by its own `generate` block.
  - **Variant C (LUT-Based Storage)**: Store indices in a small distributed RAM/LUT if available in the FPGA/ASIC library.
  - **Variant D (FSM-Embedded Constants)**: Hardwire the BM index to a fixed value (e.g., index 0) to eliminate registers.
- **Reasoning**: **Variant B** is chosen to enable modular register pruning. If only basic MX+ is needed (Phase 2) without MX++ (Phase 4), the offset registers can be pruned independently, saving area on the Tiny Tapeout tile.

---

## Phase 2: MX+ Operand Decoding

### Step 3: Outlier Identification in Multiplier (Status: **COMPLETED**)
- **Goal**: Detect when the current streaming element is the designated Block Max.
- **Preparation**:
  - Update `fp8_mul` module interface to accept outlier metadata.
  - Synchronize internal `index_counter` with the FSM `cycle_count`.
- **Variant Analysis**:
  - **Variant A (Distributed Comparators)**: Pass the 5-bit `bm_index` into each multiplier lane; each lane performs its own `count == bm_index` check.
  - **Variant B (Centralized Flagging)**: Perform the comparison in the top-level FSM (`project.v`) and pass a single `is_bm` wire to the multiplier lanes.
  - **Variant C (Address-Match Trigger)**: Use the `bm_index` to trigger a one-shot pulse from a global address decoder.
  - **Variant D (Scan-Chain Tagging)**: Tag the BM element in a shadow register during the load phase and shift the tag alongside the data.
- **Reasoning**: **Variant B** is selected. Centralizing the comparison logic reduces the total gate count by removing redundant 5-bit magnitude comparators from the multiplier lanes, which is critical for the "Ultra-Tiny" configuration.

### Step 4: Exponent Repurposing Logic (Status: **COMPLETED**)
- **Goal**: Implement the MX+ numerical semantics within the shared decoders.
- **Preparation**:
  - Refactor the `task automatic decode_operand` in `src/fp8_mul.v` to accept an `is_bm` boolean.
- **Variant Analysis**:
  - **Variant A (Dual Decoders)**: Instantiate a separate "MX+ Decoder" and a "Standard Decoder" for each lane, using a MUX to select the output.
  - **Variant B (Conditional Override)**: Modify the existing decoder logic to conditionally hardwire the exponent to `e_max` and treat exponent bits as mantissa when `is_bm` is high.
  - **Variant C (Post-Decoder Override)**: Decode normally and then use a MUX to replace the exponent bits with `e_max` before normalization.
  - **Variant D (Table-Based Decoding)**: Use a small ROM or PLA to map the 4/6/8-bit input directly to the internal format.
- **Reasoning**: **Variant B** is chosen for area efficiency. It reuses the existing mantissa shift and normalization logic with minimal additional logic gates.

---

## Phase 3: Datapath & Aligner Updates

### Step 5: Handling Variable Mantissa Width (Status: **COMPLETED**)
- **Goal**: Support the wider product generated by BM elements.
- **Preparation**:
  - Audit the bit-width of the `mul_prod` signal (currently 16-bit).
  - Ensure the aligner can handle the increased mantissa precision.
- **Variant Analysis**:
  - **Variant A (Fixed 8x8 Multiplier)**: Always use an 8x8 multiplier for all formats when `SUPPORT_MX_PLUS=1`.
  - **Variant B (Parameterized Multiplier)**: Use `generate` blocks to scale the multiplier width (4x4 or 8x8) based on both format (MXFP4/6/8) and the MX+ support flag.
  - **Variant C (Bit-Serial Mantissa Expansion)**: Process the extra BM bits over two clock cycles in the multiplier.
  - **Variant D (Logarithmic Multiplier)**: Use an LNS (Logarithmic Number System) multiplier which naturally handles varying precision.
- **Reasoning**: **Variant B** is selected to preserve the "Ultra-Tiny" footprint for users who only require standard MXFP4. The 8x8 multiplier is only instantiated if required for MXFP8+ or high-precision INT8 modes.

---

## Phase 4: MX++ Support (Advanced Scaling)

### Step 6: Decoupled Shared Scaling (Status: **COMPLETED**)
- **Goal**: Implement **MX++**, which allows Non-Block Max (NBM) elements to use a finer quantization grid.
- **Preparation**:
  - Implement a 3-bit subtractor to calculate the `shared_exp_nbm = shared_exp - offset`.
- **Variant Analysis**:
  - **Variant A (Datapath Barrel Shifter)**: Add a dedicated shifter after the multiplier to apply the offset.
  - **Variant B (Aligner Exponent Offset)**: Subtract the offset from the `exp_sum` before it enters the `fp8_aligner`.
  - **Variant C (Post-Accumulation Normalization)**: Apply the offset after the accumulator during the final result shift-out.
  - **Variant D (Dual-Path Aligner)**: Instantiate a separate "NBM Aligner" and "BM Aligner" with fixed offsets.
- **Reasoning**: **Variant B** is preferred as it leverages the existing alignment hardware. Modifying the exponent input to the aligner is significantly cheaper in terms of area than adding a second barrel shifter to the datapath.

---

## Phase 5: Verification & Benchmarking

### Step 7: Reference Model Synchronization (Status: **COMPLETED**)
- **Goal**: Update the Python reference model for bit-accuracy.
- **Preparation**:
  - Implement the `E0Mx` layout in the `test/test.py` decoding logic.
- **Variant Analysis**:
  - **Variant A (Numerical Model)**: Use floating-point math to approximate MX+ behavior.
  - **Variant B (Bit-Level Model)**: Implement the exact bit-masking and shifting logic found in the Verilog RTL.
  - **Variant C (Functional Wrapper)**: Use a high-level Python class that wraps a standard float with MX+ constraints.
  - **Variant D (C++ Extension)**: Implement the model in C++ for performance and bind it to Python using pybind11.
- **Reasoning**: **Variant B** is essential for verification. Bit-level accuracy ensures that quantization edge cases (like rounding near 0.5 LSB) are handled identically by the hardware and the software testbench.

### Step 8: Comprehensive Test Suite (Status: **COMPLETED**)
- **Goal**: Add test cases targeting outlier preservation.
- **Preparation**:
   - Define specific test vectors in `test/TEST_MXPLUS.yaml`.
- **Variant Analysis**:
  - **Variant A (Random Fuzzing)**: Generate random input blocks and check against the model.
  - **Variant B (Directed Corner Cases)**: Specifically test blocks where the BM is at index 0, 15, or 31.
  - **Variant C (Formal Verification)**: Use SVA (SystemVerilog Assertions) to formally prove the correctness of the BM detection.
  - **Variant D (Power-Aware Simulation)**: Include switching activity analysis (VCD) in tests to measure the energy impact.
- **Reasoning**: **Variant B** is prioritized for the initial implementation to ensure the FSM and indexing logic are robust, followed by Variant A for general coverage.

### Step 9: Physical Impact Analysis (Status: **COMPLETED**)
- **Goal**: Measure the gate count delta.
- **Preparation**:
  - Integrate `SUPPORT_MX_PLUS` into the `test/gate_analysis.py` matrix.
- **Variant Analysis**:
  - **Variant A (Top-Level Synthesis)**: Synthesize the entire MAC unit to see the real-world area impact.
  - **Variant B (Module-Only Synthesis)**: Synthesize only the `fp8_mul` module to isolate the cost of decoding logic.
  - **Variant C (Congestion-Aware Synthesis)**: Analyze routing density and pin placement constraints in the 1x2 tile.
  - **Variant D (Thermal Profiling)**: Run gate-level power simulations to check for hotspots.
- **Reasoning**: Both are used. Variant A provides the final "gate budget" for the Tiny Tapeout tile, while Variant B helps optimize the decoder architecture during Phase 2.
- **Results**:
  - **Top-Level Impact**: +557 gates (Baseline build).
  - **Module-Level Impact**: +170 gates (per `fp8_mul` instance).
  - **Analysis**: The overhead is primarily due to the 8x8 multiplier requirement for MX+ significands and the additional muxing in the operand decoders.

---

## Phase 6: Vector Packing for FP4 (Throughput Optimization)

### Step 10: Packed Protocol Definition (Status: **COMPLETED**)
- **Goal**: Optimize the streaming protocol for 4-bit elements.
- **Preparation**:
  - Reserve bit 6 of the Config Byte (`uio_in` at Cycle 1) to toggle Packed Mode.
- **Variant Analysis**:
  - **Variant A (Implicit Packing)**: Automatically pack all 4-bit formats into 16 cycles.
  - **Variant B (Explicit Packed Mode)**: Use a control bit to choose between standard 32-cycle and packed 16-cycle streaming.
  - **Variant C (Dynamic Packing)**: Detect 4-bit formats and automatically switch protocol length based on I/O activity.
  - **Variant D (Sub-Cycle Interleaving)**: Load elements on both rising and falling edges of the clock (DDR-style).
- **Reasoning**: **Variant B** was chosen. This allows the hardware to remain compliant with standard OCP drivers that do not support packed data layouts, while offering a high-performance "opt-in" for specialized accelerators.

### Step 11: Dual-Lane Multiplier Integration (Status: **COMPLETED**)
- **Goal**: Implement parallel processing of packed elements.
- **Preparation**:
  - Instantiate a second `fp8_mul` and `fp8_aligner` unit.
- **Variant Analysis**:
  - **Variant A (Temporal Parallelism)**: Run a single multiplier at 2x clock frequency.
  - **Variant B (Spatial Parallelism)**: Instantiate two parallel multiplier lanes.
  - **Variant C (Temporal Interleaving)**: Use a single multiplier at 2x clock frequency with a bypass register.
  - **Variant D (SIMD Vector Lane)**: Use a wide 8-bit multiplier that can be split into two 4-bit lanes.
- **Reasoning**: **Variant B** was selected. Given the Tiny Tapeout constraints (10MHz typical, 100MHz peak), spatial parallelism is more robust for timing closure and avoids complex clock-domain-crossing logic required for temporal parallelism.

### Step 12: Buffering & Duty Cycle Reduction (Alternative) (Status: **COMPLETED**)
- **Goal**: Reduce I/O activity without increasing multiplier area.
- **Preparation**:
  - Design an 8-bit wide, 16-entry FIFO for activation buffering.
- **Variant Analysis**:
  - **Variant A (Input Buffering)**: Load packed data in 16 cycles, then process at 1 element/cycle.
  - **Variant B (Output Buffering)**: Process at full speed and buffer the final 32-bit results.
  - **Variant C (Compressed Streaming)**: Use a simple RLE (Run Length Encoding) for the 4-bit elements.
  - **Variant D (Circular Buffer)**: Use a dual-port RAM for simultaneous load and process.
- **Reasoning**: **Variant A** is preferred for duty cycle reduction. It allows the system to burst-load activations and then potentially enter a low-power state or free the bus for other devices while the MAC unit processes the block.

### Step 13: Exception Handling & Robustness (Status: **COMPLETED**)
- **Goal**: Implement block-level sticky registers for NaN and Infinity tracking.
- **Preparation**:
  - Update `fp8_mul.v` and `fp8_mul_lns.v` to detect special values.
  - Define sticky registers in `src/project.v`.
- **Variant Analysis**:
  - **Variant A (Accumulator-Integrated)**: Pass NaN/Inf flags into the accumulator and let it handle the override.
  - **Variant B (Control-Path Sticky Registers)**: Latch flags in the top-level FSM and use a MUX at the output stage to override the result.
  - **Variant C (IEEE-754 Pattern Propagation)**: Propagate special patterns through the arithmetic datapath (Aligner/Adder) to naturally produce the correct result.
  - **Variant D (Interrupt-Based)**: Signal the host via a dedicated pin/interrupt when an exception occurs.
- **Reasoning**: **Variant B** is selected. It avoids increasing the complexity of the arithmetic datapath (which is optimized for area) while ensuring strict adherence to the OCP MX Shared Scale NaN Rule and special value propagation rules.

---

## Phase 7: Implementation Review

### Final Feature Verification (March 2025)
A comprehensive audit of the RTL against this roadmap confirms that all 12 steps of the MX+ extension are fully implemented and verified.

| Step | Feature | Status | Verification Method |
|:---:|---|:---:|---|
| 1 | BM Index Protocol | **[x]** | Formal (project.v), Cocotb |
| 2 | Metadata Storage | **[x]** | Formal (project.v), Cocotb |
| 3 | Outlier Identification | **[x]** | Formal (project.v), Cocotb |
| 4 | Exponent Repurposing | **[x]** | Python Model, Cocotb |
| 5 | Variable Mantissa Width | **[x]** | Synthesis (8x8 multiplier), Cocotb |
| 6 | MX++ Offset Scaling | **[x]** | Python Model, Cocotb |
| 7 | Reference Model Sync | **[x]** | `test/test.py` updates |
| 8 | MX+ Test Suite | **[x]** | `test/TEST_MXPLUS.yaml` |
| 9 | Physical Impact Analysis| **[x]** | `test/gate_analysis.py` |
| 10 | Packed Protocol | **[x]** | Cocotb (`test_mxfp4_packed`) |
| 11 | Multi-Lane/Serial Packing| **[x]** | Cocotb (`test_mxfp4_packed_serial`) |
| 12 | Input Buffering | **[x]** | Cocotb (`test_mxfp4_input_buffering`) |
| 13 | Exception Robustness | **[x]** | Cocotb (`test_mxfp8_sticky_flags`) |

### Conclusion
The OCP MX+ MAC Unit now provides a complete implementation of the "Extended Block Max Precision" extension. The design maintains a minimal area footprint (as shown in the gate analysis) while significantly reducing quantization error for outliers. The addition of **Input Buffering** (Step 12) completes the high-performance path for FP4 processing, enabling efficient burst-loading of weights and activations.
