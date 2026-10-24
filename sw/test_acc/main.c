/* -----------------------------------------------------------------------------
 * main.c — 4 路并行 SIMD INT8 乘累加硬件加速器 (wb_mac_acc) 算子性能评测基准
 *
 * 评测场景：
 *   执行边缘 AI / 信号处理核心算子：全连接层 (FC) / 矩阵向量乘 (GEMV) + Bias + ReLU
 *   - 权重矩阵 W  : 16 x 64 INT8 (1024 字节)
 *   - 输入向量 X  : 64 x 1 INT8  (64 字节)
 *   - 偏置向量 B  : 16 x 1 INT32 (16 个 32 位有符号数)
 *   - 输出向量 Y  : 16 x 1 INT32 (经 ReLU 激活后非负输出)
 *   - 累计乘累加量: 16 x 64 = 1024 次 INT8 乘加运算 (1024 MACs)
 *
 * 对比三种实现路径的执行周期数 (Cycles) 与加速比：
 *   [1] 纯软件移位加基线 (模拟无 M 扩展纯 RV32I CPU 软乘法)
 *   [2] CPU 标量硬件乘法 (RV32IM 硬件 mul 指令逐元素相乘累加)
 *   [3] 硬件并行算子加速器 (wb_mac_acc, 4 路 SIMD 打包 + 偏置预置 + 写触发 + 硬件 ReLU)
 *
 * 校验规则：
 *   三者计算所得 16 维输出向量必须 100% 完全逐元素一致。
 *   校验通过向 SIM_CTRL (0xFFFFFFF0) 写入 1 触发 PASS；失败写 0xDEAD 并挂起。
 * -------------------------------------------------------------------------- */
#include <stdint.h>
#include "soc.h"
#include "uart.h"
#include "timer.h"
#include "str.h"

/* =========================================================================
 * 1. 硬件加速器 MMIO 寄存器映射 (基地址 0x2000_0000)
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

/* 4 字节对齐，便于 32 位打包访存 */
static int8_t  g_weights[M_ROWS][K_COLS] __attribute__((aligned(4)));
static int8_t  g_inputs[K_COLS]          __attribute__((aligned(4)));
static int32_t g_biases[M_ROWS];

static int32_t g_out_soft[M_ROWS];
static int32_t g_out_scalar[M_ROWS];
static int32_t g_out_acc[M_ROWS];

/* =========================================================================
 * 2. 测试数据集初始化 (生成正负混合覆盖 INT8 动态范围的数据)
 * ========================================================================= */
static void init_dataset(void) {
    for (int r = 0; r < M_ROWS; r++) {
        g_biases[r] = (r % 2 == 0) ? (r * 35 - 200) : (-r * 45 + 180);
        for (int c = 0; c < K_COLS; c++) {
            int val = ((r * 19 + c * 37 + 17) % 241) - 120; // 范围 [-120, 120]
            g_weights[r][c] = (int8_t)val;
        }
    }
    for (int c = 0; c < K_COLS; c++) {
        int val = ((c * 29 + 53) % 251) - 125;              // 范围 [-125, 125]
        g_inputs[c] = (int8_t)val;
    }
}

/* =========================================================================
 * 3. 实现 1：纯软件移位累加乘法器 (模拟无硬件 M 扩展 CPU)
 * ========================================================================= */
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
        g_out_soft[r] = (sum > 0) ? sum : 0; // 软件 ReLU 激活
    }
}

/* =========================================================================
 * 4. 实现 2：CPU 标量硬件乘法 (RV32IM mul 逐元素相乘)
 * ========================================================================= */
static void run_scalar_hw_mul(void) {
    for (int r = 0; r < M_ROWS; r++) {
        int32_t sum = g_biases[r];
        for (int c = 0; c < K_COLS; c++) {
            // GCC RV32IM 会直接发射 mul 指令
            sum += (int32_t)g_weights[r][c] * (int32_t)g_inputs[c];
        }
        g_out_scalar[r] = (sum > 0) ? sum : 0; // 软件 ReLU 激活
    }
}

/* =========================================================================
 * 5. 实现 3：硬件并行算子加速器 (wb_mac_acc MMIO 驱动)
 * ========================================================================= */
