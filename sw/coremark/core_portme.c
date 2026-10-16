/* -----------------------------------------------------------------------------
 * core_portme.c — EEMBC CoreMark 平台移植实现 (RV32I SoC 裸机环境)
 * -------------------------------------------------------------------------- */
#include "soc.h"
#include "uart.h"
#include "timer.h"
#include "coremark.h"
#include "core_portme.h"

/* Performance Run 标准种子设定 */
#if PERFORMANCE_RUN
volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
#endif
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

ee_u32 default_num_contexts = 1;

/* 计时器与性能统计变量 */
static uint64_t start_time_val = 0;
static uint64_t stop_time_val  = 0;
static uint64_t total_ticks    = 0;

static inline uint64_t read_mtime(void) {
    uint32_t hi, lo, hi2;
    do {
        hi  = CLINT_MTIME_HI_REG;
        lo  = CLINT_MTIME_LO_REG;
        hi2 = CLINT_MTIME_HI_REG;
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | (uint64_t)lo;
}

void start_time(void) {
    start_time_val = read_mtime();
}

void stop_time(void) {
    stop_time_val = read_mtime();
    total_ticks = stop_time_val - start_time_val;
}

uint64_t get_time(void) {
    return total_ticks;
}

secs_ret time_in_secs(CORE_TICKS ticks) {
    secs_ret retval = (secs_ret)(ticks / EE_TICKS_PER_SEC);
    if (retval < 10) {
        retval = 10;
    }
    return retval;
}

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc;
    (void)argv;
    uart_init();
    p->portable_id = 1;
}

void portable_fini(core_portable *p) {
    p->portable_id = 0;
    if (total_ticks > 0) {
        uint64_t score_x1000 = (uint64_t)ITERATIONS * 1000000000ULL / total_ticks;
        ee_printf("CoreMark/MHz : %u.%03u\n",
                  (uint32_t)(score_x1000 / 1000),
                  (uint32_t)(score_x1000 % 1000));
    }
}

void portable_free(void *p) {
    (void)p;
}
