#include <stdint.h>

void reset_handler(void);
void default_handler(void) { while(1); }
extern int main(void);

// Linker script symbols
extern uint32_t _etext;
extern uint32_t _sdata;
extern uint32_t _edata;
extern uint32_t _sbss;
extern uint32_t _ebss;

__attribute__((section(".vectors")))
const uint32_t vectors[16] = {
    0x20004000,               // 0: Initial SP (End of 16KB SRAM)
    (uint32_t)reset_handler,  // 1: Reset
    (uint32_t)default_handler,// 2: NMI
    (uint32_t)default_handler,// 3: HardFault
    (uint32_t)default_handler,// 4: MemManage
    (uint32_t)default_handler,// 5: BusFault
    (uint32_t)default_handler,// 6: UsageFault
    0, 0, 0, 0,               // 7-10: Reserved
    (uint32_t)default_handler,// 11: SVCall
    (uint32_t)default_handler,// 12: DebugMonitor
    0,                        // 13: Reserved
    (uint32_t)default_handler,// 14: PendSV
    (uint32_t)default_handler // 15: SysTick
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
