/* -----------------------------------------------------------------------------
 * main.c — S1c 裸机 C 语言运行时环境综合验收测试程序
 *
 * 覆盖验收项：
 *   1. [AC-2] .bss 段自动清零与读写校验；
 *   2. [AC-2] .data 段已初始化全局变量初值与修改校验；
 *   3. [AC-2] 栈操作、递归调用与内存/字符串库 (memset/memcpy/strcmp/strlen)；
 *   4. [AC-3] 纯 RV32I 下基于 libgcc 的 32 位有符号/无符号软乘除法与取模；
 *   5. [AC-4] CLINT 64 位定时器防撕裂读取 get_time() 单调递增校验；
 *   6. [AC-5] 超过 8 字节 TX FIFO 深度的长字符串 printf 流控与格式化输出；
 *   7. [AC-6] main() 返回 0，由 crt0.S 写入 0xFFFF_FFF0 触发仿真 PASS。
 * -------------------------------------------------------------------------- */
#include <stdint.h>
#include "soc.h"
#include "uart.h"
#include "timer.h"
#include "str.h"

/* 1. 未初始化全局数组 (应放入 .bss 并由 crt0.S 清零) */
uint32_t g_bss_array[16];

/* 2. 已初始化全局变量 (位于 .data / .sdata) */
uint32_t g_data_magic  = 0xCAFEBABEU;
int32_t  g_data_signed = -42;

/* 递归计算斐波那契数列 (测试栈帧保存与恢复) */
static uint32_t fib(uint32_t n) {
    if (n <= 1U) return n;
    return fib(n - 1U) + fib(n - 2U);
}

int main(void) {
    uart_init();

    /* ---------------- Test 1: .bss 清零与读写校验 ---------------- */
    for (int i = 0; i < 16; i++) {
        if (g_bss_array[i] != 0U) {
            return 1; /* Error 1: .bss 未清零 */
        }
        g_bss_array[i] = (uint32_t)(i * 3 + 1);
    }
    if (g_bss_array[5] != 16U || g_bss_array[15] != 46U) {
        return 2; /* Error 2: .bss 读写异常 */
    }

    /* ---------------- Test 2: .data 初值与修改校验 ---------------- */
    if (g_data_magic != 0xCAFEBABEU || g_data_signed != -42) {
        return 3; /* Error 3: .data 初值不匹配 */
    }
    g_data_magic  ^= 0xFFFFFFFFU;
    g_data_signed += 142;
    if (g_data_magic != 0x35014541U || g_data_signed != 100) {
        return 4; /* Error 4: .data 修改不匹配 */
    }

    /* ---------------- Test 3: 递归栈调用与 str/mem 库校验 ---------------- */
    uint32_t f10 = fib(10U); /* 期待 55 */
    if (f10 != 55U) {
        return 5; /* Error 5: 递归函数栈错误 */
    }

    char buf_a[16];
    char buf_b[16];
    memset(buf_a, 0, sizeof(buf_a));
    strcpy(buf_a, "RV32I-SoC");
    memcpy(buf_b, buf_a, 10);
    if (strlen(buf_b) != 9U || strcmp(buf_a, buf_b) != 0) {
        return 6; /* Error 6: 字符串/内存库错误 */
    }

    /* ---------------- Test 4: libgcc 软乘除法与取模校验 ---------------- */
    volatile int32_t  sa = -1234;
    volatile int32_t  sb = 56;
    volatile int32_t  sc = -100000;
    volatile int32_t  sd = 37;
    volatile uint32_t ua = 0x12345678U;
    volatile uint32_t ub = 0x00000100U;

    int32_t  smul = sa * sb;        /* -69104 */
    int32_t  sdiv = sc / sd;        /* -2702  */
    int32_t  smod = sc % sd;        /* -26    */
    uint32_t udiv = ua / ub;        /* 0x00123456 */
    uint32_t umod = ua % ub;        /* 0x00000078 */

    if (smul != -69104 || sdiv != -2702 || smod != -26 ||
        udiv != 0x00123456U || umod != 0x78U) {
        return 7; /* Error 7: 软乘除法运算错误 */
    }

    /* ---------------- Test 5: CLINT 64-bit get_time() 校验 ---------------- */
    uint64_t t0 = get_time();
    delay_cycles(200U);
    uint64_t t1 = get_time();
    if (t1 <= t0 || (t1 - t0) < 200ULL) {
        return 8; /* Error 8: CLINT 计时器异常 */
    }
    uint32_t dt = (uint32_t)(t1 - t0);

    /* ---------------- Test 6: UART 长字符串流控与格式化输出 ---------------- */
    printf("[S1c] C Runtime OK! fib=%u mul=%d div=%d hex=0x%08x dt=%u\n",
           f10, smul, sdiv, udiv, dt);

    return 0;
}
