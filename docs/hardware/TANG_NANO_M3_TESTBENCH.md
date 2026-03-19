# Tang Nano 4K Cortex-M3 Testbench Guide

This guide describes how to use the on-chip **Cortex-M3 (EMPU)** of the Sipeed Tang Nano 4K to test the OCP MXFP8 Streaming MAC Unit. Using the internal M3 allows for high-speed protocol verification and complex CLI-based testing without external hardware controllers.

## 1. Overview

The Gowin GW1NSR-4C FPGA includes a hard-core Cortex-M3 processor (EMPU). By connecting the M3's GPIOs to the MAC unit's input and output ports within the FPGA fabric, you can drive the 41-cycle streaming protocol entirely from C code.

### Benefits
- **High Speed**: The M3 can toggle GPIOs much faster than an external MCU over long wires.
- **Self-Contained**: No need for a Raspberry Pi Pico or logic analyzer for basic verification.
- **Serial Feedback**: Results are printed directly to the Tang Nano 4K's UART interface.

---

## 2. Hardware Setup (Gowin EDA)

To use the M3, you must instantiate the **Gowin_EMPU_M3** IP core in your project.

### IP Configuration
1. **System**: Enable `AHB` and `APB` buses.
2. **Peripherals**:
   - Enable `UART0` (for CLI).
   - Enable `GPIO0` (at least 20 bits: 8 for `ui_in`, 8 for `uio_in`, and control signals).
3. **Memory**: Configure internal SRAM for instruction/data storage (typically 16KB+).

### Fabric Connections
Map the M3 signals to the MAC Unit top-level (`tt_um_chatelao_fp8_multiplier`):

| M3 Signal | MAC Unit Signal | Description |
|-----------|-----------------|-------------|
| `GPIO[7:0]` | `ui_in[7:0]` | Data / Scale A |
| `GPIO[15:8]` | `uio_in[7:0]` | Data / Scale B |
| `GPIO[16]` | `clk` | System Clock (Driven by M3) |
| `GPIO[17]` | `rst_n` | Reset (Active Low) |
| `GPIO[18]` | `ena` | Enable |
| `uo_out[7:0]` | `GPIO[26:19]` | Result (Read by M3) |

---

## 3. M3 Software CLI (C Implementation)

The following C program implements the 41-cycle MAC protocol and provides a simple UART-based interface.

### Register Map (Standard Gowin EMPU)
- **UART0**: `0x40000000`
- **GPIO0**: `0x40010000`

### `main.c`

