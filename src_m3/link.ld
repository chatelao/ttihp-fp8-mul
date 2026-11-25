MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    SRAM (rwx)  : ORIGIN = 0x20000000, LENGTH = 16K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.vectors))
        *(.text*)
        *(.rodata*)
        . = ALIGN(4);
        _etext = .;
    } > FLASH

    .data : AT (_etext)
    {
        . = ALIGN(4);
        _sdata = .;
        *(.data*)
        . = ALIGN(4);
        _edata = .;
    } > SRAM

    .bss :
    {
        . = ALIGN(4);
        _sbss = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _ebss = .;
    } > SRAM

    .stack :
    {
        . = ALIGN(8);
        _sstack = .;
        . = . + 0x800; /* 2KB stack */
        _estack = .;
    } > SRAM
}
