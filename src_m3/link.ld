MEMORY
{
    FLASH (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
    SRAM (rwx)  : ORIGIN = 0x20000000, LENGTH = 16K
}

SECTIONS
{
    .text :
    {
        KEEP(*(.vectors))
        *(.text*)
        *(.rodata*)
        _etext = .;
    } > FLASH

    .data : AT (_etext)
    {
        _sdata = .;
        *(.data*)
        _edata = .;
    } > SRAM

    .bss :
    {
        _sbss = .;
        *(.bss*)
        *(COMMON)
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