```c
#include <stdint.h>
#include <stdio.h>

// Register Definitions
#define UART0_BASE 0x40000000
#define GPIO0_BASE 0x40010000

#define UART0_DATA  (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART0_STATE (*(volatile uint32_t *)(UART0_BASE + 0x04))
#define UART0_CTRL  (*(volatile uint32_t *)(UART0_BASE + 0x08))
#define UART0_BAUD  (*(volatile uint32_t *)(UART0_BASE + 0x0C))

#define GPIO0_DATA  (*(volatile uint32_t *)(GPIO0_BASE + 0x00))
#define GPIO0_DIR   (*(volatile uint32_t *)(GPIO0_BASE + 0x04))

// GPIO Bit Offsets
#define BIT_UI_IN   0    // GPIO[7:0]
#define BIT_UIO_IN  8    // GPIO[15:8]
#define BIT_CLK     16   // GPIO[16]
#define BIT_RST     17   // GPIO[17]
#define BIT_ENA     18   // GPIO[18]
#define BIT_UO_OUT  19   // GPIO[26:19] (Input to M3)

void uart_putc(char c) {
    while (UART0_STATE & 0x01); // Wait if TX full
    UART0_DATA = c;
}

void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

char uart_getc() {
    while (!(UART0_STATE & 0x02)); // Wait if RX empty
    return UART0_DATA;
}

void clock_tick() {
    GPIO0_DATA |= (1 << BIT_CLK);
    for(volatile int i=0; i<10; i++); // Small delay
    GPIO0_DATA &= ~(1 << BIT_CLK);
    for(volatile int i=0; i<10; i++);
}

uint32_t run_mac_test(uint8_t format, uint8_t scale_a, uint8_t scale_b, uint8_t element) {
    uint32_t result = 0;

    // Reset Sequence
    GPIO0_DATA = (1 << BIT_RST); // Keep reset high (active low)
    GPIO0_DATA &= ~(1 << BIT_RST); // Pulse reset
    clock_tick();
    GPIO0_DATA |= (1 << BIT_RST);
    GPIO0_DATA |= (1 << BIT_ENA);

    // Cycle 0: IDLE
    GPIO0_DATA &= ~(0xFFFF << BIT_UI_IN); // Clear ui/uio
    clock_tick();

    // Cycle 1: Scale A & Format A
    GPIO0_DATA &= ~(0xFFFF << BIT_UI_IN);
    GPIO0_DATA |= (scale_a << BIT_UI_IN) | (format << BIT_UIO_IN);
    clock_tick();

    // Cycle 2: Scale B & Format B
    GPIO0_DATA &= ~(0xFFFF << BIT_UI_IN);
    GPIO0_DATA |= (scale_b << BIT_UI_IN) | (format << BIT_UIO_IN);
    clock_tick();

    // Cycles 3-34: Stream 32 elements
    GPIO0_DATA &= ~(0xFFFF << BIT_UI_IN);
    GPIO0_DATA |= (element << BIT_UI_IN) | (element << BIT_UIO_IN);
    for (int i = 0; i < 32; i++) clock_tick();

    // Cycles 35-36: Flush
    GPIO0_DATA &= ~(0xFFFF << BIT_UI_IN);
    clock_tick();
    clock_tick();

    // Cycles 37-40: Read Result
    for (int i = 0; i < 4; i++) {
        uint8_t byte = (GPIO0_DATA >> BIT_UO_OUT) & 0xFF;
        result = (result << 8) | byte;
        clock_tick();
    }

    return result;
}

int main() {
    // 1. UART Initialization (assuming 50MHz system clock for 115200 baud)
    // Divisor = Clock / Baud = 50,000,000 / 115200 ≈ 434
    UART0_BAUD = 434;
    UART0_CTRL = 0x03; // Enable TX and RX

    // 2. GPIO Direction
    // Bits 0-18: Output, Bits 19-26: Input
    GPIO0_DIR = 0x0007FFFF;

    uart_puts("\n--- MAC Unit M3 Interactive CLI ---\n");
    uart_puts("Press 't' to run standard test, or 'v' for version.\n");

    while (1) {
        char cmd = uart_getc();
        if (cmd == 't') {
            uart_puts("Running Test (E4M3, 1.0 * 1.0)...\n");
            uint32_t res = run_mac_test(0x00, 127, 127, 0x38);

            char buf[64];
            sprintf(buf, "Result: 0x%08X (Decimal: %u.%02u)\n",
                    (unsigned int)res,
                    (unsigned int)(res >> 8),
                    (unsigned int)((res & 0xFF) * 100 / 256));
            uart_puts(buf);
        } else if (cmd == 'v') {
            uart_puts("OCP MXFP8 MAC Unit v1.0 (Tang Nano 4K M3)\n");
        } else {
            uart_puts("Unknown command. Use 't' or 'v'.\n");
        }
    }
    return 0;
}
```

---

## 4. Execution

### Step 1: Compilation
Use the **Arm GNU Toolchain** (`arm-none-eabi-gcc`) to compile the source. Ensure you have the correct linker script (`.ld`) for the GW1NSR-4C memory map.

```bash
arm-none-eabi-gcc -mcpu=cortex-m3 -mthumb -T link.ld main.c -o testbench.elf
arm-none-eabi-objcopy -O binary testbench.elf testbench.bin
```

### Step 2: Bitstream Integration
In Gowin EDA, point the EMPU IP "Instruction Memory" path to your `testbench.bin` file. Re-run Synthesis and PNR.

### Step 3: Flashing and Monitoring
1. Flash the generated `.fs` file to the Tang Nano 4K.
2. Connect a serial terminal (e.g., PuTTY or `screen`) to the Tang Nano 4K's serial port at **115200 baud**.
3. Press the Reset button (S1) to restart the M3 and observe the output.

---

## 5. Troubleshooting

- **No Serial Output**: Verify that `UART0` is mapped to the correct physical pins (Pin 18/19 are common on Tang Nano boards) and that the baud rate divider is correctly set for your system clock.
- **Wrong Result**: Ensure the `clock_tick()` timing allows the FPGA fabric to sample the signals correctly. If necessary, increase the delay in the loop.
- **GPIO Conflict**: Check that physical pins 30-44 (used in the standalone guide) are not being driven by both the M3 and external headers simultaneously.
