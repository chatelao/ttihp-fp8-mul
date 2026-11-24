# Project Review & Improvement Proposals: `ttihp-fp8-mul`

## Executive Summary

This review audits the **Tiny Tapeout IHP OCP MXFP8 Streaming MAC Unit** (`ttihp-fp8-mul`) across six engineering domains: core RTL & arithmetic datapath, formal verification & ASIC hardening, FPGA/Cortex-M3 integration & firmware, WebAssembly Digital Twin, test suite & CI/CD, and documentation & repository hygiene.

The core parallel MAC architecture (multi-format decoding, 40-bit S23.16 alignment, UE8M0 shared scaling, MX+ extended mantissa, and IEEE-754 Float32 conversion) is well-structured, and the current `ihp-sg13cmos5l` GDS/precheck/GL-test pipeline passes at 50 MHz (`CLOCK_PERIOD = 20`). However, the audit uncovered **concrete functional bugs**—including an ungated accumulator enable that corrupts results on `ena=0`, a Cycle 0 control-bit collision that makes Float32 debug probes unusable, broken bit-serial and LNS arithmetic corner cases, AHB-Lite protocol violations in the DMA bridge, an off-by-one byte drop in the Web Digital Twin, and an orphaned test suite masking failing tests.

### Findings Summary

| Severity | Count | Key Risk Areas |
| :--- | :---: | :--- |
| **Critical** | 5 | `acc_en` missing `ena` gate; Cycle 0 bit collision; AHB-Lite DMA timing violations; M3 firmware off-by-1 protocol bug; Web Digital Twin byte-drop & Float32 mismatch |
| **High** | 10 | Narrow-accumulator truncation; LNS subnormal/area bugs; Bit-serial LNS & aligner bugs; broken formal setup; ASIC clock/file-list mismatches; gated clocks in FPGA bridge; orphaned/failing tests; variant drift; RTL-vs-docs drift |
| **Medium** | 8 | Disconnected `SUPPORT_SERIAL`; unconditional F2F area overhead; Verilog 0-width replication & `initial` blocks; Cortex-M3 vector table & TT DevKit script init; Web UI mismatches; CI gaps; broken doc links; root clutter & repo bloat |
| **Low** | 1 | Rounding-gate and fixed-point NaN/Inf override edge cases |

---

## Decided Architectural Resolutions (Ready for Implementation)

The following three design decisions have been finalized and MUST be applied during implementation:

### Decision 1 — Cycle 0 Control Bit Allocation (`F-RTL-02`)
Resolve all `ui_in` collisions with zero extra protocol cycles and 100% backward compatibility for normal (`debug_en = 0`) operation:

| `ui_in` Bit | Normal Mode (`ui_in[6] == 0`) | Debug Mode (`ui_in[6] == 1`) |
| :---: | :--- | :--- |
| `[7]` | `short_protocol` (1 = jump to Cycle 3, reuse scales) | `short_protocol` (unchanged) |
| `[6]` | `debug_en = 0` | `debug_en = 1` |
| `[5]` | `float32_mode` (1 = IEEE-754 Float32, 0 = S23.8 fixed-point) | `float32_mode` (**dedicated; never triggers loopback**) |
| `[4]` | `lns_mode[1]` | `loopback_en` (**sticky loopback triggers ONLY on `ui_in[6] && ui_in[4]`**, e.g. `ui_in = 0x50`) |
| `[3]` | `lns_mode[0]` | `probe_sel[3]` |
| `[2:0]` | `nbm_offset_a[2:0]` | `probe_sel[2:0]` |

**Implementation rules:**
- `uio_in[7:0]` remains **100% dedicated** to `mx_plus_en`, `packed_mode`, `overflow_wrap`, `round_mode`, and `nbm_offset_b`/`short_format` in both Normal and Debug modes.
- When `ui_in[6] == 1` (Debug Mode), `lns_mode_reg` and `nbm_offset_a` **hold their existing values** (reset `0` or prior non-debug Cycle 0 values) so selecting probes `0x0`–`0xF` never corrupts LNS or MX++ arithmetic.
- Loopback latches on `loopback_en_reg <= loopback_en_reg | (ui_in[6] && ui_in[4])`.
- Probing Float32 mode (`float32_mode = 1` with Probes `0xE` / `0xF`) uses `ui_in = 8'h6E` / `8'h6F` (Standard) or `8'hEE` / `8'hEF` (Short) without triggering loopback.

### Decision 2 — Target ASIC Clock Frequency & Tiny Tapeout IHP Spec Compliance (`F-ASIC-01`)
Verified directly against the official `TinyTapeout/ttihp-verilog-template` (`src/config.json`, `info.yaml`), Tiny Tapeout clock/GPIO specs, and the repo's passing `gds.yaml` run on `ihp-sg13cmos5l`:
- **Target frequency:** Standardize on **50 MHz** across the ASIC metadata:
  - Keep `"CLOCK_PERIOD": 20` (50 MHz) in `src/config.json` (matches official `ttihp-verilog-template` default and already closes STA/precheck/GL-test on `ihp-sg13cmos5l`).
  - Update `clock_hz: 50000000` in `info.yaml` (and update tile-size comment from `167x108 uM` to `202x155 uM` per `ttihp-verilog-template`).
  - Update `docs/info.md` clock target to `50 MHz` (noting that the Gowin Tang Nano 4K FPGA target remains 20 MHz in `gowin.yaml` and `TANG_NANO_4K_GUIDE.md`).
- **Do NOT modify Tiny Tapeout locked template settings in `src/config.json`:** `"RUN_KLAYOUT_XOR": 0`, `"RUN_KLAYOUT_DRC": 0`, and `"GRT_ALLOW_CONGESTION": 1` sit below the official template's `"!!! DO NOT CHANGE ANYTHING BELOW THIS POINT !!!"` banner because KLayout DRC/XOR run in the separate `TinyTapeout/tt-gds-action/precheck@ihp-cmos5l` job. Leave those flags intact.
- **Synchronize `source_files`:** Keep `info.yaml`, `test/Makefile`, `.github/workflows/lint.yaml`, `.github/workflows/test.yaml`, and `.github/workflows/gowin.yaml` synchronized (include `accumulator_serial.v` once integrated, or generate file lists from `info.yaml`).

### Decision 3 — NaN / Infinity Output Convention in Fixed-Point vs. Float32 Mode (`F-RTL-10`)
Adopt the standard DSP/SIMD hardware convention—separating fixed-point saturation from IEEE-754 encodings:
- **Float32 Mode (`float32_mode_reg == 1`):** Emit standard IEEE-754 canonical patterns via `fixed_to_float.v`:
  - `NaN` (including `+Inf + -Inf` and Scale `0xFF`) → `0x7FC00000` (quiet NaN)
  - `+Inf` → `0x7F800000`
  - `-Inf` → `0xFF800000`
