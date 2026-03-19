#include <stdint.h>

void reset_handler(void);
extern int main(void);

// Linker script symbols
extern uint32_t _etext;
extern uint32_t _sdata;
extern uint32_t _edata;
extern uint32_t _sbss;
extern uint32_t _ebss;

__attribute__((section(".vectors")))
const uint32_t vectors[] = {
    0x20004000, // Initial SP (End of 16KB SRAM)
    (uint32_t)reset_handler,
};

void reset_handler(void) {
    // 1. Initialize DATA section (copy from Flash to SRAM)
    uint32_t *src = &_etext;
    uint32_t *dst = &_sdata;
    while (dst < &_edata) {
        *dst++ = *src++;
    }

    // 2. Clear BSS section
    dst = &_sbss;
    while (dst < &_ebss) {
        *dst++ = 0;
    }

    // 3. Launch application
    main();
    while(1);
}
