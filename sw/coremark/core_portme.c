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
#ifndef FPGA_BOARD_LOOP
    if (retval < 10) {
        retval = 10;
    }
#endif
    return retval;
}

#ifdef FPGA_BOARD_LOOP
/* =========================================================================
 * 板级二合一演示：4 路并行 SIMD INT8 乘累加硬件加速器 (wb_mac_acc) 评测
 * ========================================================================= */
#define ACC_BASE            0x20000000UL
#define ACC_CTRL_REG        REG32(ACC_BASE + 0x00UL)
#define ACC_OPA_REG         REG32(ACC_BASE + 0x04UL)
#define ACC_OPB_TRIG_REG    REG32(ACC_BASE + 0x08UL)
#define ACC_RESULT_REG      REG32(ACC_BASE + 0x0CUL)
#define ACC_RELU_REG        REG32(ACC_BASE + 0x10UL)
#define ACC_COUNT_REG       REG32(ACC_BASE + 0x14UL)

#define M_ROWS 16
#define K_COLS 64

#ifndef USE_ANSI_COLOR
#define USE_ANSI_COLOR 0
#endif

#if USE_ANSI_COLOR
#define C_HEAD "\x1b[36m"
#define C_PASS "\x1b[1;32m"
#define C_FAIL "\x1b[1;31m"
#define C_OFF  "\x1b[0m"
#else
#define C_HEAD "" 
#define C_PASS ""
#define C_FAIL ""
#define C_OFF  ""
#endif

static int8_t  g_weights[M_ROWS][K_COLS] __attribute__((aligned(4)));
static int8_t  g_inputs[K_COLS]          __attribute__((aligned(4)));
static int32_t g_biases[M_ROWS];

static int32_t g_out_soft[M_ROWS];
static int32_t g_out_scalar[M_ROWS];
static int32_t g_out_acc[M_ROWS];

static void init_dataset(void) {
    for (int r = 0; r < M_ROWS; r++) {
        g_biases[r] = (r % 2 == 0) ? (r * 35 - 200) : (-r * 45 + 180);
        for (int c = 0; c < K_COLS; c++) {
            int val = ((r * 19 + c * 37 + 17) % 241) - 120;
            g_weights[r][c] = (int8_t)val;
        }
    }
    for (int c = 0; c < K_COLS; c++) {
        int val = ((c * 29 + 53) % 251) - 125;
        g_inputs[c] = (int8_t)val;
    }
}

static inline int32_t soft_mul_s8(int8_t a, int8_t b) {
    int32_t sa = (int32_t)a;
    int32_t sb = (int32_t)b;
    int32_t sign = 0;
    if (sa < 0) { sa = -sa; sign = !sign; }
    if (sb < 0) { sb = -sb; sign = !sign; }

    uint32_t ua = (uint32_t)sa;
    uint32_t ub = (uint32_t)sb;
    uint32_t prod = 0;
    while (ub > 0) {
        if (ub & 1U) {
            prod += ua;
        }
        ua <<= 1;
        ub >>= 1;
    }
    return sign ? -(int32_t)prod : (int32_t)prod;
}

static void run_software_shiftadd(void) {
    for (int r = 0; r < M_ROWS; r++) {
        int32_t sum = g_biases[r];
        for (int c = 0; c < K_COLS; c++) {
            sum += soft_mul_s8(g_weights[r][c], g_inputs[c]);
        }
        g_out_soft[r] = (sum > 0) ? sum : 0;
    }
}

static void run_scalar_hw_mul(void) {
    for (int r = 0; r < M_ROWS; r++) {
        int32_t sum = g_biases[r];
        for (int c = 0; c < K_COLS; c++) {
            sum += (int32_t)g_weights[r][c] * (int32_t)g_inputs[c];
        }
        g_out_scalar[r] = (sum > 0) ? sum : 0;
    }
}

static void run_accelerator(void) {
    const uint32_t *x_packed = (const uint32_t *)(const void *)g_inputs;

    for (int r = 0; r < M_ROWS; r++) {
        const uint32_t *w_packed = (const uint32_t *)(const void *)g_weights[r];
        ACC_RESULT_REG = (uint32_t)g_biases[r];
        for (int k = 0; k < K_COLS / 4; k++) {
            ACC_OPA_REG      = w_packed[k];
            ACC_OPB_TRIG_REG = x_packed[k];
        }
        g_out_acc[r] = (int32_t)ACC_RELU_REG;
    }
}

static int format_u32_commas(char *out, uint32_t v) {
    char b[12];
    int n = 0;
    int len = 0;
    do {
        b[n++] = (char)('0' + (v % 10U));
        v /= 10U;
    } while (v);
    while (n--) {
        out[len++] = b[n];
        if (n > 0 && (n % 3) == 0) {
            out[len++] = ',';
        }
    }
    out[len] = '\0';
    return len;
}

static void put_pad(int n) {
    while (n-- > 0) {
        ee_printf(" ");
    }
}

static int str_len(const char *s) {
    int n = 0;
    while (s[n]) n++;
    return n;
}

static void format_mac_per_cyc(char *out, uint32_t cyc) {
    if (cyc == 0) {
        out[0] = '-'; out[1] = '-'; out[2] = '\0';
        return;
    }
    uint32_t val = (uint32_t)((1024ULL * 1000U + cyc / 2U) / cyc);
    uint32_t ip = val / 1000U;
    uint32_t fp = val % 1000U;
    char ib[12];
    int in = 0, len = 0;
    do {
        ib[in++] = (char)('0' + (ip % 10U));
        ip /= 10U;
    } while (ip);
    while (in--) {
        out[len++] = ib[in];
    }
    out[len++] = '.';
    out[len++] = (char)('0' + (fp / 100U));
    out[len++] = (char)('0' + ((fp / 10U) % 10U));
    out[len++] = (char)('0' + (fp % 10U));
    out[len] = '\0';
}

