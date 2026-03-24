# ARM Cortex-M3 Integration: MAC Unit Accelerator

This document consolidates the integration concepts for connecting the ARM Cortex-M3 (EMCU) to the Tiny Tapeout MAC unit on the Gowin GW1NSR-4C FPGA, ranging from simple GPIO bit-banging to high-performance AHB Master/DMA modes.

## 1. Introduction

The Gowin GW1NSR-4C provides a hard-core ARM Cortex-M3 (EMCU) which can be used to drive the MAC unit. Depending on the performance requirements and available FPGA resources, several integration levels are possible. Transitioning from the current bit-banged GPIO approach to a memory-mapped interface (APB or AHB) allows for higher throughput, lower latency, and cleaner software abstraction.

## 2. Current GPIO Implementation (Status Quo)

The current implementation in `src_gowin/tt_gowin_top_m3.v` uses a **16-bit multiplexed GPIO interface**:
- **GPIO[7:0]**: Data Bus (Multiplexed)
- **GPIO[10:8]**: Address (Selects `ui_in`, `uio_in`, `uo_out`, etc.)
- **GPIO[11-14]**: Control (`clk`, `rst_n`, `ena`, `WEN`)

**Limitations:**
- Software must manually toggle `GPIO[11]` (mac_clk) for every cycle.
- Software must manage the 8-bit data bus direction (input/output) during reads.
- High CPU overhead for bit-banging the 41-cycle protocol.
- Max clock speed is limited by software execution (approx. 500 kHz).

## 3. Hybrid Integration Mode (APB-Write / GPIO-Read)

The **Hybrid mode** serves as a bridge between full software control and full hardware automation.
- **Mechanism**: Accelerates the 32-cycle streaming phase by automating clock generation in hardware via an APB bridge for writes.
- **Simplification**: Uses the existing GPIO path for the low-frequency read phase (Cycles 37-40), simplifying the bridge design.
- **Benefit**: Significantly reduces CPU overhead during the data-intensive streaming phase without the complexity of a full bidirectional APB-to-MAC bridge.

## 4. APB Integration (Peripheral Mode)

The APB interface acts as a Slave between the M3's Peripheral Bus and the MAC unit, replacing manual GPIO toggling with hardware-assisted register access.

### Block Diagram Concept
```text
[ Cortex-M3 ] <--- APB Bus ---> [ APB-to-MAC Bridge ] <---> [ MAC Unit ]
                                   (Register Map)            (ui, uo, uio)
                                   (State Machine)           (mac_clk gen)
```

### APB Register Map
The bridge is mapped to a dedicated peripheral address space (e.g., `0x40020000`).

| Offset | Name | Access | Description |
|:---:|---|:---:|---|
| `0x00` | **DATA_IN** | W | Writes to `ui_in` (low byte) and `uio_in` (high byte). Triggers a `mac_clk` pulse. |
| `0x04` | **DATA_OUT** | R | Reads `uo_out` (low byte) and `uio_out` (high byte). |
| `0x08` | **CTRL** | RW | Bit 0: `ena`, Bit 1: `rst_n`, Bit 2: `auto_clk` enable. |
| `0x0C` | **STATUS** | R | Bit 0: Busy (Protocol in progress), Bit 1: Result Valid. |
| `0x10` | **CONFIG** | RW | Clock divider settings for `mac_clk` generation. |

### Automated Block Mode
To minimize software overhead, the bridge can implement an **Automated Block Mode** where a hardware sequencer manages the entire 41-cycle streaming protocol, triggered by a single control register bit.

## 5. AHB Integration (System Bus)

For maximum performance, the MAC unit can be integrated directly onto the **Advanced High-performance Bus (AHB)**, the primary system bus of the Cortex-M3. AHB allows for burst transfers and zero-wait-state accesses.

### 5.1. AHB_SLAVE (Peripheral Mode)

In this mode, the MAC unit functions as a passive peripheral on the system bus.

- **Operation**: An **AHB-to-MAC Bridge** module translates AHB protocol phases (`HSEL`, `HTRANS`, `HADDR`, `HWRITE`, `HWDATA`) into MAC control signals.
- **Pipeline Support**: AHB uses separate address and data phases. The bridge buffers the address for one cycle to correlate it with the data phase.
- **Wait-States**: The bridge uses the `HREADY` signal to pause the M3 if the MAC unit is busy with the sequential streaming protocol.
- **Advantages**: Zero-wait-state access (where possible), higher taktraten (clock rates), and lower latency compared to APB.