- **Fixed-Point S23.8 Mode (`float32_mode_reg == 0`):** Emit standard saturating two's-complement 32-bit integers instead of aliasing IEEE-754 float bit patterns:
  - `+Inf` → `0x7FFFFFFF` (`INT32_MAX`)
  - `-Inf` → `0x80000000` (`INT32_MIN`)
  - `NaN` (including `+Inf + -Inf` and Scale `0xFF`) → `0x80000000` (`INT32_MIN`, standard integer indefinite/error sentinel, with exact `nan_sticky`/`inf_pos_sticky`/`inf_neg_sticky` flags readable on Debug Probe `0x2`)
- **Required test updates:** Update fixed-point NaN/Inf assertions in `test/test.py`, `test/TEST_MX_E2E.yaml`, `test/test_short_protocol.py`, and `test/test_ofp8_compliance.py` to expect `0x7FFFFFFF` / `0x80000000` in fixed-point mode, and add/keep explicit `float32_mode=1` tests verifying `0x7FC00000` / `0x7F800000` / `0xFF800000`.

---

## 1. Core RTL & Arithmetic (`src/`)

### F-RTL-01 · Critical · `acc_en` is not gated by `ena` (accumulator corruption on stall/deselect)
- **Location:** [`src/project.v:390-392`](../src/project.v#L390-L392), [`src/accumulator.v:60-89`](../src/accumulator.v#L60-L89)
- **Finding:** Every sequential control signal in `tt_um_chatelao_fp8_multiplier` is gated by `ena` (`cycle_count`, `acc_clear`, `load_en`, `shift_en`, pipeline registers, sticky registers) **except `acc_en`**:
  ```verilog
  wire acc_en = strobe && (SUPPORT_PIPELINING ?
                ((logical_cycle >= 6'd4 && logical_cycle <= last_stream_cycle + 6'd1) && ...) :
                ((logical_cycle >= 6'd3 && logical_cycle <= last_stream_cycle) && ...));
  ```
- **Impact:** If `ena` is deasserted (`ena == 0`) while `logical_cycle` is in the stream window—whether for host stalling/flow-control or when Tiny Tapeout's project mux deselects the tile while `clk` remains active—`cycle_count` freezes while `acc_inst` continues adding the same element every clock cycle, silently corrupting the MAC result.

### F-RTL-02 · Critical · Cycle 0 `ui_in` bit collisions break Float32 debugging and corrupt MX+/LNS settings
- **Location:** [`src/project.v:123-130`](../src/project.v#L123-L130), [`src/project.v:183-190`](../src/project.v#L183-L190), [`src/project.v:355-362`](../src/project.v#L355-L362), [`src/project.v:979-980`](../src/project.v#L979-L980)
- **Finding:** Cycle 0 overloads `ui_in[6:0]` with conflicting semantics:
  - `ui_in[5]` selects **both** `float32_mode_reg` (line 360) and sticky `loopback_en_reg` when `ui_in[6]` (`debug_en`) is `1` (line 129: `loopback_en_reg <= loopback_en_reg | (ui_in[5] && ui_in[6])`).
  - `ui_in[3:0]` selects **both** `probe_sel_reg[3:0]` (line 126) and `nbm_offset_a` (`ui_in[2:0]`) + `lns_mode_reg[0]` (`ui_in[3]`).
- **Impact:**
  1. It is **impossible to probe Float32 mode** using Probes `0xE` and `0xF`: enabling Float32 (`ui_in[5]=1`) and Debug (`ui_in[6]=1`) simultaneously latches sticky `loopback_en_reg=1`, forcing `uo_out = ui_in ^ uio_in` until chip reset.
  2. Selecting any probe `>= 0x8` sets `ui_in[3]=1` (inadvertently changing `lns_mode_reg`) and `ui_in[2:0]` (corrupting `nbm_offset_a` when MX+ is enabled).
- **Resolution:** Apply **Decision 1** above.

### F-RTL-03 · High · Silent wraparound/truncation when `ACCUMULATOR_WIDTH < ALIGNER_WIDTH` or `< 32`
- **Location:** [`src/project.v:718`](../src/project.v#L718), [`src/project.v:813-824`](../src/project.v#L813-L824), [`src/project.v:934-948`](../src/project.v#L934-L948)
- **Finding:**
  1. When `ALIGNER_WIDTH = 40` and `ACCUMULATOR_WIDTH = 32` (used by `gds.yaml` WASM and `gowin.yaml` Full/Lite/Tiny), `gen_lane_ext_narrow` slices `aligned_lane0_res[31:0]`, discarding the top 8 integer bits `[39:32]` **without saturation**, even when `overflow_wrap == 0` (SAT mode).
  2. When `ACCUMULATOR_WIDTH = 24` (used by `gowin.yaml` Ultra-Tiny/Tiny-Serial and `tt_gowin_top.v` defaults), `ACTUAL_ACC_WIDTH` is clamped to `32`, so `aligned_combined` (32 bits) connects directly to `accumulator.data_in` (24 bits), silently truncating `[31:24]`.
- **Impact:** Large E4M3/E5M2 products (e.g., `>= 2^15`) silently wrap to arbitrary signed values in SAT mode whenever `ACCUMULATOR_WIDTH < ALIGNER_WIDTH`.

### F-RTL-04 · High · `fp8_mul_lns.v` breaks subnormals & MX+, drops INT8, and increases area instead of reducing it
- **Location:** [`src/fp8_mul_lns.v:75-85`](../src/fp8_mul_lns.v#L75-L85), [`src/fp8_mul_lns.v:244-275`](../src/fp8_mul_lns.v#L244-L275)
- **Finding:**
  1. **Subnormal bug:** In LNS mode (lines 262–275), `m_sum` uses `ma[2:0]` and `mb[2:0]` and hardcodes an implicit leading `1'b1` (`p_res = {9'd0, 1'b1, m_sum[2:0], 3'd0}`), ignoring that subnormals have implicit bit `0`. E4M3 subnormal `0x04` (`0.5 * 2^-6`) × `1.0` evaluates as `1.5 * 2^-6` (200% error), and `0x01` (`0.125 * 2^-6`) × `1.0` evaluates as `1.125 * 2^-6` (800% error).
  2. **MX+ Block Max bug:** When `lns_mode == 2'b01` (pure LNS) and `is_bm == 1`, `ma` holds an 8-bit extended mantissa `{1'b1, data[6:0]}` with `tmp_exp` compensated by `-4`. Taking only `ma[2:0]` discards bits `[6:3]` and introduces a `16x` scale error.
  3. **Area inversion:** Because `lns_mode == 2'b00` and `2'b10` (lines 246, 255) still execute `ma * mb`, `fp8_mul_lns` synthesizes **two 8×8 multipliers plus the LNS adder/LUT**, resulting in *more* area than `fp8_mul.v`.
  4. **INT8 silent zeroing:** Lines 257–260 return `p_res = 0` for INT8/INT8_SYM whenever `lns_mode != 0`.

### F-RTL-05 · High · Multiple functional bugs in `fp8_mul_serial_lns.v`
- **Location:** [`src/fp8_mul_serial_lns.v:17`](../src/fp8_mul_serial_lns.v#L17), [`src/fp8_mul_serial_lns.v:94-132`](../src/fp8_mul_serial_lns.v#L94-L132), [`src/fp8_mul_serial_lns.v:207-215`](../src/fp8_mul_serial_lns.v#L207-L215)
- **Finding:**
  1. **Unmasked sign bit corrupts exponents:** `s1_a` and `s1_b` (lines 128–129) feed `a_aligned`/`b_aligned` straight into the serial adder for `cnt < 12` without masking the sign bit (`cnt == s_p_a` / `s_p_b`). Any negative operand adds its sign bit (`1`) directly into the exponent (corrupting the exponent by `+16` for E4M3, `+32` for E5M2, or `+4` for E2M1). Existing tests in `test/test_fp8_mul_serial_lns.py` only tested positive inputs.
  2. **Unreset/uncleared delay shift registers:** `a_m_delay` and `b_m_delay` (lines 99–105) have neither asynchronous reset nor `strobe` clearing, injecting `X` values after reset and stale bits from the prior element during `cnt == 0..1` for E5M2, E3M2, and E2M1.
  3. **False E4M3 NaN detection:** Line 208 flags `format_a == 3'b000 && a_e_all_ones && a_m_any_nonzero` as NaN. Per OCP OFP8, only `S.1111.111` (`data[6:0] == 7'h7F`) is NaN; the 12 finite E4M3 values `±288` through `±448` (`E=15, M=1..6`) are erroneously treated as NaN.
  4. **Missing `Inf * 0 = NaN` rule:** Multiplying E5M2 `Inf` by `0` asserts both `special_inf` and `special_zero` while leaving `special_nan = 0`.
  5. **No subnormal support & `bias_offset` underflow:** Subnormals (`E == 0, M != 0`) are treated as normals with exponent `0`; for `E2M1 × E2M1`, `bias_offset = 1 + 1 - 7 = -5` (`8'hFB`) is not sign-extended at `cnt == 11`; `EXP_SUM_WIDTH` parameter is unused.

### F-RTL-06 · High · `fp8_aligner_serial.v` drops all right-shifted products and leaks stale delay bits
- **Location:** [`src/fp8_aligner_serial.v:16`](../src/fp8_aligner_serial.v#L16), [`src/fp8_aligner_serial.v:32-49`](../src/fp8_aligner_serial.v#L32-L49)
- **Finding:**
  1. When `k0 = exp_sum + 3 < 0` (every product smaller than `2^-10`), line 49 forces `mag_bit = 1'b0` instead of skipping the first `|k0|` incoming bits. All E4M3/E5M2 products in `[2^-16, 2^-10)` are completely zeroed out despite fitting in the S23.16 accumulator.
  2. `delay_line` is never cleared on `strobe`, so trailing bits from the previous element leak into the next element when `k0` indexes earlier cycles.
  3. `WIDTH` parameter is unused; rounding (only TRN) and saturation are unimplemented.

### F-RTL-07 · Medium · `SUPPORT_SERIAL=1` does not instantiate the bit-serial datapath
- **Location:** [`src/project.v:68-81`](../src/project.v#L68-L81), [`src/project.v:427-450`](../src/project.v#L427-L450)
- **Finding:** Enabling `SUPPORT_SERIAL = 1` in `src/project.v` only adds a `k_counter` strobe divider and two 8-bit shift registers (`a_shifter`, `b_shifter`) whose outputs (`a_bit_serial`, `b_bit_serial`) are **unconnected**. The full parallel `fp8_mul`, `fp8_aligner`, `accumulator`, and `fixed_to_float` remain instantiated.
- **Impact:** Contrary to `README.md` and `README_SERIAL.md`, `SUPPORT_SERIAL=1` currently *increases* silicon area while reducing throughput by `SERIAL_K_FACTOR` (8×).

### F-RTL-08 · Medium · Unconditional `fixed_to_float` instantiation & dead default input FIFO
- **Location:** [`src/project.v:30-32`](../src/project.v#L30-L32), [`src/project.v:227-265`](../src/project.v#L227-L265), [`src/project.v:891-906`](../src/project.v#L891-L906)
- **Finding:**
  1. `fixed_to_float` (40-bit LZC, bidirectional 40-bit barrel shifter, 39-branch sticky mux, RNE rounder) is always instantiated unconditionally—even in `Tiny`, `Ultra-Tiny`, and `Tiny-Serial` builds. There is no `SUPPORT_FLOAT32` parameter.
  2. Default parameters set both `SUPPORT_VECTOR_PACKING = 1` and `SUPPORT_INPUT_BUFFERING = 1`, which makes `actual_input_buffering` permanently `0` (line 315) while elaborating two 16×8 register arrays (`fifo_a`, `fifo_b`, 256 FFs without reset).

### F-RTL-09 · Medium · Non-portable zero-width replication & non-synthesizable `initial` blocks in ASIC RTL
- **Location:** [`src/accumulator.v:69`](../src/accumulator.v#L69), [`src/project.v:327-335`](../src/project.v#L327-L335), [`src/fp8_mul_lns.v:76-85`](../src/fp8_mul_lns.v#L76-L85)
- **Finding:**
  1. `src/accumulator.v` line 69 writes `acc_reg <= {load_data, {(REG_WIDTH-32){1'b0}}};`. When `WIDTH <= 32`, `REG_WIDTH == 32`, producing a 0-width replication `{(0){1'b0}}`.
  2. `src/project.v` lines 327–335 contain an `initial` block initializing registers—ignored by ASIC synthesis and capable of masking missing-reset bugs during RTL simulation that later fail in gate-level simulation (`GL_TEST`) or silicon.
  3. `src/fp8_mul_lns.v` lines 76–85 initialize `lns_lut` via an `initial` block instead of a combinational `case` ROM.

### F-RTL-10 · Low · Rounding-parameter inconsistency and fixed-point NaN/Inf bit-pattern aliasing
- **Location:** [`src/fp8_aligner.v:125-138`](../src/fp8_aligner.v#L125-L138), [`src/fixed_to_float.v:137-182`](../src/fixed_to_float.v#L137-L182), [`src/project.v:908-919`](../src/project.v#L908-L919)
- **Finding:**
  1. In `src/fp8_aligner.v`, `R_CEL` and `R_FLR` are gated by `SUPPORT_ADV_ROUNDING`, while `R_RNE` (and the sticky mask logic) is **not** gated—contradicting `README.md`.
  2. `src/fixed_to_float.v` hardcodes RNE rounding and Inf overflow, ignoring `round_mode` and `overflow_wrap`.
  3. In fixed-point output mode (`float32_mode_reg == 0`), `sticky_byte` overrides `uo_out` with IEEE-754 Float32 patterns (`0x7FC00000`, `0x7F800000`, `0xFF800000`), which alias to valid finite S23.8 fixed-point numbers (`+8,372,224.0`, `+8,355,840.0`, `-32,768.0`).
- **Resolution:** Apply **Decision 3** above for NaN/Inf output convention.

---

## 2. Formal Verification & ASIC Hardening

### F-FV-01 · High · Formal verification configuration and assertions are broken and excluded from CI
- **Location:** [`src/project.sby:7-18`](../src/project.sby#L7-L18), [`src/project.v:1039-1057`](../src/project.v#L1039-L1057), [`src/project.v:1120-1140`](../src/project.v#L1120-L1140)
- **Finding:**
  1. `src/project.sby` executes `read -formal project.v` without reading any of the submodules listed in `[files]` (`fp8_mul.v`, `fp8_aligner.v`, `accumulator.v`, `lzc40.v`, `fixed_to_float.v`, `fp8_mul_lns.v`), causing immediate elaboration failure.
  2. The formal assertion in `src/project.v` lines 1121–1127 asserts `is_bm_a_lane0_raw` whenever `element_index_lane0_reg == bm_index_a_val`, **omitting `mx_plus_en_val`** (line 211 gates `is_bm_a_lane0_raw` with `mx_plus_en`). Whenever `mx_plus_en == 0`, the proof immediately fails at Cycle 3.
  3. Line 1045 compares `$past(logical_cycle) == last_cycle` instead of `$past(last_cycle)`.
  4. `depth 10` in `src/project.sby` is too shallow to traverse the 41-cycle protocol, and no GitHub Actions workflow runs `sby`.

### F-ASIC-01 · High · Clock frequency and source-list drift between `info.yaml`, `src/config.json`, and build files
- **Location:** [`info.yaml:8,19-28`](../info.yaml#L8), [`src/config.json:15`](../src/config.json#L15)
- **Finding:**
  1. **Clock target mismatch:** `info.yaml` declares `clock_hz: 20000000` (20 MHz), whereas `src/config.json` constrains synthesis/STA to `"CLOCK_PERIOD": 20` (50 MHz, matching the official `TinyTapeout/ttihp-verilog-template` default and already passing GDS/precheck/GL-test on `ihp-sg13cmos5l`).
  2. **Outdated tile-size comment:** `info.yaml` still lists `167x108 uM` (Sky130) instead of `202x155 uM` (IHP).
  3. **Source file list drift:** `src/accumulator_serial.v` is present in `src/` and `src/project.sby` but omitted from `info.yaml`, `test/Makefile`, `.github/workflows/lint.yaml`, `.github/workflows/test.yaml`, and `.github/workflows/gowin.yaml`.
- **Resolution:** Apply **Decision 2** above (keep `src/config.json` locked template parameters intact; update `info.yaml` to `50000000` Hz; unify `source_files`).

---

## 3. FPGA, Cortex-M3 Integration & Firmware (`src_gowin/`, `src_m3/`, `test/TT_MAC_RUN.PY`)

### F-FPGA-01 · Critical · `ahb2_mac_bridge.v` violates AHB-Lite 2-phase pipelining on DMA reads and writes
- **Location:** [`src_gowin/ahb2_mac_bridge.v:212-226`](../src_gowin/ahb2_mac_bridge.v#L212-L226), [`src_gowin/ahb2_mac_bridge.v:262-278`](../src_gowin/ahb2_mac_bridge.v#L262-L278)
- **Finding:** In ARM AHB-Lite, a transfer consists of an **Address Phase** (cycle $T$, where `HTRANS=NONSEQ` is sampled when `HREADY=1`) followed by a **Data Phase** (cycle $T+1$, where `HRDATA` is read or `HWDATA` is driven until `HREADY=1`).
  - **DMA Read bug:** `STATE_REQ_DATA` schedules `m_htrans <= 2'b10` (active on cycle $T+1$). On cycle $T+1$ (`STATE_WAIT_DATA`), if `m_hready == 1`, the bridge immediately latches `m_hrdata` on the **Address Phase edge**—one cycle before the SRAM returns read data.
  - **DMA Write bug:** `STATE_REQ_WRITE` drives `m_htrans <= 2'b10` and `m_hwdata <= result_accumulator` together, then `STATE_WAIT_WRITE` deasserts `m_htrans`, `m_hwrite`, and `m_hsel` after a single `m_hready` cycle (dropping `m_hsel` during the Data Phase).
  - Additionally, the DMA FSM hardcodes the 41-cycle standard sequence and cannot handle Short Protocol (`ui_in[7]=1`) or Packed FP4 (25 cycles).

### F-FPGA-02 · High · Glitch-prone fabric-generated clocks (`mac_clk`) in Gowin M3 wrappers
- **Location:** [`src_gowin/ahb2_mac_bridge.v:123`](../src_gowin/ahb2_mac_bridge.v#L123), [`src_gowin/tt_gowin_top_m3.v:109,172,250`](../src_gowin/tt_gowin_top_m3.v#L109)
- **Finding:** All four M3 integration modes drive the MAC unit's `clk` pin from fabric registers or combinational logic (`assign mac_clk = (state == STATE_IDLE) ? slave_mac_clk_pulse : (state == STATE_MAC_CLK_HI);` or `m3_gpio_o[11]`).
- **Impact:** Fabric-generated and combinational-muxed clocks introduce clock-tree skew, hold-time violations across `ext_clk` ↔ `mac_clk` boundaries, potential glitches on FSM transitions, and unreliable STA in `nextpnr-gowin`. Once `F-RTL-01` is fixed, `mac_clk` should be connected directly to `ext_clk` with a single-cycle synchronous pulse on `ena`.

### F-FPGA-03 · High · Unused bus handshaking and address-decoding omissions in `tt_gowin_top_m3.v`
- **Location:** [`src_gowin/tt_gowin_top_m3.v:154-166`](../src_gowin/tt_gowin_top_m3.v#L154-L166), [`src_gowin/tt_gowin_top_m3.v:205-215`](../src_gowin/tt_gowin_top_m3.v#L205-L215), [`src_gowin/tt_gowin_top_m3.v:295-299`](../src_gowin/tt_gowin_top_m3.v#L295-L299)
- **Finding:**
  1. In APB mode (`INTEGRATION_MODE == 1`), `APB_BASE_ADDR` and `m3_read` are completely unused; any peripheral write matching `m3_addr[7:0]` writes to MAC registers.
  2. In AHB/DMA modes (`INTEGRATION_MODE == 2, 3`), the system `m3_hready` input from `Gowin_EMPU_M3` is ignored (mode 3 loops `.s_hready(m3_hreadyout)` back to itself instead of `m3_hready`), violating multi-slave AHB-Lite bus rules, and `ahb2_mac_bridge`'s `AHB_BASE_ADDR` parameter is never checked.

### F-FW-01 · Critical · Multiple protocol bugs in Cortex-M3 firmware (`src_m3/main.c`)
- **Location:** [`src_m3/main.c:119-168`](../src_m3/main.c#L119-L168), [`src_m3/main.c:206-221`](../src_m3/main.c#L206-L221)
- **Finding:**
  1. **Off-by-1 cycle bug:** Lines 123–125 release reset, assert `ena`, and issue an extra `clock_tick()` **before** writing Cycle 0 metadata (`write_ui_in(cycle0_ui)` at line 128). That extra clock advances the MAC from Cycle 0 to Cycle 1 using stale bus values, shifting the entire 41-cycle protocol by 1 cycle.
  2. **Broken Packed Mode test (`'p'`):** Passes `format_a = 0` (E4M3) with `packed_mode = 1` (packed mode only activates for FP4 `format == 4`), and lines 147–152 falsely claim sending 32 cycles in packed mode is harmless (packed mode completes at Cycle 24, so 32 stream cycles overwrite the output phase).
  3. **Broken Short Protocol test (`'s'`):** Calls `run_mac_test_ext()`, which asserts `BIT_RST = 0` at line 120—wiping out the scales it intends to reuse.
  4. **GPIO-only:** No firmware driver exists for APB, AHB, or AHB-DMA modes despite CI building bitstreams for all four modes.

### F-FW-02 · Medium · Incomplete Cortex-M3 vector table and committed build artifacts in `src_m3/`
- **Location:** [`src_m3/startup.c:13-17`](../src_m3/startup.c#L13-L17), [`src_m3/Makefile`](../src_m3/Makefile)
- **Finding:** `vectors[]` only defines 2 entries (Initial SP and Reset Handler). On Cortex-M3, entries 2–15 cover NMI, HardFault, MemManage, BusFault, UsageFault, SVCall, PendSV, and SysTick; any exception jumps into executable code at `0x08..0x3C`. Additionally, `src_m3/Makefile` omits the `bin2mi.py` rule to generate `testbench.mi`, while compiled binaries (`testbench.bin`, `testbench.elf`, `testbench.mi`) are tracked in git.

### F-FW-03 · Medium · `test/TT_MAC_RUN.PY` clocks Cycle 0 without initializing input pins
- **Location:** [`test/TT_MAC_RUN.PY:60-70`](../test/TT_MAC_RUN.PY#L60-L70)
- **Finding:** `run_mac()` calls `clock_step()` at line 69 (Cycle 0 → Cycle 1) without first calling `set_ui_in(0x00)` and `set_uio_in(0x00)`. Whatever residual state exists on the RP2040/RP2350 GPIO pins is latched as Cycle 0 metadata.

---

## 4. Web Digital Twin & WASM (`docs/web/`, `wasm/`)

### F-WEB-01 · Critical · `docs/web/main.js` drops Byte 3 (MSB) on every simulation run
- **Location:** [`docs/web/main.js:221-236`](../docs/web/main.js#L221-L236)
- **Finding:** After Cycle 36's `twin.step()` (line 225), `logical_cycle` is `37` and `uo_out` already holds **Byte 3 (MSB)**. Inside the readout loop (lines 231–236), `main.js` calls `twin.step()` **before** `twin.get_uo_out()`:
  ```javascript
  for (let i = 0; i < 4; i++) {
      twin.step();                      // Advances 37->38, discarding Byte 3!
      const byte = BigInt(twin.get_uo_out());
      result = (result << 8n) | byte;
  }
  ```
- **Impact:** Byte 3 is discarded, Bytes 2–0 are shifted left by 8 bits, and Byte 0 becomes `0x00` (Cycle 0), corrupting every single result in the primary Digital Twin demo.

### F-WEB-02 · Critical · Both Web UIs decode S23.8 fixed-point output as IEEE-754 Float32
- **Location:** [`docs/web/main.js:180,238-242`](../docs/web/main.js#L180), [`docs/web/mac.js:262,316-321`](../docs/web/mac.js#L262)
- **Finding:** Neither `main.js` nor `mac.js` sets `ui_in[5] = 1` (`float32_mode_reg`) in Cycle 0, so the RTL outputs **S23.8 signed fixed-point**. Both scripts then interpret the 32-bit output via `DataView.getFloat32(0, false)`, displaying denormalized/nonsense floating-point numbers (e.g., `0x00002000` for `32.0` displays as `1.148e-41`).

### F-WEB-03 · Medium · Additional Web UI / WASM configuration mismatches
- **Location:** [`docs/web/main.js:61-66,163-183`](../docs/web/main.js#L61-L66), [`docs/web/mac.js:70,255`](../docs/web/mac.js#L70), [`.github/workflows/gds.yaml:90`](../.github/workflows/gds.yaml#L90), [`.github/workflows/wasm.yaml:44`](../.github/workflows/wasm.yaml#L44)
- **Finding:**
  1. **Packed mode guard missing:** `isPacked` checks only `packed-mode === 1` without checking `format-a == 4 && format-b == 4`, desynchronizing JS cycle counts from RTL whenever Packed is toggled on non-FP4 formats.
  2. **Short Protocol broken in `main.js`:** `runSimulation()` always resets the twin (`set_rst_n(false)`), erasing prior scales, and writes `nbm-offset-b` instead of `format-a` into `uio0[2:0]`.
  3. **`INT8_SYM` `0x80` mismatch:** JS returns `NaN` for `0x80`, while `fp8_mul.v` line 186 clamps `0x80` to `-127`.
  4. **Inactive LNS UI selector:** Both `wasm.yaml` and `gds.yaml` compile WASM with default `USE_LNS_MUL=0`, so selecting LNS/Hybrid in the UI has zero effect.
  5. **WASM build divergence:** `gds.yaml` (deployed to GitHub Pages) builds WASM with `ACCUMULATOR_WIDTH=32`, while `wasm.yaml` builds `Full` with `ACCUMULATOR_WIDTH=40`.

---

## 5. Verification, Testing & CI/CD (`test/`, `scripts/`, `.github/workflows/`)

### F-CI-01 · High · Over half the test suite is orphaned from CI, masking broken tests
- **Location:** [`test/run_tests.sh:16-17`](../test/run_tests.sh#L16-L17), [`.github/workflows/test.yaml:44-61`](../.github/workflows/test.yaml#L44-L61), [`test/test_debug.py:6-34`](../test/test_debug.py#L6-L34), [`test/test_ofp8_compliance.py:27-84`](../test/test_ofp8_compliance.py#L27-L84)
- **Finding:** `test/run_tests.sh` only executes 5 top-level modules (`test`, `test_coverage`, `test_performance`, `test_short_protocol`, `test_exhaustive`). **11 test targets are never run in CI**:
  - Top-level tests: `test_debug.py`, `test_ofp8_compliance.py`, `test_async_reset.py`, `test_fp8_legacy.py`
  - Unit tests: `Makefile_accumulator`, `Makefile_accumulator_serial`, `Makefile_aligner`, `Makefile_f2f`, `Makefile_lzc40`, `test_fp8_mul_serial_lns.py`
  - Structural check: `verify_rtl_m3.py`
- **Confirmed regressions hidden by this gap:**
  - `test_debug.py` fails against current RTL: it places `probe_sel` in `uio_in[3:0]` (RTL reads `ui_in[3:0]`) and triggers loopback with `debug_en=0, loopback_en=1` (RTL requires `ui_in[5] && ui_in[6]`).
  - `test_ofp8_compliance.py` fails against current 40-bit S23.16 RTL: lines 27–31 and 75–83 assert old 32-bit S23.8 rounding expectations (`32`, `0`, `64` instead of `18`, `16`, `48`).

### F-CI-02 · High · Variant definitions drift across 5 files; duplicate CI jobs leave narrow widths untested
- **Location:** [`.github/workflows/test.yaml:47-59`](../.github/workflows/test.yaml#L47-L59), [`.github/workflows/wasm.yaml:42-57`](../.github/workflows/wasm.yaml#L42-L57), [`.github/workflows/gowin.yaml:52-61`](../.github/workflows/gowin.yaml#L52-L61), [`scripts/configure_variant.py:25-47`](../scripts/configure_variant.py#L25-L47)
- **Finding:** Variant parameters (`Full`, `Lite`, `Tiny`, `Ultra-Tiny`, `Tiny-Serial`) are copy-pasted independently across `test.yaml`, `wasm.yaml`, `gowin.yaml`, `gds.yaml`, `run_all_configs.sh`, `gate_analysis.py`, and `scripts/configure_variant.py`—and have diverged sharply:
  - In `test.yaml` (lines 51–54) and `wasm.yaml` (lines 49–54), **`Tiny` and `Ultra-Tiny` are byte-for-byte identical**, wasting CI time while leaving `ALIGNER_WIDTH=32` / `ACCUMULATOR_WIDTH=24` (used in `gowin.yaml` Ultra-Tiny & Tiny-Serial) completely untested in simulation.
  - `scripts/configure_variant.py tiny` sets **all** format flags (including `SUPPORT_E4M3`) to `0`, creating a broken build with zero enabled formats.
  - `USE_LNS_MUL=1` is never tested in CI.

### F-CI-03 · Medium · CI workflow trigger, linting, and error-handling gaps
- **Location:** [`.github/workflows/test.yaml:2`](../.github/workflows/test.yaml#L2), [`.github/workflows/lint.yaml:16`](../.github/workflows/lint.yaml#L16), [`test/gate_analysis.py:59-61`](../test/gate_analysis.py#L59-L61)
- **Finding:**
  1. `test.yaml` triggers only on `[push, workflow_dispatch]`, omitting `pull_request` (unlike `lint.yaml`).
  2. `lint.yaml` only lints the default `project.v` parameters (missing `USE_LNS_MUL=1`, `SUPPORT_SERIAL=1`, `IS_FP4_ONLY`, and narrow widths) and omits `src/accumulator_serial.v` and `src_gowin/*.v`.
  3. `test/gate_analysis.py` returns `None` and exits with code `0` when Yosys synthesis fails (lines 59–61), silently masking synthesis errors in CI.

---

## 6. Documentation & Repository Hygiene (`README.md`, `docs/`, root directory)

### F-DOC-01 · High · Severe documentation drift against actual RTL protocol and defaults
- **Location:** [`README.md:83-135,229-250`](../README.md#L83-L135), [`docs/DEBUG_TT.md:11-40`](DEBUG_TT.md#L11-L40), [`docs/info.md:91-167`](info.md#L91-L167), [`docs/FP32_AUDIT.md`](FP32_AUDIT.md)
- **Finding:**
  - `README.md`, `docs/info.md`, and `docs/DEBUG_TT.md` all document `uio_in[3:0]` as the Debug Probe Selector and `ui_in[5]` alone as Loopback Enable, contradicting `src/project.v`.
  - `float32_mode` (`ui_in[5]`) and Float32 probes `0xE`/`0xF` are undocumented in `README.md`, `docs/info.md`, and `docs/DEBUG_TT.md`.
  - `README.md` lines 229–250 list outdated default parameters (`ALIGNER_WIDTH=32`, `ACCUMULATOR_WIDTH=24`, `SUPPORT_E5M2=0`, `SUPPORT_SERIAL=1`, `ENABLE_SHARED_SCALING=0`) that contradict `src/project.v` (`40`, `40`, `1`, `0`, `1`).
  - `docs/FP32_AUDIT.md` is still written in present tense claiming `fixed_to_float` and 40-bit alignment are missing, even though Steps 9–28 are complete.

### F-DOC-02 · Medium · Broken internal links in documentation
- **Location:** [`README.md:52`](../README.md#L52), [`docs/FP32_AUDIT.md:35`](FP32_AUDIT.md#L35)
- **Finding:**
  - `README.md` links to `docs/hardware/LOCAL_SETUP.md`, which does not exist in the repository.
  - `docs/FP32_AUDIT.md` links to `../ROADMAP.md#6-numerical-precision--fp32-compliance`, an anchor that no longer exists in `ROADMAP.md`.

### F-REPO-01 · Medium · Repository clutter, duplicated PDFs, and tracked build binaries
- **Location:** Repository root, `docs/integration/RISCV/`, `docs/reference/`, `docs/research/`, `src_m3/`
- **Finding:**
  1. **10 ad-hoc one-off scripts in the repository root:** `final_fix.py`, `fix_docs.py`, `update_docs.py`, `update_docs_v2.py`, `update_docs_v3.py`, `update_docs_v4.py`, `update_everything.py`, `update_final.py`, `update_final_all.py`, `verify_fp4.py`.
  2. **~12 MB of committed external PDFs & duplicates:** `OCP-MICROSCALING-FORMATS-MX-V1-0-SPEC.PDF` (812 KB) is duplicated identically in `docs/integration/RISCV/` and `docs/reference/`; `PAPER_TEXT.TXT` and `MX_PLUS_PAPER_TEXT.TXT` (103 KB each) are byte-for-byte duplicates; two copies of `2510.14557V1.PDF` (2.1 MB and 1.0 MB) and both `TurboQuant.md` and `TURBO_QUANT.md` exist.
  3. **Tracked build outputs:** `src_m3/testbench.bin`, `src_m3/testbench.elf`, and `src_m3/testbench.mi` are committed directly in git.

---

## Derived Improvement Proposals & Implementation Plan (Handoff to Gemini Hydrogen)

> **Note for Implementer (`docs/GEMINI.md` rules):**
> - Keep all markdown filenames UPPERCASE (except `.md` extension and `docs/info.md`).
> - Include specification-derivation comments for every YAML test case added/updated.
> - Update `docs/hardware/DIE_SIZE_ANALYSIS.md` after Verilog changes.
> - Do NOT alter locked parameters below the Tiny Tapeout template boundary in `src/config.json`.

### Phase 1 · Critical Silicon & Functional Fixes (Immediate Priority)

- [ ] **P1.1 · Gate `acc_en` with `ena` (`F-RTL-01`)**
  - Change `src/project.v:390` to `wire acc_en = ena && strobe && (...)`.
  - Add a Cocotb test in `test/test.py` (or `test/test_async_reset.py`) that deasserts `ena=0` mid-stream for several cycles and verifies exact MAC output.

- [ ] **P1.2 · Implement Decision 1 for Cycle 0 Control/Debug Bits (`F-RTL-02`, `F-DOC-01`)**
  - Update `src/project.v` lines 123–131, 183–190, 355–362:
    - `loopback_en_reg <= loopback_en_reg | (ui_in[6] && ui_in[4]);`
    - `probe_sel_reg <= ui_in[3:0];` (captured when `ui_in[6]` is high)
    - Gate `lns_mode_reg` and `nbm_offset_a` updates with `!ui_in[6]` so debug mode never corrupts them.
    - Keep `float32_mode_reg <= ui_in[5];` independent of debug/loopback.
  - Update `test/test_debug.py` (including new tests for Float32 Probes `0xE` and `0xF`), `README.md`, `docs/info.md`, `docs/DEBUG_TT.md`, and WaveDrom JSON/SVG files (`METADATA_C0_UI_BITFIELD.*`, `METADATA_C0_UIO_DEBUG_BITFIELD.*`).

- [ ] **P1.3 · Implement Decision 3 for Fixed-Point vs. Float32 NaN/Inf (`F-RTL-10`)**
  - Update `sticky_byte` in `src/project.v` lines 908–919 & 994:
    - When `float32_mode_reg == 1`: rely directly on `f2f_result` (which already outputs `0x7FC00000`, `0x7F800000`, `0xFF800000`).
    - When `float32_mode_reg == 0` and `sticky_any == 1`: emit `0x7FFFFFFF` for `+Inf`, `0x80000000` for `-Inf` or `NaN` (`nan_sticky || (inf_pos_sticky && inf_neg_sticky)`).
  - Update fixed-point NaN/Inf assertions in `test/test.py`, `test/TEST_MX_E2E.yaml`, `test/test_short_protocol.py`, and `test/test_ofp8_compliance.py`; verify IEEE-754 patterns in Float32 mode tests.

- [ ] **P1.4 · Fix Narrow-Accumulator Saturation & Verilog Portability (`F-RTL-03`, `F-RTL-09`)**
  - In `src/project.v` (`gen_lane_ext_narrow`), saturate `aligned_lane0_res` / `aligned_lane1_res` to `[-2^(ACCUMULATOR_WIDTH-1), 2^(ACCUMULATOR_WIDTH-1)-1]` when `!overflow_wrap` before narrowing to `ACCUMULATOR_WIDTH`.
  - Pass `aligned_combined[ACCUMULATOR_WIDTH-1:0]` to `acc_inst.data_in`.
  - Fix 0-width replication in `src/accumulator.v:69` using a `generate` block (`if (REG_WIDTH > 32) ... else ...`).
  - Remove the `initial` block in `src/project.v:327-335` and convert `lns_lut` in `src/fp8_mul_lns.v:75-85` to a combinational `case` function.

- [ ] **P1.5 · Fix Web Digital Twin Readout Timing & Float32 Mode (`F-WEB-01`, `F-WEB-02`, `F-WEB-03`)**
  - In `docs/web/main.js`, call `twin.get_uo_out()` **before** `twin.step()` in the 4-byte readout loop.
  - Add an Output Format selector (`Float32` vs. `Fixed-Point S23.8`) in `docs/web/index.html` and `docs/web/mac.html`; set `ui_in[5] = 1` when Float32 is selected, and decode signed S23.8 (`val / 256.0`) when Fixed-Point is selected.
  - Guard `isPacked` with `(fmtA === 4 && fmtB === 4)`, fix `decode_int8_sym(0x80)` to `-127 / 64.0`, fix Short Protocol in `main.js` (preserve scales, write `format-a` to `uio0[2:0]`), and align `gds.yaml` WASM `ACCUMULATOR_WIDTH=40` with `wasm.yaml`.

- [ ] **P1.6 · Apply Decision 2 for ASIC Spec Alignment (`F-ASIC-01`)**
  - Update `info.yaml`: `clock_hz: 50000000`, update tile size comment to `202x155 uM`.
  - Keep `src/config.json` locked Tiny Tapeout template settings untouched (`CLOCK_PERIOD: 20`, `RUN_KLAYOUT_DRC: 0`, `RUN_KLAYOUT_XOR: 0`, `GRT_ALLOW_CONGESTION: 1`).
  - Update `docs/info.md` clock spec to `50 MHz`.

---

### Phase 2 · Verification, Formal Proofs & CI/CD Hardening

- [ ] **P2.1 · Single Source of Truth for Hardware Variants (`F-CI-02`)**
  - Create `variants.json` defining `Full`, `Lite`, `Tiny`, `Ultra-Tiny`, `Tiny-Serial`, and `LNS` parameters.
  - Update `test.yaml`, `wasm.yaml`, `gowin.yaml`, `gds.yaml`, `test/gate_analysis.py`, `run_all_configs.sh`, and `scripts/configure_variant.py` to consume `variants.json`.
  - Ensure `Ultra-Tiny` tests `ALIGNER_WIDTH=32, ACCUMULATOR_WIDTH=24`, `Tiny` enables `SUPPORT_E4M3=1`, and CI tests `USE_LNS_MUL=1`.

- [ ] **P2.2 · Re-integrate All Orphaned Tests & Harden CI (`F-CI-01`, `F-CI-03`)**
  - Update `test/test_ofp8_compliance.py` for 40-bit S23.16 expectations (parameterized by `ALIGNER_WIDTH`).
  - Run `test_debug`, `test_ofp8_compliance`, `test_async_reset`, `verify_rtl_m3.py`, and all unit Makefiles (`Makefile_accumulator`, `Makefile_accumulator_serial`, `Makefile_aligner`, `Makefile_aligner_serial`, `Makefile_f2f`, `Makefile_lzc40`, `test_fp8_mul_serial_lns.py`) in `.github/workflows/test.yaml`.
  - Add `pull_request` trigger to `test.yaml`.
  - Expand `.github/workflows/lint.yaml` to lint multiple parameter configurations, `src/accumulator_serial.v`, and `src_gowin/*.v`.
  - Make `test/gate_analysis.py` exit with non-zero status on Yosys synthesis failure.

- [ ] **P2.3 · Repair & Automate SymbiYosys Formal Verification (`F-FV-01`)**
  - Update `src/project.sby` to read all required RTL files and include a `bmc` task with `depth 45`.
  - Fix the `mx_plus_en_val` guard (line 1121) and `$past(last_cycle)` check (line 1045) in `src/project.v`.
  - Add a `formal` job to `.github/workflows/lint.yaml` using `YosysHQ/setup-oss-cad-suite`.

---

### Phase 3 · Arithmetic, Bit-Serial & FPGA/M3 Architecture Improvements

- [ ] **P3.1 · Refactor `fp8_mul_lns.v` and Add `SUPPORT_FLOAT32` Pruning (`F-RTL-04`, `F-RTL-08`, `F-RTL-10`)**
  - Add `SUPPORT_FLOAT32` parameter to `src/project.v` (default `1` in `Full`, `0` in `Tiny`/`Ultra-Tiny`/`Tiny-Serial`) to prune `fixed_to_float` + `lzc40` when unused.
  - Default `SUPPORT_INPUT_BUFFERING = 0` when `SUPPORT_VECTOR_PACKING = 1`, and guard `gen_input_buffering` with `SUPPORT_INPUT_BUFFERING && !SUPPORT_VECTOR_PACKING`.
  - In `src/fp8_mul_lns.v`: gate exact multiplier behind `SUPPORT_LNS_HYBRID` so pure LNS actually saves area; fix subnormal handling and MX+ Block Max handling; handle INT8 cleanly.
  - Clarify or gate `R_RNE` vs. `SUPPORT_ADV_ROUNDING` consistently between `src/fp8_aligner.v` and docs.

- [ ] **P3.2 · Fix Bit-Serial Submodules & Complete `SUPPORT_SERIAL=1` Integration (`F-RTL-05`, `F-RTL-06`, `F-RTL-07`)**
  - Fix `src/fp8_mul_serial_lns.v`: mask sign bits from serial adder (`cnt < s_p_a`, `cnt < s_p_b`), reset/clear `a_m_delay`/`b_m_delay`, fix E4M3 NaN (require all mantissa bits `1`), add `Inf * 0 = NaN`, sign-extend `bias_offset`, add negative/subnormal unit tests.
  - Fix `src/fp8_aligner_serial.v`: clear `delay_line` on `strobe`, implement bit-skipping for `k0 < 0`.
  - Wire `fp8_mul_serial_lns`, `fp8_aligner_serial`, and `accumulator_serial` into `src/project.v` when `SUPPORT_SERIAL = 1` (Steps 4.4–4.8 of `ROADMAP.md`), and verify area reduction in `gate_analysis.py`.

- [ ] **P3.3 · Redesign Gowin M3 Bridges & Fix Firmware Drivers (`F-FPGA-01`, `F-FPGA-02`, `F-FPGA-03`, `F-FW-01`, `F-FW-02`, `F-FW-03`)**
  - Connect `mac_inst.clk` directly to `ext_clk` in `src_gowin/tt_gowin_top_m3.v` and `src_gowin/ahb2_mac_bridge.v`, driving `mac_ena` as a single-cycle synchronous clock enable instead of fabric-generated `mac_clk`.
  - Fix AHB-Lite 2-phase Address/Data pipelining in `src_gowin/ahb2_mac_bridge.v`, properly wire `m3_hready`, decode `APB_BASE_ADDR`/`AHB_BASE_ADDR`, and add a Cocotb simulation testbench for `ahb2_mac_bridge.v`.
  - Fix `src_m3/main.c` (remove stray post-reset `clock_tick()`, fix Packed FP4 & Short Protocol tests), expand `src_m3/startup.c` to full 16-entry Cortex-M3 exception vectors, add `testbench.mi` target to `src_m3/Makefile`, and initialize `ui_in`/`uio_in` to `0x00` before Cycle 0 in `test/TT_MAC_RUN.PY`.

---

### Phase 4 · Documentation & Repository Hygiene

- [ ] **P4.1 · Clean Up Repository Clutter & Documentation Drift (`F-DOC-01`, `F-DOC-02`, `F-REPO-01`)**
  - Delete obsolete root scripts: `final_fix.py`, `fix_docs.py`, `update_docs.py`, `update_docs_v2.py`, `update_docs_v3.py`, `update_docs_v4.py`, `update_everything.py`, `update_final.py`, `update_final_all.py`, `verify_fp4.py`.
  - Remove duplicate external files (`docs/integration/RISCV/OCP-MICROSCALING-FORMATS-MX-V1-0-SPEC.PDF`, `docs/research/PAPER_TEXT.TXT`, duplicate `2510.14557V1.PDF`), and untrack/ignore `src_m3/testbench.{bin,elf,mi}`.
  - Sync `README.md` parameter defaults and Cycle 0 tables with `src/project.v`, fix broken link to `docs/hardware/LOCAL_SETUP.md`, mark `docs/FP32_AUDIT.md` as resolved/historical with valid links, update `docs/hardware/DIE_SIZE_ANALYSIS.md`, and add a Sphinx linkcheck step to `.github/workflows/docs.yaml`.
