// -----------------------------------------------------------------------------
// riscv_test.h — 适配无 CSR 基础 RV32I 处理器的精简测试头文件
//
// 专为无特权级、无 CSR 的 5 级流水线 RV32I Core 定制：
//   - 替代官方依赖 CSR (tohost/mstatus) 与 ecall 的陷阱机制
//   - 使用内存魔数地址 0x0000_1000 作为通信信箱 (Mailbox)
//   - TEST_PASS: 向 0x0000_1000 写入 1，随后进入自旋死循环
//   - TEST_FAIL: 向 0x0000_1000 写入失败用例编号 (gp)，随后进入自旋死循环
// -----------------------------------------------------------------------------

#ifndef _RISCV_TEST_H
#define _RISCV_TEST_H

#define RVTEST_RV32U
#define RVTEST_RV64U

#define TESTNUM gp

#define RVTEST_CODE_BEGIN               \
    .section .text;                     \
    .globl _start;                      \
    .align 4;                           \
_start:                                 \
    li  x1,  0;                         \
    li  x2,  0;                         \
    li  x3,  0;                         \
    li  x4,  0;                         \
    li  x5,  0;                         \
    li  x6,  0;                         \
    li  x7,  0;                         \
    li  x8,  0;                         \
    li  x9,  0;                         \
    li  x10, 0;                         \
    li  x11, 0;                         \
    li  x12, 0;                         \
    li  x13, 0;                         \
    li  x14, 0;                         \
    li  x15, 0;                         \
    li  x16, 0;                         \
    li  x17, 0;                         \
    li  x18, 0;                         \
    li  x19, 0;                         \
    li  x20, 0;                         \
    li  x21, 0;                         \
    li  x22, 0;                         \
    li  x23, 0;                         \
    li  x24, 0;                         \
    li  x25, 0;                         \
    li  x26, 0;                         \
    li  x27, 0;                         \
    li  x28, 0;                         \
    li  x29, 0;                         \
    li  x30, 0;                         \
    li  x31, 0;

#define RVTEST_CODE_END                 \
    1: j 1b;

#define RVTEST_PASS                     \
    li  t0, 0x00001000;                 \
    li  t1, 1;                          \
    sw  t1, 0(t0);                      \
    1: j 1b;

#define RVTEST_FAIL                     \
    li  t0, 0x00001000;                 \
    sw  gp, 0(t0);                      \
    1: j 1b;

#define RVTEST_DATA_BEGIN               \
    .section .data;                     \
    .align 4;

#define RVTEST_DATA_END                 \
    .align 4;

#define EXTRA_DATA
#define EXTRA_INIT

#endif // _RISCV_TEST_H
