#include <stdint.h>

// Register Definitions for Gowin EMPU (Cortex-M3)
#define UART0_BASE 0x40000000
#define GPIO0_BASE 0x40010000

#define UART0_DATA  (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART0_STATE (*(volatile uint32_t *)(UART0_BASE + 0x04))
#define UART0_CTRL  (*(volatile uint32_t *)(UART0_BASE + 0x08))
#define UART0_BAUD  (*(volatile uint32_t *)(UART0_BASE + 0x0C))

#define GPIO0_DATA  (*(volatile uint32_t *)(GPIO0_BASE + 0x00))
#define GPIO0_DIR   (*(volatile uint32_t *)(GPIO0_BASE + 0x04))

// GPIO Bit Offsets (Fabric Mapping)
#define BIT_UI_IN   0    // GPIO[7:0]   -> ui_in[7:0]
#define BIT_UIO_IN  8    // GPIO[15:8]  -> uio_in[7:0]
#define BIT_CLK     16   // GPIO[16]    -> clk
#define BIT_RST     17   // GPIO[17]    -> rst_n (active low)
#define BIT_ENA     18   // GPIO[18]    -> ena
#define BIT_UO_OUT  19   // GPIO[26:19] <- uo_out[7:0] (Input to M3)

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

// Simple delay loop for clock stretching
void delay(int count) {
    for(volatile int i=0; i < count; i++);
}

void clock_tick() {
    delay(10);
    GPIO0_DATA |= (1 << BIT_CLK);
    delay(10);
    GPIO0_DATA &= ~(1 << BIT_CLK);
}

uint32_t run_mac_test(uint8_t format, uint8_t scale_a, uint8_t scale_b, uint8_t element) {
    uint32_t result = 0;

    // Reset Sequence (rst_n is active low)
    GPIO0_DATA &= ~(1 << BIT_RST); // Assert Reset
    clock_tick();
    clock_tick();
    GPIO0_DATA |= (1 << BIT_RST);  // De-assert Reset
    GPIO0_DATA |= (1 << BIT_ENA);  // Enable MAC
    clock_tick();

    // Cycle 0: IDLE / Metadata Capture
    // ui_in[7]: Short Protocol = 0
    // uio_in[7:0]: Rounding, Overflow, Packed, MX+
    GPIO0_DATA = (GPIO0_DATA & ~(0xFFFF << BIT_UI_IN)) | (0x00 << BIT_UI_IN) | (0x00 << BIT_UIO_IN);
    clock_tick();

    // Cycle 1: Scale A & Format A (Standard Protocol)
    GPIO0_DATA = (GPIO0_DATA & ~(0xFFFF << BIT_UI_IN)) | (scale_a << BIT_UI_IN) | (format << BIT_UIO_IN);
    clock_tick();

    // Cycle 2: Scale B & Format B (Standard Protocol)
    GPIO0_DATA = (GPIO0_DATA & ~(0xFFFF << BIT_UI_IN)) | (scale_b << BIT_UI_IN) | (format << BIT_UIO_IN);
    clock_tick();

    // Cycles 3-34: Stream 32 elements (Lanes 0 & 1)
    for (int i = 0; i < 32; i++) {
        GPIO0_DATA = (GPIO0_DATA & ~(0xFFFF << BIT_UI_IN)) | (element << BIT_UI_IN) | (element << BIT_UIO_IN);
        clock_tick();
    }

    // Cycles 35-36: Flush / Pipeline Drain
    GPIO0_DATA &= ~(0xFFFF << BIT_UI_IN);
    clock_tick();
    clock_tick();

    // Cycles 37-40: Read Result (uo_out is 32-bit serialized)
    for (int i = 0; i < 4; i++) {
        uint8_t byte = (GPIO0_DATA >> BIT_UO_OUT) & 0xFF;
        result = (result << 8) | byte;
        clock_tick();
    }

    return result;
}

int main() {
    // 1. UART Initialization (assuming 20MHz system clock for 115200 baud)
    // Divisor = Clock / Baud = 20,000,000 / 115200 ≈ 174
    UART0_BAUD = 174;
    UART0_CTRL = 0x03; // Enable TX and RX

    // 2. GPIO Direction
    // Bits 0-18: Output (ui_in, uio_in, clk, rst, ena)
    // Bits 19-26: Input (uo_out)
    GPIO0_DIR = 0x0007FFFF;

    uart_puts("\r\n--- OCP MXFP8 MAC M3 Testbench ---\r\n");
    uart_puts("Targets: Tang Nano 4K (GW1NSR-4C)\r\n");
    uart_puts("Commands: [t] Run Test, [v] Version, [i] Info\r\n");

    while (1) {
        char cmd = uart_getc();
        if (cmd == 't') {
            uart_puts("Executing E4M3 Test (1.0 * 1.0 sum)...\r\n");
            // E4M3 format=0, Scale=127 (bias), Element=0x38 (1.0)
            uint32_t res = run_mac_test(0x00, 127, 127, 0x38);

            // Manual hex to string since sprintf might be heavy for minimal SRAM
            uart_puts("Raw Result: 0x");
            for(int i=28; i>=0; i-=4) {
                uint8_t nibble = (res >> i) & 0xF;
                uart_putc(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
            }
            uart_puts("\r\n");
        } else if (cmd == 'v') {
            uart_puts("Firmware Version: 1.1.0-M3\r\n");
        } else if (cmd == 'i') {
            uart_puts("Mapped Registers:\r\n");
            uart_puts("  UART0: 0x40000000\r\n");
            uart_puts("  GPIO0: 0x40010000\r\n");
        }
    }
    return 0;
}
