# ARM Cortex-M3 Integration: MAC Unit Accelerator

This document consolidates the integration concepts for connecting the ARM Cortex-M3 (EMCU) to the Tiny Tapeout MAC unit on the Gowin GW1NSR-4C FPGA, ranging from simple GPIO bit-banging to high-performance AHB Master/DMA modes.

## 1. Introduction

The Gowin GW1NSR-4C provides a hard-core ARM Cortex-M3 (EMCU) which can be used to drive the MAC unit. Depending on the performance requirements and available FPGA resources, several integration levels are possible. Transitioning from the current bit-banged GPIO approach to a memory-mapped interface (APB or AHB) allows for higher throughput, lower latency, and cleaner software abstraction.

## 2. Toolchain Setup

To build and deploy the M3-integrated MAC unit, the following tools are required:

### 2.1. Arm Firmware Toolchain
- **Compiler**: `arm-none-eabi-gcc` (Arm GNU Toolchain).
- **Required**: `gcc`, `binutils`, `newlib`.
- **Usage**: Compiles `src_m3/main.c` and `src_m3/startup.c` into a `.bin` file.

### 2.2. RTL & FPGA Synthesis
- **OSS Toolchain**: [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (includes Yosys, nextpnr-gowin, and Apycula/gowin_pack).
- **Alternative**: [Gowin EDA](https://www.gowinsemi.com/en/design/software/) (Proprietary).
- **M3 IP**: Synthesis requires the `Gowin_EMPU_M3` primitive. In the OSS flow, this is provided by `src_gowin/gowin_empu_m3_stub.v`.

### 2.3. Utilities
- **Python 3**: Used for converting the compiled binary to a Gowin-compatible memory initialization file (`src_m3/bin2mi.py`).
- **Serial Terminal**: `PuTTY`, `minicom`, or `screen` (115200 baud).

## 3. GPIO Implementation (Status Quo)

The baseline implementation in `src_gowin/tt_gowin_top_m3.v` uses a **16-bit multiplexed GPIO interface** to overcome the physical pin limitations of the EMCU.

### 3.1. Technical Details
- **GPIO[7:0]**: 8-bit Bidirectional Data Bus
- **GPIO[10:8]**: 3-bit Address Select (0: `ui_in`, 1: `uio_in`, 2: `uo_out`, 3: `uio_out`, 4: `uio_oe`)
- **GPIO[11]**: `mac_clk` (Manual toggle)
- **GPIO[12]**: `mac_rst_n` (Active low)
- **GPIO[13]**: `mac_ena`
- **GPIO[14]**: `WEN` (Write Strobe)

### 3.2. Installation & Usage

**Synthesis**:
To enable GPIO mode, define `M3_MODE_GPIO` during synthesis:
```bash
yosys -p "read_verilog -sv -DM3_MODE_GPIO src/project.v src_gowin/tt_gowin_top_m3.v ...; synth_gowin -top tt_gowin_top_m3"
```

**Firmware (C)**:
```c
#define GPIO0_DATA (*(volatile uint32_t *)0x40010000)
#define GPIO0_DIR  (*(volatile uint32_t *)0x40010004)

void write_ui_in(uint8_t val) {
    GPIO0_DIR |= 0x00FF; // Bits 0-7 as output
    GPIO0_DATA = (0 << 8) | val; // Addr 0, Data val
    GPIO0_DATA |= (1 << 14);     // WEN high
    GPIO0_DATA &= ~(1 << 14);    // WEN low
}

void clock_tick() {
    GPIO0_DATA |= (1 << 11);     // clk high
    GPIO0_DATA &= ~(1 << 11);    // clk low
}
```

## 4. Hybrid Integration Mode (APB-Write / GPIO-Read)

The **Hybrid mode** serves as a bridge between full software control and full hardware automation.
- **Mechanism**: Accelerates the 32-cycle streaming phase by automating clock generation in hardware via an APB bridge for writes.
- **Simplification**: Uses the existing GPIO path for the low-frequency read phase (Cycles 37-40), simplifying the bridge design.
- **Benefit**: Significantly reduces CPU overhead during the data-intensive streaming phase without the complexity of a full bidirectional APB-to-MAC bridge.

## 5. APB Integration (Peripheral Mode)

The APB interface acts as a Slave between the M3's Peripheral Bus and the MAC unit, replacing manual GPIO toggling with hardware-assisted register access.

### 5.1. Block Diagram Concept
```text
[ Cortex-M3 ] <--- APB Bus ---> [ APB-to-MAC Bridge ] <---> [ MAC Unit ]
                                   (Register Map)            (ui, uo, uio)
                                   (State Machine)           (mac_clk gen)
```

### 5.2. APB Register Map
The bridge is mapped to a dedicated peripheral address space (e.g., `0x40020000`).

| Offset | Name | Access | Description |
|:---:|---|:---:|---|
| `0x00` | **DATA_IN** | W | Writes to `ui_in` (low byte) and `uio_in` (high byte). Triggers a `mac_clk` pulse. |
| `0x04` | **DATA_OUT** | R | Reads `uo_out` (low byte) and `uio_out` (high byte). |
| `0x08` | **CTRL** | RW | Bit 0: `ena`, Bit 1: `rst_n`, Bit 2: `auto_clk` enable. |
| `0x0C` | **STATUS** | R | Bit 0: Busy (Protocol in progress), Bit 1: Result Valid. |
| `0x10` | **CONFIG** | RW | Clock divider settings for `mac_clk` generation. |

### 5.3. Installation & Usage

**Synthesis**:
The APB mode is the **default** for the `tt_gowin_top_m3` top-level if no other mode is specified.
```bash
yosys -p "read_verilog -sv src/project.v src_gowin/tt_gowin_top_m3.v ...; synth_gowin -top tt_gowin_top_m3"
```

**Firmware (C)**:
```c
#define APB_MAC_BASE 0x40020000
#define MAC_DATA_IN  (*(volatile uint32_t *)(APB_MAC_BASE + 0x00))
#define MAC_DATA_OUT (*(volatile uint32_t *)(APB_MAC_BASE + 0x04))
#define MAC_CTRL     (*(volatile uint32_t *)(APB_MAC_BASE + 0x08))

void mac_init() {
    MAC_CTRL = 0x03; // ena=1, rst_n=1
}

void stream_element(uint8_t a, uint8_t b) {
    // Write ui_in (bits 7:0) and uio_in (bits 15:8)
    // Writing to DATA_IN automatically triggers one mac_clk pulse.
    MAC_DATA_IN = (b << 8) | a;
}
```

### 5.4. Automated Block Mode
To minimize software overhead, the bridge can implement an **Automated Block Mode** where a hardware sequencer manages the entire 41-cycle streaming protocol, triggered by a single control register bit.

## 6. AHB Integration (System Bus)

For maximum performance, the MAC unit can be integrated directly onto the **Advanced High-performance Bus (AHB)**, the primary system bus of the Cortex-M3. AHB allows for burst transfers and zero-wait-state accesses.

### 5.1. AHB_SLAVE (Peripheral Mode)

In this mode, the MAC unit functions as a passive peripheral on the system bus.

- **Operation**: An **AHB-to-MAC Bridge** module translates AHB protocol phases (`HSEL`, `HTRANS`, `HADDR`, `HWRITE`, `HWDATA`) into MAC control signals.
- **Pipeline Support**: AHB uses separate address and data phases. The bridge buffers the address for one cycle to correlate it with the data phase.
- **Wait-States**: The bridge uses the `HREADY` signal to pause the M3 if the MAC unit is busy with the sequential streaming protocol.
- **Advantages**: Zero-wait-state access (where possible), higher clock rates, and lower latency compared to APB.

![Protocol States Diagram](https://www.plantuml.com/plantuml/proxy?cache=no&src=https://raw.githubusercontent.com/chatelao/ttihp-fp8-mul/main/docs/diagrams/PROTOCOL_STATES.PUML)

#### 6.1.1. Installation & Usage

**Synthesis**:
To enable AHB Slave mode, define `M3_MODE_AHB` during synthesis:
```bash
yosys -p "read_verilog -sv -DM3_MODE_AHB src/project.v src_gowin/tt_gowin_top_m3.v ...; synth_gowin -top tt_gowin_top_m3"
```

**Firmware (C)**:
Accessing the MAC unit in AHB mode is identical to APB mode but uses the system bus for lower latency:
```c
#define AHB_MAC_BASE 0x40020000
#define MAC_DATA_IN  (*(volatile uint32_t *)(AHB_MAC_BASE + 0x00))
// Same register offsets as APB
```

### 6.2. AHB_MASTER (DMA / Accelerator Mode)

In this mode, the integration includes a hardware sequencer that acts as a Bus Master.

- **Autonomous Access**: The unit requests the bus and reads operands (e.g., weights from Flash/SRAM) and input data directly from memory without CPU intervention.
- **Accelerator Structure**:
  1. M3 configures start address and block size via control registers.
  2. MAC unit takes over the bus and streams data autonomously.
  3. Results are written back directly to the destination memory.
- **Interrupts**: An IRQ informs the M3 when the operation is complete.
- **Advantages**: Minimal CPU load and maximum throughput (utilizing AHB bursts). Ideal for large-scale calculations such as LLM inference.

#### 6.2.1. AHB DMA Register Map

| Offset | Name | Access | Description |
|:---:|---|:---:|---|
| `0x20` | **DMA_SRC** | RW | Source address in M3 SRAM (pointing to operand data). |
| `0x24` | **DMA_DST** | RW | Destination address in M3 SRAM (for results). |
| `0x2C` | **DMA_CTRL** | RW | Bit 0: Start DMA, Bit 1: Enable IRQ on completion. |
| `0x0C` | **STATUS** | RW | Bit 0: Busy, Bit 1: Done (Write 1 to clear). |

#### 6.2.2. Installation & Usage

**Synthesis**:
To enable AHB DMA mode, define `M3_MODE_AHB_DMA` during synthesis:
```bash
yosys -p "read_verilog -sv -DM3_MODE_AHB_DMA src/project.v src_gowin/tt_gowin_top_m3.v src_gowin/ahb2_mac_bridge.v ...; synth_gowin -top tt_gowin_top_m3"
```

**Firmware (C)**:
```c
#define AHB_DMA_BASE 0x40020000
#define DMA_SRC      (*(volatile uint32_t *)(AHB_DMA_BASE + 0x20))
#define DMA_DST      (*(volatile uint32_t *)(AHB_DMA_BASE + 0x24))
#define DMA_CTRL     (*(volatile uint32_t *)(AHB_DMA_BASE + 0x2C))
#define DMA_STATUS   (*(volatile uint32_t *)(AHB_DMA_BASE + 0x0C))

void run_dma_mac(void* src, void* dst) {
    DMA_SRC = (uint32_t)src;
    DMA_DST = (uint32_t)dst;
    DMA_CTRL = 0x01; // Start
    while (DMA_STATUS & 0x01); // Wait for busy bit to clear
}
```

## 7. Comparison of Integration Methods

| Feature | GPIO (Status Quo) | Hybrid (APB/GPIO) | APB (Peripheral) | AHB_SLAVE | AHB_MASTER (DMA) |
|:---:|:---:|:---:|:---:|:---:|:---:|
| **Bus Type** | Bit-Banging | Mixed | Peripheral Bus | System Bus | System Bus |
| **Throughput** | ~100 KB/s | ~1 MB/s | ~2 MB/s | ~10-20 MB/s | >50 MB/s |
| **CPU Load** | 100% | High | Medium | Low | Minimal |
| **Footprint** | ~150 Gates | ~350 Gates | ~500 Gates | ~800 Gates | ~2000 Gates |
| **Design Effort**| Minimal | Low | Medium | High | Very High |

## 8. Implementation Roadmap

1. **RTL Development**: Create `src_gowin/apb_mac_bridge.v` (or AHB equivalent).
2. **Integration**: Update `tt_gowin_top_m3.v` to instantiate the chosen bridge instead of direct GPIO mapping.
3. **CST Update**: Update `tangnano4k_m3.cst` if any physical pins change (though APB/AHB are internal).
4. **Firmware**: Update `main.c` to use memory-mapped pointers (e.g., `*(volatile uint32_t *)0x40020000`) instead of GPIO bit-toggling.
5. **Verification**: Run Cocotb tests with appropriate Bus Functional Models (BFM) to verify timing and protocol compliance.
