# JTAG Integration Concept for OCP MXFP8 Streaming MAC

This document outlines the proposal for adding JTAG-based debug and data retrieval capabilities to the Tiny Tapeout project. JTAG provides a standard way to probe internal registers and state without consuming additional output cycles in the primary protocol.

## 1. Activation Sequence (The "ACDC" Knock)

To ensure the JTAG logic does not interfere with standard operation or accidental triggers, it is gated by a "Magic Knock" sequence during the **Cycle 0 (STATE_IDLE)** phase.

### Trigger Condition
On the **falling edge of the clock in Cycle 0**, the hardware checks for the following conditions:
1. **DEBUG Enable**: `ui_in[6]` must be high (`1`).
2. **Magic Value**: The concatenated inputs `{uio_in, ui_in}` must equal `0xACDC`.

| Port | Hex Value | Binary | Notes |
|:---:|:---:|:---:|---|
| `uio_in` | `0xAC` | `1010 1100` | MSB of the knock |
| `ui_in` | `0xDC` | `1101 1100` | LSB of the knock (Bit 6 is Debug En) |

### State Transition
Once the knock is detected, the unit enters **JTAG Mode**. In this mode, the FSM can either be paused or continue running, but the pin functions of `ui_in` and `uo_out` are repurposed to serve the JTAG TAP (Test Access Port) controller.

## 2. JTAG Pin Mapping

The following mapping is proposed to implement a standard 4-wire JTAG interface using the existing Tiny Tapeout pins.

| TT Pin | JTAG Function | Direction | Description |
|:---:|:---:|:---:|---|
| `ui_in[0]` | **TCK** | Input | Test Clock |
| `ui_in[1]` | **TMS** | Input | Test Mode Select |
| `ui_in[2]` | **TDI** | Input | Test Data In |
| `uo_out[0]` | **TDO** | Output | Test Data Out |
| `ui_in[3]` | **TRSTn** | Input | Test Reset (Active Low) |

*Note: `uio_in` pins remain available for their standard functions or can be used as additional debug inputs if needed.*

## 3. Sophistication Levels

The JTAG implementation can be scaled in complexity based on available gate area and debugging needs.

### Level 1: Basic Compliance (Boundary & ID)
- **Estimated Die Size**: **~150 gates** (Comparable to `SUPPORT_DEBUG`)
- **Features**:
  - **BYPASS**: A 1-bit register to allow the device to be bypassed in a chain.
  - **IDCODE**: Returns a unique 32-bit ID for the OCP MAC Unit (e.g., `0x0ACDC001`).
- **Goal**: Verify that the JTAG knock worked and the TAP controller is responsive.

### Level 2: Data Retrieval (Accumulator Access)
- **Estimated Die Size**: **~300 gates**
- **Features**:
  - **READ_ACC (Instruction)**: Connects the 32-bit Accumulator register to the Data Register (DR) scan chain.
- **Benefit**: Allows the external controller to read the final result immediately after the `STREAM` phase ends, bypassing the 4-cycle `STATE_OUTPUT` serialization.

### Level 3: Advanced Probing (Internal Visibility)
- **Estimated Die Size**: **500+ gates**
- **Features**:
  - **SCAN_STATE (Instruction)**: Connects a large internal scan chain containing FSM state, cycle counter, sticky bits, and pipeline registers.
  - **DEBUG_OVR (Instruction)**: Allows overriding the `probe_sel` via JTAG, enabling real-time logic analyzer functionality on `uo_out[7:1]`.

## 4. Implementation Notes
- **Clock Domains**: The JTAG TAP typically runs on `TCK`. Care must be taken to synchronize data between the system `clk` and `TCK` if asynchronous reading is required.
- **Area Impact Summary**:
  - **Level 1**: Fits easily within a **1x1 Tiny Tapeout tile**.
  - **Level 2**: Fits within a **1x1 tile** if other non-essential features (like `SUPPORT_MX_PLUS`) are disabled.
  - **Level 3**: Likely requires a **1x2 or 2x2 tile** configuration (e.g., the "Full" variant) to accommodate the scan chain overhead.
- **Persistence**: JTAG mode should persist until a hard reset (`rst_n`) or a specific JTAG "Exit" command is issued.