static void run_accelerator(void) {
    const uint32_t *x_packed = (const uint32_t *)(const void *)g_inputs;

    for (int r = 0; r < M_ROWS; r++) {
        const uint32_t *w_packed = (const uint32_t *)(const void *)g_weights[r];

        // 1. 偏置预置：1 条写指令直接注入初始 bias
        ACC_RESULT_REG = (uint32_t)g_biases[r];

        // 2. 4 路 SIMD 流式乘加：每批处理 4 个 INT8，仅需 2 条 MMIO 存储指令
        for (int k = 0; k < K_COLS / 4; k++) {
            ACC_OPA_REG      = w_packed[k];
            ACC_OPB_TRIG_REG = x_packed[k]; // 写即触发计算并累加！
        }

        // 3. 硬件零延迟 ReLU 读出：1 条读指令直接获取激活后结果
        g_out_acc[r] = (int32_t)ACC_RELU_REG;
    }
}

/* =========================================================================
 * 6. 主评测流程与结果打印
 * ========================================================================= */
int main(void) {
    uart_init();
    printf("\n============================================================\n");
    printf("   RISC-V Parallel Operator Accelerator Benchmark\n");
    printf("   Workload: GEMV/FC Layer 16x64 INT8 (1024 MACs + Bias + ReLU)\n");
    printf("============================================================\n");

    init_dataset();

    /* 1. 纯软件移位加法基线 */
    uint32_t t0 = get_time_lo();
    run_software_shiftadd();
    uint32_t t1 = get_time_lo();
    uint32_t cyc_soft = t1 - t0;

    /* 2. CPU 标量硬件乘法 */
    t0 = get_time_lo();
    run_scalar_hw_mul();
    t1 = get_time_lo();
    uint32_t cyc_scalar = t1 - t0;

    /* 3. 并行算子加速器 */
    t0 = get_time_lo();
    run_accelerator();
    t1 = get_time_lo();
    uint32_t cyc_acc = t1 - t0;

    /* 4. 输出一致性校验 */
    int mismatch = 0;
    for (int r = 0; r < M_ROWS; r++) {
        if (g_out_soft[r] != g_out_scalar[r] || g_out_scalar[r] != g_out_acc[r]) {
            printf("[ERROR] Mismatch at row %d: Soft=%d, Scalar=%d, Acc=%d\n",
                   r, g_out_soft[r], g_out_scalar[r], g_out_acc[r]);
            mismatch++;
        }
    }

    if (mismatch != 0) {
        printf(">>> ACCELERATOR VERIFICATION FAILED (%d mismatches) <<<\n", mismatch);
        SIM_CTRL_REG = 0xDEAD0000UL | (uint32_t)mismatch;
        return 1;
    }

    /* 5. 打印周期数与加速比 */
    printf("\n--- Performance Breakdown (1024 MACs) ---\n");
    printf("[1] Soft Shift-Add (RV32I) : %u cycles\n", cyc_soft);
    printf("[2] Scalar HW Mul  (RV32IM): %u cycles\n", cyc_scalar);
    printf("[3] SIMD INT8 Acc  (MMIO)  : %u cycles\n", cyc_acc);

    uint32_t speedup_scalar_vs_soft_x100 = (cyc_soft * 100U) / cyc_scalar;
    uint32_t speedup_acc_vs_scalar_x100  = (cyc_scalar * 100U) / cyc_acc;
    uint32_t speedup_acc_vs_soft_x100    = (cyc_soft * 100U) / cyc_acc;

    printf("\n--- Speedup Analysis ---\n");
    printf("CPU Scalar vs Soft Baseline : %u.%02u x\n",
           speedup_scalar_vs_soft_x100 / 100U, speedup_scalar_vs_soft_x100 % 100U);
    printf("SIMD Acc   vs CPU Scalar    : %u.%02u x\n",
           speedup_acc_vs_scalar_x100 / 100U, speedup_acc_vs_scalar_x100 % 100U);
    printf("SIMD Acc   vs Soft Baseline : %u.%02u x\n",
           speedup_acc_vs_soft_x100 / 100U, speedup_acc_vs_soft_x100 % 100U);

    printf("\n------------------------------------------------------------\n");
    printf(">>> ACCELERATOR VERIFICATION PASSED (100%% Output Matched) <<<\n");
    printf("------------------------------------------------------------\n");

    SIM_CTRL_REG = 1UL; // PASS 退出
    return 0;
}
