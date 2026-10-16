#ifndef SOC_H
#define SOC_H

#include <stdint.h>

/* =========================================================================
 * SoC 物理内存映射 (对齐 docs/spec/soc.md)
 * ========================================================================= */
#define SRAM_BASE           0x00000000UL
#define SRAM_SIZE           (64UL * 1024UL)

#define CLINT_BASE          0x02000000UL
#define UART0_BASE          0x10010000UL
#define SIM_CTRL_ADDR       0xFFFFFFF0UL

#define REG32(addr)         (*(volatile uint32_t *)(uintptr_t)(addr))

/* =========================================================================
 * UART0 寄存器定义 (SiFive FE310 兼容布局)
 * ========================================================================= */
#define UART_TXDATA_REG     REG32(UART0_BASE + 0x00UL)
#define UART_RXDATA_REG     REG32(UART0_BASE + 0x04UL)
#define UART_TXCTRL_REG     REG32(UART0_BASE + 0x08UL)
#define UART_RXCTRL_REG     REG32(UART0_BASE + 0x0CUL)
#define UART_IE_REG         REG32(UART0_BASE + 0x10UL)
#define UART_IP_REG         REG32(UART0_BASE + 0x14UL)
#define UART_DIV_REG        REG32(UART0_BASE + 0x18UL)

#define UART_TXFULL_MASK    0x80000000UL
#define UART_RXEMPTY_MASK   0x80000000UL

/* =========================================================================
 * CLINT 定时器寄存器定义 (RISC-V 特权级规范标准偏移)
 * ========================================================================= */
#define CLINT_MSIP_REG          REG32(CLINT_BASE + 0x0000UL)
#define CLINT_MTIMECMP_LO_REG   REG32(CLINT_BASE + 0x4000UL)
#define CLINT_MTIMECMP_HI_REG   REG32(CLINT_BASE + 0x4004UL)
#define CLINT_MTIME_LO_REG      REG32(CLINT_BASE + 0xBFF8UL)
#define CLINT_MTIME_HI_REG      REG32(CLINT_BASE + 0xBFFCUL)

/* =========================================================================
 * 仿真控制信箱 (SIM_CTRL)
 * ========================================================================= */
#define SIM_CTRL_REG        REG32(SIM_CTRL_ADDR)

#endif /* SOC_H */
