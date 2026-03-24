# APB Integration Concept: Cortex-M3 to MAC Unit

This document outlines the integration concept for connecting the ARM Cortex-M3 (EMCU) to the Tiny Tapeout MAC unit via the **Advanced Peripheral Bus (APB)** on the Gowin GW1NSR-4C FPGA.

## 1. Introduction

Currently, the Cortex-M3 interfaces with the MAC unit using a **16-bit multiplexed GPIO interface**. While functional for testing, this approach requires significant CPU overhead for bit-banging the 41-cycle protocol and toggling the clock. Transitioning to an **APB-based memory-mapped interface** allows for higher throughput, lower latency, and cleaner software abstraction.

## 2. Current GPIO Implementation (Status Quo)

The current implementation in `src_gowin/tt_gowin_top_m3.v` uses a 16-bit GPIO bus:
- **GPIO[7:0]**: Data Bus (Multiplexed)
- **GPIO[10:8]**: Address (Selects `ui_in`, `uio_in`, `uo_out`, etc.)
- **GPIO[11-14]**: Control (`clk`, `rst_n`, `ena`, `WEN`)

**Limitations:**
- Software must manually toggle `GPIO[11]` (mac_clk) for every cycle.
- Software must manage the 8-bit data bus direction (input/output) during reads.
- High interrupt latency if other tasks are running on the M3.

## 3. Proposed APB Integration Architecture

The APB interface will act as a bridge (Slave) between the M3's Peripheral Bus and the MAC unit. It replaces the manual GPIO toggling with hardware-assisted register access.

### Block Diagram Concept
```text
[ Cortex-M3 ] <--- APB Bus ---> [ APB-to-MAC Bridge ] <---> [ MAC Unit ]
                                   (Register Map)            (ui, uo, uio)
                                   (State Machine)           (mac_clk gen)
```

## 4. APB Register Map

The bridge will be mapped to a dedicated peripheral address space (e.g., `0x40020000`).

| Offset | Name | Access | Description |
|:---:|---|:---:|---|
| `0x00` | **DATA_IN** | W | Writes to `ui_in` (low byte) and `uio_in` (high byte). Triggers a `mac_clk` pulse. |
| `0x04` | **DATA_OUT** | R | Reads `uo_out` (low byte) and `uio_out` (high byte). |
| `0x08` | **CTRL** | RW | Bit 0: `ena`, Bit 1: `rst_n`, Bit 2: `auto_clk` enable. |
| `0x0C` | **STATUS** | R | Bit 0: Busy (Protocol in progress), Bit 1: Result Valid. |
| `0x10` | **CONFIG** | RW | Clock divider settings for `mac_clk` generation. |

## 5. APB Slave State Machine & Timing

The APB Slave logic handles the handshake between the fast M3 bus clock and the MAC unit's protocol.

### APB Write Cycle (DATA_IN)
1. **PSEL & PENABLE**: M3 initiates a write to `0x00`.
2. **Latch**: Bridge latches the 16-bit data.
3. **Pulse**: Bridge automatically generates a single `mac_clk` pulse after the write completes.
4. **READY**: Bridge pulls `PREADY` low if it needs more than one cycle to stabilize the fabric signals (stretching the APB access).

### APB Read Cycle (DATA_OUT)
1. **PSEL & PENABLE**: M3 initiates a read from `0x04`.
2. **MUX**: Bridge connects internal `uo_out` and `uio_out` signals to `PRDATA`.
3. **Completion**: Data is returned to M3 in a single cycle.

## 6. Comparison & Advantages

| Feature | GPIO (Multiplexed) | APB (Memory Mapped) |
|---|---|---|
| **CPU Usage** | High (Bit-banging) | Low (Store/Load) |
| **Max Clock Speed** | ~500 kHz (Software Ltd) | ~10 MHz (Hardware Ltd) |
| **Code Size** | Large (Driver functions) | Small (Direct pointers) |
| **Bus Integrity** | Manual direction switching | Hardware-managed |

## 7. Implementation Roadmap

1. **RTL Development**: Create `src_gowin/apb_mac_bridge.v` implementing the APB Slave interface.
2. **Integration**: Update `tt_gowin_top_m3.v` to instantiate the bridge instead of direct GPIO mapping.
3. **CST Update**: Update `tangnano4k_m3.cst` if any physical pins change (though APB is internal).
4. **Firmware Update**: Refactor `main.c` to use `*(volatile uint32_t *)0x40020000` instead of GPIO registers.
5. **Verification**: Run Cocotb tests with an APB BFM to verify the bridge timing.