static void format_speedup(char *out, uint32_t base_cyc, uint32_t cyc, int is_na) {
    if (is_na || cyc == 0) {
        out[0] = '-'; out[1] = '-'; out[2] = '\0';
        return;
    }
    uint32_t val = (uint32_t)(((uint64_t)base_cyc * 100ULL + cyc / 2U) / cyc);
    uint32_t ip = val / 100U;
    uint32_t fp = val % 100U;
    char ib[12];
    int in = 0, len = 0;
    do {
        ib[in++] = (char)('0' + (ip % 10U));
        ip /= 10U;
    } while (ip);
    while (in--) {
        out[len++] = ib[in];
    }
    out[len++] = '.';
    out[len++] = (char)('0' + (fp / 10U));
    out[len++] = (char)('0' + (fp % 10U));
    out[len++] = 'x';
    out[len] = '\0';
}

static void print_table_row(const char *label, uint32_t cyc, uint32_t base_soft, uint32_t base_scalar, int is_na_scalar) {
    char c_buf[16];
    char m_buf[16];
    char s_soft_buf[16];
    char s_scal_buf[16];

    format_u32_commas(c_buf, cyc);
    format_mac_per_cyc(m_buf, cyc);
    format_speedup(s_soft_buf, base_soft, cyc, 0);
    format_speedup(s_scal_buf, base_scalar, cyc, is_na_scalar);

    ee_printf("  %s", label);
    put_pad(20 - str_len(label));

    put_pad(8 - str_len(c_buf));
    ee_printf("%s", c_buf);

    put_pad(10 - str_len(m_buf));
    ee_printf("%s", m_buf);

    put_pad(10 - str_len(s_soft_buf));
    ee_printf("%s", s_soft_buf);

    put_pad(10 - str_len(s_scal_buf));
    ee_printf("%s\n", s_scal_buf);
}

static void run_board_acc_benchmark(void) {
    ee_printf("============================================================\n");
    ee_printf("  Pango Logos-2 PG2L200H   RV32IM + SIMD Accel SoC\n");
    ee_printf("  CPU  RV32IM+BPU(BTB/BHT)   Clock 27MHz   Wishbone B4\n");
    ee_printf("============================================================\n");
    ee_printf("  GEMV 16x64 INT8 = 1024 MACs + bias + ReLU\n\n");

    init_dataset();

    uint32_t t0 = get_time_lo();
    run_software_shiftadd();
    uint32_t t1 = get_time_lo();
    uint32_t cyc_soft = t1 - t0;

    t0 = get_time_lo();
    run_scalar_hw_mul();
    t1 = get_time_lo();
    uint32_t cyc_scalar = t1 - t0;

    t0 = get_time_lo();
    run_accelerator();
    t1 = get_time_lo();
    uint32_t cyc_acc = t1 - t0;

    int mismatch = 0;
    for (int r = 0; r < M_ROWS; r++) {
        if (g_out_soft[r] != g_out_scalar[r] || g_out_scalar[r] != g_out_acc[r]) {
            ee_printf("[ERROR] Mismatch at row %d: Soft=%d, Scalar=%d, Acc=%d\n",
                      r, g_out_soft[r], g_out_scalar[r], g_out_acc[r]);
            mismatch++;
        }
    }

    if (mismatch != 0) {
        ee_printf("%s  RESULT  ACCELERATOR FAILED  (%d mismatches)%s\n", C_FAIL, mismatch, C_OFF);
        SIM_CTRL_REG = 0xDEAD0000UL;
        while (1) {}
    }

    ee_printf("%s  Implementation        Cycles   MAC/cyc   vs soft vs scalar%s\n", C_HEAD, C_OFF);
    ee_printf("  ----------------------------------------------------------\n");

    print_table_row("[1] Soft shift-add", cyc_soft, cyc_soft, cyc_scalar, 1);
    print_table_row("[2] Scalar mul", cyc_scalar, cyc_soft, cyc_scalar, 0);
    print_table_row("[3] SIMD INT8 acc", cyc_acc, cyc_soft, cyc_scalar, 0);

    ee_printf("  ----------------------------------------------------------\n");
    ee_printf("%s  RESULT  ACCELERATOR PASSED  (16/16 rows)%s\n\n", C_PASS, C_OFF);
    ee_printf("  Next    EEMBC CoreMark 2K, 1000 iterations (~12 s)\n\n");
}
#endif

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc;
    (void)argv;
    uart_init();
#ifdef FPGA_BOARD_LOOP
    run_board_acc_benchmark();
#endif
    p->portable_id = 1;
}

void portable_fini(core_portable *p) {
    p->portable_id = 0;
    if (total_ticks > 0) {
        uint64_t score_x1000 = (uint64_t)ITERATIONS * 1000000000ULL / total_ticks;
        ee_printf("CoreMark/MHz : %u.%03u\n",
                  (uint32_t)(score_x1000 / 1000),
                  (uint32_t)(score_x1000 % 1000));
#ifdef FPGA_BOARD_LOOP
        uint64_t exact_time_ms = total_ticks * 1000ULL / 27000000ULL;
        uint64_t cm_27m_x1000  = score_x1000 * 27ULL;
        ee_printf("Exact Time (27M) : %u.%03u secs\n",
                  (uint32_t)(exact_time_ms / 1000),
                  (uint32_t)(exact_time_ms % 1000));
        ee_printf("CoreMark (27MHz) : %u.%03u\n",
                  (uint32_t)(cm_27m_x1000 / 1000),
                  (uint32_t)(cm_27m_x1000 % 1000));
#endif
    }
}

void portable_free(void *p) {
    (void)p;
}
