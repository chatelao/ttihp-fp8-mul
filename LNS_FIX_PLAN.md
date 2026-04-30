# LNS Bit-Serial Integration Fix Plan

## 1. Analysis of CI/CD Failures

### 1.1 Verilator/Lint Failures
- **Syntax Errors**: Automated edits used C-style `}` instead of Verilog `end`. This caused total compilation failure in lint and wasm jobs.
- **Missing Pins**: The `fixed_to_float` instantiation lacked connections for probe outputs, triggering `PINMISSING`.
- **Width Mismatches**: Ternary operators in the element index calculation generated 7-bit results in one branch and 8-bit in another, triggering `WIDTHEXPAND`.
- **Unused Signals/Params**: Parameters like `USE_LNS_MUL_PRECISE` and signals like `bm_index_a_val` triggered warnings when specific features were disabled.

### 1.2 Functional/Numerical Failures
- **Zero Results**: Many tests returned `Actual: 0`. This is likely due to the `acc_en` logic or protocol timing gaps being misaligned with the 2-cycle logical latency.
- **Model Mismatch**: `test.py` was using the standard multiplier model even when testing the bit-serial hardware (which is always LNS-based).
- **Alignment Shift**: The constant `37` vs `30`. For a 40-bit datapath with bit 16 as $2^0$, and a multiplier output with binary point at bit 6, the correct offset is `30` (providing a base shift of +10).

## 2. Roadmap to Fix

### Step 1: Hardware Synchronization
- [ ] Fix Verilog syntax in `src/project.v` (ensure `end` and `endgenerate` are correctly placed).
- [ ] Connect all pins in `fixed_to_float` and use `/* verilator lint_off UNUSEDSIGNAL */`.
- [ ] Correct `DATAPATH_LATENCY`:
    - Bit-serial multiplier takes 1 logical cycle for handoff.
    - Pipeline register takes 1 logical cycle.
    - Total logical latency = 2.
- [ ] Ensure `COUNTER_WIDTH` is consistently 7 bits.

### Step 2: Verification Model Alignment
- [ ] Update `run_mac_test` in `test/test.py` to detect `SUPPORT_SERIAL` from the DUT parameters.
- [ ] Force `use_lns=1` in the model if `SUPPORT_SERIAL` is active.
- [ ] Synchronize the alignment formula in `test.py` to use the constant `30`.

### Step 3: CI/CD Compliance
- [ ] Run local `iverilog` elaboration check.
- [ ] Ensure all `generate` blocks have named blocks and proper `endgenerate` tags.
- [ ] Validate with `test_mxfp_mac_randomized`.

## 3. Immediate Actions
1. Fix the `src/project.v` file content manually (no more greedy `sed`).
2. Update `test/test.py` to match bit-serial LNS behavior.
3. Verify the "6-cycle gap" logic between streaming and capture.