![Protocol States Diagram](https://www.plantuml.com/plantuml/proxy?cache=no&src=https://raw.githubusercontent.com/chatelao/ttihp-fp8-mul/main/docs/diagrams/PROTOCOL_STATES.PUML)

### 5.2. AHB_MASTER (DMA / Accelerator Mode)

In this mode, the integration includes a hardware sequencer that acts as a Bus Master.

- **Autonomous Access**: The unit requests the bus and reads operands (e.g., weights from Flash/SRAM) and input data directly from memory without CPU intervention.
- **Accelerator Structure**:
  1. M3 configures start address and block size via control registers.
  2. MAC unit takes over the bus and streams data autonomously.
  3. Results are written back directly to the destination memory.
- **Interrupts**: An IRQ informs the M3 when the operation is complete.
- **Advantages**: Minimal CPU load and maximum throughput (utilizing AHB bursts). Ideal for large-scale calculations such as LLM inference.

### 5.3. AHB2 DMA (Autonomous Master/Slave Hybrid)

This mode combines an AHB Slave for configuration and an AHB Master for autonomous data movement. It is designed for high-throughput batch processing where the CPU only initializes the transfer and is notified upon completion.

#### AHB2 Master Signals (DMA)
- `HADDR_M`: Address for memory-mapped read/write.
- `HTRANS_M`: Transfer type (IDLE, NONSEQ, SEQ).
- `HWRITE_M`: 0 for Read (operands), 1 for Write (result).
- `HSIZE_M`: Fixed at 32-bit for results, 8-bit/32-bit for operands.
- `HWDATA_M`: Data to be written to memory (MAC result).
- `HRDATA_M`: Data read from memory (MAC operands).
- `HREADY_M`: Wait-state signal from the memory/interconnect.

#### DMA Register Map (Base + 0x20)
| Offset | Name | Access | Description |
|:---:|---|:---:|---|
| `0x20` | **DMA_SRC_A** | RW | Source address for Operand A elements (32-bit). |
| `0x24` | **DMA_SRC_B** | RW | Source address for Operand B elements (32-bit). |
| `0x28` | **DMA_DST** | RW | Destination address for the 32-bit result (32-bit). |
| `0x2C` | **DMA_LEN** | RW | Number of blocks to process (16-bit). |
| `0x30` | **DMA_CTRL** | RW | Bit 0: Start, Bit 1: IE (Interrupt Enable), Bit 2: Mode. |
| `0x34` | **DMA_STAT** | R | Bit 0: Busy, Bit 1: Done, Bit 2: Error. |

#### DMA Operation Flow
1. **Setup**: CPU writes Source A/B, Destination, and Length to the DMA registers via the AHB Slave interface.
2. **Trigger**: CPU sets the `Start` bit in `DMA_CTRL`.
3. **Fetch**: The bridge becomes an AHB Master and fetches 32 elements for Operand A and B from SRAM.
4. **Compute**: The bridge drives the MAC protocol, streaming the fetched elements.
5. **Writeback**: Once the 32-bit result is ready, the bridge writes it to the `DMA_DST` address.
6. **Iterate**: If `DMA_LEN > 1`, the bridge increments addresses and repeats the cycle.
7. **Finish**: The `Done` bit is set, and an optional interrupt is triggered.

## 6. Comparison of Integration Methods

| Feature | GPIO (Status Quo) | Hybrid (APB/GPIO) | APB (Peripheral) | AHB_SLAVE | AHB_MASTER (DMA) |
|:---:|:---:|:---:|:---:|:---:|:---:|
| **Bus Type** | Bit-Banging | Mixed | Peripheral Bus | System Bus | System Bus |
| **Throughput** | ~100 KB/s | ~1 MB/s | ~2 MB/s | ~10-20 MB/s | >50 MB/s |
| **CPU Load** | 100% | High | Medium | Low | Minimal |
| **Footprint** | ~150 Gates | ~350 Gates | ~500 Gates | ~800 Gates | ~2000 Gates |
| **Design Effort**| Minimal | Low | Medium | High | Very High |

## 7. Implementation Roadmap

1. **RTL Development**: Create `src_gowin/apb_mac_bridge.v` (or AHB equivalent).
2. **Integration**: Update `tt_gowin_top_m3.v` to instantiate the chosen bridge instead of direct GPIO mapping.
3. **CST Update**: Update `tangnano4k_m3.cst` if any physical pins change (though APB/AHB are internal).
4. **Firmware**: Update `main.c` to use memory-mapped pointers (e.g., `*(volatile uint32_t *)0x40020000`) instead of GPIO bit-toggling.
5. **Verification**: Run Cocotb tests with appropriate Bus Functional Models (BFM) to verify timing and protocol compliance.
