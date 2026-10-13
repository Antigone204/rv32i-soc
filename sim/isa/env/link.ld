/* =============================================================================
 * link.ld — 裸机测试用链接脚本 (Bare-Metal RISC-V Test Linker Script)
 *
 * 地址排布：
 *   - 0x0000_0000: .text 代码段 (起始包含复位向量 _start)
 *   - 随后紧跟 .data (只读与可写数据)
 *   - 随后紧跟 .bss (未初始化数据)
 * ============================================================================= */

OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
    . = 0x00000000;

    .text : {
        *(.text.init)
        *(.text)
        *(.text.*)
    }

    . = ALIGN(4);
    .data : {
        *(.data)
        *(.data.*)
        *(.sdata)
        *(.sdata.*)
        *(.rodata)
        *(.rodata.*)
    }

    . = ALIGN(4);
    .bss : {
        *(.bss)
        *(.bss.*)
        *(.sbss)
        *(.sbss.*)
    }

    . = ALIGN(4);
    _end = .;
}
