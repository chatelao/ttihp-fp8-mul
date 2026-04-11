# Debug Capabilities for Tiny Tapeout Tapeout

This document proposes "best practices" debug capabilities for the OCP MXFP8 Streaming MAC Unit, specifically tailored for its first silicon tapeout on Tiny Tapeout.

## 1. Real-Time Observability (The "Logic Analyzer" Mode)

Since the OCP protocol leaves `uo_out` unused (driven to `0x00`) during the `IDLE`, `LOAD_SCALE`, and `STREAM` phases (Cycles 0–36), we can repurpose these pins for real-time internal signal probing.

### Configuration
A "Debug Instruction" is sampled in **Cycle 0** (STATE_IDLE):
- `ui_in[6]`: **Enable Debug Mode** (1 = Active, 0 = Normal)
- `uio_in[3:0]`: **Probe Selector** (Determines what signal is muxed to `uo_out`)

![Metadata 1 (uio_in) Debug Mode](docs/metadata_c0_uio_debug.svg)

### Probe Mappings (`uo_out` during Cycles 0-36)

| Selector | Signal Description | Bit Mapping |
|:---:|---|---|
| `0x0` | **Default** | `8'h00` (Normal operation) |
| `0x1` | **FSM State & Timing** | `[7:6]` State, `[5:0]` logical_cycle |
| `0x2` | **Exception Monitor** | `[7]` nan_sticky, `[6]` inf_pos, `[5]` inf_neg, `[4]` strobe, `[3:0]` 0 |
| `0x3` | **Accumulator [31:24]** | Live MSB of the accumulator |
| `0x4` | **Accumulator [23:16]** | Live Byte 2 |
| `0x5` | **Accumulator [15:8]** | Live Byte 1 |
| `0x6` | **Accumulator [7:0]** | Live LSB (Fixed-point fraction) |
| `0x7` | **Multiplier Lane 0 MSB** | `mul_prod_lane0[15:8]` (Exp sum / MSB) |
| `0x8` | **Multiplier Lane 0 LSB** | `mul_prod_lane0[7:0]` (Mantissa product) |
| `0x9` | **Control Signals** | `[7]` ena, `[6]` strobe, `[5]` acc_en, `[4]` acc_clear, `[3:0]` 0 |
| `0xA` | **Multiplier Lane 0 Meta** | `[7]` sign, `[6]` nan, `[5]` inf, `[4:0]` exp_sum[4:0] |
| `0xB` | **Multiplier Lane 1 MSB** | `mul_prod_lane1[15:8]` |
| `0xC` | **Multiplier Lane 1 LSB** | `mul_prod_lane1[7:0]` |
| `0xD` | **Multiplier Lane 1 Meta** | `[7]` sign, `[6]` nan, `[5]` inf, `[4:0]` exp_sum[4:0] |

## 2. Connectivity Loopback

To verify the PCB/Socket connectivity and the TT infrastructure before running complex arithmetic, a transparent loopback mode is provided.

- **Trigger**: `ui_in[5]` is set to `1` in **Cycle 0**.
- **Behavior**: The unit enters a persistent "Loopback Mode" until reset. It is **sticky** across block boundaries once enabled.
  - `uo_out = ui_in ^ uio_in`
  - `uio_oe = 8'h00` (All pins remain inputs to avoid combinational loops)
  - This allows verifying all 16 input pins (`ui_in[7:0]` and `uio_in[7:0]`) via the `uo_out` port.
  - This bypasses all FSM logic.

## 3. Metadata Echo

In **Cycle 35** (Pipeline Flush), if `debug_mode` is active, `uo_out` will echo the latched configuration instead of `0x00`.
- `uo_out[2:0]`: `format_a`
- `uo_out[4:3]`: `round_mode`
- `uo_out[5]`: `overflow_wrap`
- `uo_out[6]`: `packed_mode`
- `uo_out[7]`: `mx_plus_en`

This allows verifying that the setup cycles (1 & 2) were correctly sampled by the hardware.

## 4. Implementation Notes

- **Area Impact**: Approximately ~100-150 gates for the debug multiplexers.
- **Timing**: No impact on the critical path (arithmetic) as it only muxes the final `uo_out` stage which is already registered or gated.
- **Persistence**: Once `debug_mode` is enabled in Cycle 0, it remains active for that entire block operation (until `logical_cycle == 0`).
