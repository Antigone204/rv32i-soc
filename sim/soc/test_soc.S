// -----------------------------------------------------------------------------
// test_soc.S — SoC 顶层硬件集成冒烟汇编程序
//
// 测试项目：
//   1. Wishbone SRAM 访问：向 0x0000_0800 写入 0x12345678 并读回校验；
//   2. Wishbone UART 发送：向 0x1001_0000 (TXDATA) 连续写入 "Hi!\n"；
//   3. Wishbone CLINT 定时器读取：读取 0x0200_BFF8 (mtime)，延迟后再次读取校验递增；
//   4. 最终状态上报：向 0x0000_1000 (Mailbox) 写入 1 表示 PASS。
// -----------------------------------------------------------------------------

.section .text
.globl _start

_start:
    // 清零寄存器
    li x1, 0
    li x2, 0
    li x3, 0

    // ---------------- 1. Wishbone SRAM 读写校验 ----------------
    li a0, 0x00000800       // SRAM 测试地址
    li a1, 0x12345678       // 测试数据
    sw a1, 0(a0)            // 经 Wishbone 写入 SRAM
    lw a2, 0(a0)            // 经 Wishbone 读回
    bne a1, a2, fail        // 校验失败跳转

    // ---------------- 2. Wishbone UART 字符发送 ----------------
    li t0, 0x10010000       // UART0 基地址

    // 发送 'H'
    li t1, 'H'
    sw t1, 0(t0)

    // 发送 'i'
    li t1, 'i'
    sw t1, 0(t0)

    // 发送 '!'
    li t1, '!'
    sw t1, 0(t0)

    // 发送 '\n'
    li t1, '\n'
    sw t1, 0(t0)

    // ---------------- 3. Wishbone CLINT 定时器读取校验 ----------------
    li t2, 0x02000000       // CLINT 基地址
    li t3, 0xBFF8
    add t2, t2, t3          // t2 = 0x0200_BFF8 (MTIME_LO)

    lw s1, 0(t2)            // 第一次读取 mtime

    // 延时循环消耗时间
    li t4, 50
delay_loop:
    addi t4, t4, -1
    bnez t4, delay_loop

    lw s2, 0(t2)            // 第二次读取 mtime
    bgeu s1, s2, fail       // s2 必须大于 s1，否则失败

    // ---------------- 4. 成功上报 Mailbox (0x0000_1000) ----------------
pass:
    li a0, 0x00001000
    li a1, 1                // 1 = PASS
    sw a1, 0(a0)
spin_pass:
    j spin_pass

fail:
    li a0, 0x00001000
    li a1, 0xDEADBEEF       // 失败标志
    sw a1, 0(a0)
spin_fail:
    j spin_fail
