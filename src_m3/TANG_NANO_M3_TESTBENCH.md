# Tang Nano 4K Cortex-M3 Testbench Guide

This guide describes how to use the on-chip **Cortex-M3 (EMPU)** of the Sipeed Tang Nano 4K to test the OCP MXFP8 Streaming MAC Unit. Using the internal M3 allows for high-speed protocol verification and complex CLI-based testing without external hardware controllers.

## 1. Overview

The Gowin GW1NSR-4C FPGA includes a hard-core Cortex-M3 processor (EMPU). By connecting the M3's GPIOs to the MAC unit's input and output ports within the FPGA fabric, you can drive the 41-cycle streaming protocol entirely from C code.

### Benefits
- **High Speed**: The M3 can toggle GPIOs much faster than an external MCU over long wires.
- **Self-Contained**: No need for a Raspberry Pi Pico or logic analyzer for basic verification.
- **Serial Feedback**: Results are printed directly to the Tang Nano 4K's UART interface.

---

## 2. Serial Communication Setup

The Cortex-M3 communicates with your PC via **UART0**. There are two ways to connect:

### A. On-board USB-to-UART Bridge
The Tang Nano 4K features an on-board bridge (BL616 or CH552) that routes the M3's UART signals to the USB-C connector.
- **Connection**: Connect a USB-C cable from the Tang Nano 4K to your PC.
- **Port**: It will appear as a standard COM port (Windows) or `/dev/ttyUSBx` (Linux).
- **Settings**: 115200 Baud, 8 Data bits, 1 Stop bit, No Parity.

### B. External FTDI / UART Adapter
If you prefer to use an external serial adapter (e.g., FT232R, CP2102), connect it to the physical pins mapped in the fabric.

| Tang Nano 4K Pin | Signal | External Adapter Pin |
|:---:|:---:|:---:|
| **18** | `uart_rx` | TXD |
| **19** | `uart_tx` | RXD |
| **GND** | Ground | GND |

*Note: Ensure your adapter is set to **3.3V logic levels**. Connecting a 5V adapter may damage the FPGA.*

---

## 3. Hardware Setup (Gowin EDA)

To use the M3, you must instantiate the **Gowin_EMPU_M3** IP core in your project.

### IP Configuration
1. **System**: Enable `AHB` and `APB` buses.
2. **Peripherals**:
   - Enable `UART0` (for CLI).
   - Enable `GPIO0` (at least 20 bits: 8 for `ui_in`, 8 for `uio_in`, and control signals).
3. **Memory**: Configure internal SRAM for instruction/data storage (typically 16KB+).

### Fabric Connections (Multiplexed 16-bit Interface)
Map the M3 signals (GPIO[15:0]) to the MAC Unit through the `tt_gowin_top_m3.v` wrapper:

| M3 GPIO Bit | Signal Name | Direction (M3) | Description |
|:---:|---|:---:|---|
| **[7:0]** | `DATA_BUS` | Bidirectional | Multiplexed data for `ui_in`, `uio_in`, and read-back |
| **8** | `mac_clk` | Output | MAC System Clock |
| **9** | `mac_rst_n` | Output | Reset (Active Low) |
| **10** | `mac_ena` | Output | Enable |
| **11** | `ui_latch` | Output | Pulse to latch `ui_in` from `DATA_BUS` |
| **12** | `uio_latch` | Output | Pulse to latch `uio_in` from `DATA_BUS` |
| **13** | `read_en` | Output | Enable Fabric to drive `DATA_BUS` |
| **[15:14]** | `read_sel` | Output | 0: `uo_out`, 1: `uio_out`, 2: `uio_oe`, 3: `ui_in` echo |

---

## 4. M3 Software CLI (C Implementation)

The following C program implements the 41-cycle MAC protocol and provides a comprehensive UART-based interface.

### Register Map (Gowin EMPU)
- **UART0**: `0x40000000`
- **GPIO0**: `0x40010000`

