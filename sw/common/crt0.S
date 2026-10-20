// -----------------------------------------------------------------------------
// crt0.S — RV32I 最小 SoC 裸机 C 运行时启动汇编
//
// 流程：
//   1. 清零通用寄存器 x1 ~ x31（防止仿真未知态 'x 传播）；
//   2. 初始化全局指针 gp 与栈指针 sp (__stack_top = 0x0001_0000)；
//   3. 按字清零 .bss 段 ([__bss_start, __bss_end))；
//   4. 调用 C 语言入口 main()；
//   5. 将返回状态写入高地址仿真退出信箱 SIM_CTRL (0xFFFF_FFF0)：
//        - main() 返回 0   -> 写入 1 (PASS)
//        - main() 返回非 0 -> 写入 (ret | 0xDEAD0000) (FAIL，避免返回 1 与 PASS 冲突)
// -----------------------------------------------------------------------------

.section .text.init, "ax"
.globl _start
_start:
    // 1. 清零通用寄存器
    li x1,  0
    li x2,  0
    li x3,  0
    li x4,  0
    li x5,  0
    li x6,  0
    li x7,  0
    li x8,  0
    li x9,  0
    li x10, 0
    li x11, 0
    li x12, 0
    li x13, 0
    li x14, 0
    li x15, 0
    li x16, 0
    li x17, 0
    li x18, 0
    li x19, 0
    li x20, 0
    li x21, 0
    li x22, 0
    li x23, 0
    li x24, 0
    li x25, 0
    li x26, 0
    li x27, 0
    li x28, 0
    li x29, 0
    li x30, 0
    li x31, 0

    // 2. 初始化 gp 与 sp
.option push
.option norelax
    la gp, __global_pointer$
.option pop
    la sp, __stack_top

    // 3. 清零 .bss 段
    la a0, __bss_start
    la a1, __bss_end
1:
    bgeu a0, a1, 2f
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    1b
2:

    // 4. 调用 main(0, 0)
    li   a0, 0
    li   a1, 0
    call main

    // 5. 根据 main() 返回值上报 SIM_CTRL (0xFFFF_FFF0)
    li   t0, 0xFFFFFFF0
    bnez a0, .Lfail

    // main() == 0 -> PASS (写 1)
    li   t1, 1
    sw   t1, 0(t0)
    j    .Lhalt

.Lfail:
    // main() != 0 -> FAIL (附带 0xDEAD0000 前缀，确保绝不等于 1)
    li   t1, 0xDEAD0000
    slli a0, a0, 16
    srli a0, a0, 16
    or   t1, t1, a0
    sw   t1, 0(t0)

.Lhalt:
#ifdef FPGA_BOARD_LOOP
    // 板级友好设计：延时约 3 秒（约 20,000,000 次循环），跳回 _start 重新运行并再次打印
    li   t2, 20000000
.Ldelay:
    addi t2, t2, -1
    bnez t2, .Ldelay
    j    _start
#else
    j    .Lhalt
#endif
