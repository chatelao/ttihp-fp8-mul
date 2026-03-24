#include <stdint.h>

// Register Base Addresses
#define UART0_BASE 0x40000000
#define MAC_BASE   0x40020000

// UART Registers
#define UART0_DATA  (*(volatile uint32_t *)(UART0_BASE + 0x00))
#define UART0_STATE (*(volatile uint32_t *)(UART0_BASE + 0x04))
#define UART0_CTRL  (*(volatile uint32_t *)(UART0_BASE + 0x08))
#define UART0_BAUD  (*(volatile uint32_t *)(UART0_BASE + 0x0C))

// MAC / AHB DMA Registers
#define MAC_DATA_IN   (*(volatile uint32_t *)(MAC_BASE + 0x00))
#define MAC_DATA_OUT  (*(volatile uint32_t *)(MAC_BASE + 0x04))
#define MAC_CTRL      (*(volatile uint32_t *)(MAC_BASE + 0x08))
#define DMA_SRC_A     (*(volatile uint32_t *)(MAC_BASE + 0x20))
#define DMA_SRC_B     (*(volatile uint32_t *)(MAC_BASE + 0x24))
#define DMA_DST       (*(volatile uint32_t *)(MAC_BASE + 0x28))
#define DMA_LEN       (*(volatile uint32_t *)(MAC_BASE + 0x2C))
#define DMA_CTRL      (*(volatile uint32_t *)(MAC_BASE + 0x30))
#define DMA_STAT      (*(volatile uint32_t *)(MAC_BASE + 0x34))

// Memory Buffers (32 elements each, 8-bit stored in 32-bit words for simplicity in this demo)
// Note: In a real system, these would be packed 8-bit arrays.
uint8_t buffer_a[32] __attribute__((aligned(32)));
uint8_t buffer_b[32] __attribute__((aligned(32)));
uint32_t result_buffer[1] __attribute__((aligned(4)));

void uart_putc(char c) {
    while (UART0_STATE & 0x01);
    UART0_DATA = c;
}

void uart_puts(const char *s) {
    while (*s) uart_putc(*s++);
}

void uart_puthex(uint32_t val) {
    uart_puts("0x");
    for(int i=28; i>=0; i-=4) {
        uint8_t nibble = (val >> i) & 0xF;
        uart_putc(nibble < 10 ? '0' + nibble : 'A' + nibble - 10);
    }
}

int main() {
    UART0_BAUD = 174; // 20MHz / 115200
    UART0_CTRL = 0x03;

    uart_puts("\r\n--- OCP MXFP8 AHB2 DMA Test (v1.0.0) ---\r\n");

    // Initialize Buffers (1.0 x 1.0)
    for(int i=0; i<32; i++) {
        buffer_a[i] = 0x38; // 1.0 in E4M3
        buffer_b[i] = 0x38; // 1.0 in E4M3
    }
    result_buffer[0] = 0;

    uart_puts("Configuring DMA...\r\n");
    DMA_SRC_A = (uint32_t)buffer_a;
    DMA_SRC_B = (uint32_t)buffer_b;
    DMA_DST   = (uint32_t)result_buffer;
    DMA_LEN   = 1;

    uart_puts("Triggering DMA Transfer...\r\n");
    DMA_CTRL = 0x01; // Start bit

    // Poll for completion
    while (DMA_STAT & 0x01) {
        // Wait until Busy is cleared
    }

    if (DMA_STAT & 0x02) {
        uart_puts("DMA Complete!\r\n");
        uart_puts("Result: ");
        uart_puthex(result_buffer[0]);
        uart_puts("\r\n");

        // Expected for 32x 1.0*1.0 = 32.0 (0x00002000 in fixed-point)
        if (result_buffer[0] == 0x00002000) {
            uart_puts("SUCCESS: Result matches expectation.\r\n");
        } else {
            uart_puts("FAILURE: Unexpected result.\r\n");
        }
    } else {
        uart_puts("DMA Error or Timeout.\r\n");
    }

    while(1);
    return 0;
}
