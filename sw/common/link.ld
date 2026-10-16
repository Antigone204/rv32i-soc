/* -----------------------------------------------------------------------------
 * link.ld — RV32I SoC 64KB On-Chip SRAM 裸机链接脚本
 *
 * 内存区域：
 *   SRAM : 0x0000_0000 ~ 0x0000_FFFF (64 KB)
 *   栈顶 : 0x0001_0000 (__stack_top，向下生长，16 字节对齐)
 * -------------------------------------------------------------------------- */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    SRAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
    .text ORIGIN(SRAM) : ALIGN(4)
    {
        KEEP(*(.text.init))
        *(.text .text.*)
        . = ALIGN(4);
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        . = ALIGN(4);
    } > SRAM

    .data : ALIGN(4)
    {
        __data_start = .;
        *(.data .data.*)
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.sdata .sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > SRAM

    .bss (NOLOAD) : ALIGN(4)
    {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > SRAM

    _end = .;
    PROVIDE(__stack_top = ORIGIN(SRAM) + LENGTH(SRAM));
}