### `main.c` Reference
For the full source, refer to `main.c`. Below are the core driver and interactive loop details.

#### Interactive CLI Commands

| Command | Mode | Format / Operation | Expected Result (1.0 x 1.0 x 32) |
|:---:|:---:|---|---|
| `t` | Standard | **E4M3** | `0x00002000` (32.0) |
| `e` | Standard | **E5M2** | `0x00002000` (32.0) |
| `i` | Standard | **INT8** (1 x 1 x 32) | `0x00000020` (32) |
| `y` | Standard | **INT8_SYM** | `0x00000020` (32) |
| `p` | Packed | **Packed E4M3** (Dual Lane) | `0x00002000` (32.0) |
| `m` | MX+ | **MX+ Extension** (E4M3, Offset=1) | `0x00001000` (16.0) |
| `s` | Short | **Short Protocol** (Reuse Scales) | `0x00002000` (32.0) |
| `l` | Toggle | **LNS Mode** (0:Std, 1:LNS, 2:Hybrid) | Varies |
| `v` | Info | **Firmware Version** | `1.3.0-M3-MXFP8` |

---

## 5. Verification Workflow

Once the firmware is running, you can verify the design by sending commands through the serial terminal.

### Example: Verifying E4M3 Dot Product
1. Open your serial terminal (115200 baud).
2. Press `t`.
3. The M3 will drive the MAC unit with 32 elements of `1.0` (E4M3: `0x38`) and unit scales.
4. **Expected Output**:
   ```text
   E4M3 Standard...
   Result: 0x00002000
   ```
   *Explanation: `0x2000` is 8192 in fixed-point. $8192 / 256.0 = 32.0$.*

### Example: Verifying MX+ (High Precision)
1. Press `m`.
2. This mode uses a non-zero NBM Offset.
3. **Expected Output**:
   ```text
   MX+ Precision Research (E4M3, Offset=1, BM=Idx31)...
   Result: 0x00001000
   ```
   *Explanation: With Offset=1, the effective value is halved.*

---

## 6. Execution

### Step 1: Compilation
Use the **Arm GNU Toolchain** (`arm-none-eabi-gcc`) to compile the firmware. The project includes a `Makefile` in the current directory to simplify this process.

```bash
cd src_m3
make
```

This will produce `testbench.bin`, which is the raw machine code for the Cortex-M3.

### Step 2: Generate Memory Initialization File (.mi)
Gowin EDA's EMPU IP requires a specifically formatted `.mi` file to initialize the internal instruction memory. Use the provided Python utility to convert the binary:

```bash
python3 bin2mi.py testbench.bin testbench.mi
```

### Step 3: Bitstream Integration
1. Open your project in **Gowin EDA**.
2. Double-click the **Gowin_EMPU_M3** IP in the "Design" tab.
3. In the "Memory" configuration section, locate the **Instruction Memory** initialization path.
4. Point it to the `testbench.mi` file generated in the previous step.
5. Click **OK** and regenerate the IP.
6. Run **Synthesis** and **Place & Route** to produce the final `.fs` bitstream.

### Step 4: Flashing and Monitoring
1. Flash the generated `.fs` file to the Tang Nano 4K.
2. Connect a serial terminal (e.g., PuTTY or `screen`) to the Tang Nano 4K's serial port at **115200 baud**.
3. Press the Reset button (S1) to restart the M3 and observe the output.

---

## 7. Troubleshooting

- **No Serial Output**: Verify that `UART0` is mapped to the correct physical pins (Pin 18/19 are common on Tang Nano boards) and that the baud rate divider is correctly set for your system clock.
- **Wrong Result**: Ensure the `clock_tick()` timing allows the FPGA fabric to sample the signals correctly. If necessary, increase the delay in the loop.
- **GPIO Conflict**: Check that physical pins 30-44 (used in the standalone guide) are not being driven by both the M3 and external headers simultaneously.
