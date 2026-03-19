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

void uart_puthex8(uint8_t val) {
    uint8_t nibble = (val >> 4) & 0xF;
    uart_putc(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
    nibble = val & 0xF;
    uart_putc(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
}

void uart_puthex(uint32_t val) {
    uart_puts("0x");
    for(int i=28; i>=0; i-=4) {
        uint8_t nibble = (val >> i) & 0xF;
        uart_putc(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
    }
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

/**
 * Enhanced MAC Test Driver
 * @param meta_ui_base: ui_in[7:0] for Cycle 0 (excluding nbm_offset_a)
 * @param meta_uio_base: uio_in[7:0] for Cycle 0 (excluding nbm_offset_b)
 * @param nbm_offset_a/b: MX+ offsets (3 bits)
 * @param bm_index_a/b: MX+ Block Max indices (5 bits)
 */
uint32_t run_mac_test_ext(uint8_t meta_ui_base, uint8_t meta_uio_base,
                          uint8_t nbm_offset_a, uint8_t nbm_offset_b,
                          uint8_t scale_a, uint8_t format_a, uint8_t bm_index_a,
                          uint8_t scale_b, uint8_t format_b, uint8_t bm_index_b,
                          uint8_t element_a, uint8_t element_b) {
    uint32_t result = 0;
    uint8_t cycle0_ui = meta_ui_base | (nbm_offset_a & 0x07);
    uint8_t cycle0_uio = meta_uio_base | (nbm_offset_b & 0x07);

    // Reset Sequence
    GPIO0_DATA &= ~(1 << BIT_RST);
    clock_tick();
    clock_tick();
    GPIO0_DATA |= (1 << BIT_RST);
    GPIO0_DATA |= (1 << BIT_ENA);
    clock_tick();

    // Cycle 0: IDLE / Metadata
    GPIO0_DATA = (GPIO0_DATA & ~(0xFFFF << BIT_UI_IN)) | (cycle0_ui << BIT_UI_IN) | (cycle0_uio << BIT_UIO_IN);
    clock_tick();

    if (!(cycle0_ui & 0x80)) { // Standard Protocol
        // Cycle 1: Scale A, Format A, BM Index A
        uint8_t cycle1_uio = (bm_index_a << 3) | (format_a & 0x07);
        GPIO0_DATA = (GPIO0_DATA & ~(0xFFFF << BIT_UI_IN)) | (scale_a << BIT_UI_IN) | (cycle1_uio << BIT_UIO_IN);
        clock_tick();

        // Cycle 2: Scale B, Format B, BM Index B
        uint8_t cycle2_uio = (bm_index_b << 3) | (format_b & 0x07);
        GPIO0_DATA = (GPIO0_DATA & ~(0xFFFF << BIT_UI_IN)) | (scale_b << BIT_UI_IN) | (cycle2_uio << BIT_UIO_IN);
        clock_tick();
    }

    // Cycles 3-34: Stream elements
    // In Packed mode, we only stream 16 cycles, but the driver can send 32 without harm (FSM handles it)
    for (int i = 0; i < 32; i++) {
        GPIO0_DATA = (GPIO0_DATA & ~(0xFFFF << BIT_UI_IN)) | (element_a << BIT_UI_IN) | (element_b << BIT_UIO_IN);
        clock_tick();
    }

    // Flush
    GPIO0_DATA &= ~(0xFFFF << BIT_UI_IN);
    clock_tick();
    clock_tick();

    // Read Result
    for (int i = 0; i < 4; i++) {
        uint8_t byte = (GPIO0_DATA >> BIT_UO_OUT) & 0xFF;
        result = (result << 8) | byte;
        clock_tick();
    }

    return result;
}

int main() {
    UART0_BAUD = 174; // 20MHz / 115200
    UART0_CTRL = 0x03;
    GPIO0_DIR = 0x0007FFFF;

    uart_puts("\r\n--- OCP MXFP8 MAC M3 Testbench (v1.3.0) ---\r\n");
    uart_puts("Commands: [t] E4M3, [e] E5M2, [i] INT8, [y] INT8_SYM, [p] Packed, [m] MX+, [s] Short, [l] LNS, [v] Version\r\n");

    uint8_t current_lns_mode = 0;

    while (1) {
        char cmd = uart_getc();
        uint32_t res;
        uint8_t lns_bits = (current_lns_mode & 0x03) << 3;

        switch(cmd) {
            case 't':
                uart_puts("E4M3 Standard...\r\n");
                res = run_mac_test_ext(lns_bits, 0x00, 0, 0, 127, 0, 0, 127, 0, 0, 0x38, 0x38);
                uart_puts("Result: "); uart_puthex(res); uart_puts("\r\n");
                break;
            case 'e':
                uart_puts("E5M2 Standard...\r\n");
                res = run_mac_test_ext(lns_bits, 0x00, 0, 0, 127, 1, 0, 127, 1, 0, 0x3C, 0x3C);
                uart_puts("Result: "); uart_puthex(res); uart_puts("\r\n");
                break;
            case 'i':
                uart_puts("INT8 Standard...\r\n");
                res = run_mac_test_ext(lns_bits, 0x00, 0, 0, 127, 5, 0, 127, 5, 0, 0x01, 0x01);
                uart_puts("Result: "); uart_puthex(res); uart_puts("\r\n");
                break;
            case 'y':
                uart_puts("INT8 Symmetric...\r\n");
                res = run_mac_test_ext(lns_bits, 0x00, 0, 0, 127, 6, 0, 127, 6, 0, 0x01, 0x01);
                uart_puts("Result: "); uart_puthex(res); uart_puts("\r\n");
                break;
            case 'p':
                uart_puts("Packed E4M3 (Dual Lane)...\r\n");
                res = run_mac_test_ext(lns_bits, 0x40, 0, 0, 127, 0, 0, 127, 0, 0, 0x38, 0x38);
                uart_puts("Result: "); uart_puthex(res); uart_puts("\r\n");
                break;
            case 'm':
                uart_puts("MX+ Precision Research (E4M3, Offset=1, BM=Idx31)...\r\n");
                // MX+ Enable (uio_in[7]=0x80), Offset A/B = 1
                res = run_mac_test_ext(lns_bits, 0x80, 1, 1, 127, 0, 31, 127, 0, 31, 0x38, 0x38);
                uart_puts("Result: "); uart_puthex(res); uart_puts("\r\n");
                break;
            case 's':
                uart_puts("Short Protocol (Reuse Scales)...\r\n");
                res = run_mac_test_ext(0x80 | lns_bits, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0x38, 0x38);
                uart_puts("Result: "); uart_puthex(res); uart_puts("\r\n");
                break;
            case 'l':
                current_lns_mode = (current_lns_mode + 1) % 3;
                uart_puts("LNS Mode toggled to: ");
                uart_putc('0' + current_lns_mode);
                uart_puts("\r\n");
                break;
            case 'v':
                uart_puts("Firmware Version: 1.3.0-M3-MXFP8\r\n");
                break;
            default:
                uart_puts("Unknown CMD: "); uart_putc(cmd); uart_puts("\r\n");
                break;
        }
    }
    return 0;
}
