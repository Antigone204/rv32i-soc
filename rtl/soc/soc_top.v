`default_nettype none
// -----------------------------------------------------------------------------
// soc_top — RISC-V 最小系统级芯片顶层 (RV32I Minimal SoC Top)
//
// 架构：
//   - CPU 核心：RV32I 5 级流水线核 (core.v)；
//   - 指令总线：core.imem_* 直连片上 SRAM Port A (零等待状态取指)；
//   - 数据总线：core.dmem_* 经 wb_core_bridge 转换接入 Wishbone B4 互连；
//   - 存储器与外设映射：
//       * 0x0000_0000 ~ 0x0000_FFFF : 64KB 片上双端口 SRAM (wb_sram)
//       * 0x0200_0000 ~ 0x0200_FFFF : CLINT 定时器 (wb_clint)
//       * 0x1001_0000 ~ 0x1001_001F : UART 控制器 (wb_uart)
//   - 调试与追踪：导出精确提交接口 (wb_valid, wb_pc, ...) 与心跳/状态 LED。
// -----------------------------------------------------------------------------
module soc_top #(
    parameter integer CLK_HZ        = 50_000_000,
    parameter integer BAUD          = 115_200,
    parameter integer SRAM_WORDS    = 16384,      // 16K x 32bit = 64 KB
    parameter         MEM_INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- 外部物理串口 ----
    output wire        uart_txd,
    input  wire        uart_rxd,

    // ---- 板载调试 LED ----
    output wire [7:0]  led,

    // ---- 提交追踪接口 (DiffTest / 调试验证用) ----
    output wire        wb_valid,
    output wire        wb_we,
    output wire [31:0] wb_pc,
    output wire [4:0]  wb_rd,
    output wire [31:0] wb_wdata,

    // ---- 性能计数器 (基准测试/评测用) ----
    output wire [31:0] perf_cycle,
    output wire [31:0] perf_instret
);

    // =========================================================================
    // 1. CPU 核心总线连线声明
    // =========================================================================
    wire [31:0] imem_addr;
    /* verilator lint_off UNUSED */
    wire        imem_req;
    /* verilator lint_on  UNUSED */
    wire [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_byte_we;
    wire        dmem_req;
    wire [31:0] dmem_rdata;

    // 例化 CPU 核心
    core u_core (
        .clk         (clk),
        .rst_n       (rst_n),
        .imem_addr   (imem_addr),
        .imem_req    (imem_req),
        .imem_rdata  (imem_rdata),
        .dmem_addr   (dmem_addr),
        .dmem_wdata  (dmem_wdata),
        .dmem_byte_we(dmem_byte_we),
        .dmem_req    (dmem_req),
        .dmem_rdata  (dmem_rdata),
        .wb_valid    (wb_valid),
        .wb_we       (wb_we),
        .wb_pc       (wb_pc),
        .wb_rd       (wb_rd),
        .wb_wdata    (wb_wdata),
        .perf_cycle  (perf_cycle),
        .perf_instret(perf_instret)
    );

    // =========================================================================
    // 2. Wishbone 总线网络连线
    // =========================================================================
    // Master 总线 (来自 Bridge)
    wire        wbm_cyc;
    wire        wbm_stb;
    wire        wbm_we;
    wire [31:0] wbm_adr;
    wire [31:0] wbm_dat_w;
    wire [3:0]  wbm_sel;
    wire [31:0] wbm_dat_r;
    wire        wbm_ack;

    // Slave 0: SRAM
    wire        wbs0_cyc;
    wire        wbs0_stb;
    wire        wbs0_we;
    wire [31:0] wbs0_adr;
    wire [31:0] wbs0_dat_w;
    wire [3:0]  wbs0_sel;
    wire [31:0] wbs0_dat_r;
    wire        wbs0_ack;

    // Slave 1: UART
    wire        wbs1_cyc;
    wire        wbs1_stb;
    wire        wbs1_we;
    wire [31:0] wbs1_adr;
    wire [31:0] wbs1_dat_w;
    wire [3:0]  wbs1_sel;
    wire [31:0] wbs1_dat_r;
    wire        wbs1_ack;

    // Slave 2: CLINT
    wire        wbs2_cyc;
    wire        wbs2_stb;
    wire        wbs2_we;
    wire [31:0] wbs2_adr;
    wire [31:0] wbs2_dat_w;
    wire [3:0]  wbs2_sel;
    wire [31:0] wbs2_dat_r;
    wire        wbs2_ack;

    // =========================================================================
    // 3. 例化 Core-to-Wishbone 主机桥
    // =========================================================================
    wb_core_bridge u_bridge (
        .clk         (clk),
        .rst_n       (rst_n),
        .dmem_addr   (dmem_addr),
        .dmem_wdata  (dmem_wdata),
        .dmem_byte_we(dmem_byte_we),
        .dmem_req    (dmem_req),
        .dmem_rdata  (dmem_rdata),
        .wbm_cyc_o   (wbm_cyc),
        .wbm_stb_o   (wbm_stb),
        .wbm_we_o    (wbm_we),
        .wbm_adr_o   (wbm_adr),
        .wbm_dat_o   (wbm_dat_w),
        .wbm_sel_o   (wbm_sel),
        .wbm_dat_i   (wbm_dat_r),
        .wbm_ack_i   (wbm_ack)
    );

    // =========================================================================
    // 4. 例化 Wishbone 互连
    // =========================================================================
    wb_interconnect u_intercon (
        .clk       (clk),
        .rst_n     (rst_n),
        .wbm_cyc_i (wbm_cyc),
        .wbm_stb_i (wbm_stb),
        .wbm_we_i  (wbm_we),
        .wbm_adr_i (wbm_adr),
        .wbm_dat_i (wbm_dat_w),
        .wbm_sel_i (wbm_sel),
        .wbm_dat_o (wbm_dat_r),
        .wbm_ack_o (wbm_ack),

        // Slave 0: SRAM
        .wbs0_cyc_o(wbs0_cyc),
        .wbs0_stb_o(wbs0_stb),
        .wbs0_we_o (wbs0_we),
        .wbs0_adr_o(wbs0_adr),
        .wbs0_dat_o(wbs0_dat_w),
        .wbs0_sel_o(wbs0_sel),
        .wbs0_dat_i(wbs0_dat_r),
        .wbs0_ack_i(wbs0_ack),

        // Slave 1: UART
        .wbs1_cyc_o(wbs1_cyc),
        .wbs1_stb_o(wbs1_stb),
        .wbs1_we_o (wbs1_we),
        .wbs1_adr_o(wbs1_adr),
        .wbs1_dat_o(wbs1_dat_w),
        .wbs1_sel_o(wbs1_sel),
        .wbs1_dat_i(wbs1_dat_r),
        .wbs1_ack_i(wbs1_ack),

        // Slave 2: CLINT
        .wbs2_cyc_o(wbs2_cyc),
        .wbs2_stb_o(wbs2_stb),
        .wbs2_we_o (wbs2_we),
        .wbs2_adr_o(wbs2_adr),
        .wbs2_dat_o(wbs2_dat_w),
        .wbs2_sel_o(wbs2_sel),
        .wbs2_dat_i(wbs2_dat_r),
        .wbs2_ack_i(wbs2_ack)
    );

    // =========================================================================
    // 5. 例化片上双端口 SRAM
    // =========================================================================
    wb_sram #(
        .WORDS        (SRAM_WORDS),
        .MEM_INIT_FILE(MEM_INIT_FILE)
    ) u_sram (
        .clk       (clk),
        .rst_n     (rst_n),
        .imem_addr (imem_addr),
        .imem_rdata(imem_rdata),
        .wbs_cyc_i (wbs0_cyc),
        .wbs_stb_i (wbs0_stb),
        .wbs_we_i  (wbs0_we),
        .wbs_adr_i (wbs0_adr),
        .wbs_dat_i (wbs0_dat_w),
        .wbs_sel_i (wbs0_sel),
        .wbs_dat_o (wbs0_dat_r),
        .wbs_ack_o (wbs0_ack)
    );

    // =========================================================================
    // 6. 例化 Wishbone UART 控制器
    // =========================================================================
    wb_uart #(
        .CLK_HZ(CLK_HZ),
        .BAUD  (BAUD)
    ) u_uart (
        .clk      (clk),
        .rst_n    (rst_n),
        .wbs_cyc_i(wbs1_cyc),
        .wbs_stb_i(wbs1_stb),
        .wbs_we_i (wbs1_we),
        .wbs_adr_i(wbs1_adr),
        .wbs_sel_i(wbs1_sel),
        .wbs_dat_i(wbs1_dat_w),
        .wbs_dat_o(wbs1_dat_r),
        .wbs_ack_o(wbs1_ack),
        .uart_txd (uart_txd),
        .uart_rxd (uart_rxd)
    );

    // =========================================================================
    // 7. 例化 CLINT 定时器
    // =========================================================================
    /* verilator lint_off UNUSED */
    wire timer_irq;
    /* verilator lint_on  UNUSED */

    wb_clint u_clint (
        .clk      (clk),
        .rst_n    (rst_n),
        .wbs_cyc_i(wbs2_cyc),
        .wbs_stb_i(wbs2_stb),
        .wbs_we_i (wbs2_we),
        .wbs_adr_i(wbs2_adr),
        .wbs_sel_i(wbs2_sel),
        .wbs_dat_i(wbs2_dat_w),
        .wbs_dat_o(wbs2_dat_r),
        .wbs_ack_o(wbs2_ack),
        .timer_irq(timer_irq)
    );

    // =========================================================================
    // 8. 心跳与状态指示 LED
    // =========================================================================
    reg [24:0] heartbeat_cnt;
    always @(posedge clk) begin
        if (!rst_n) begin
            heartbeat_cnt <= 25'd0;
        end else begin
            heartbeat_cnt <= heartbeat_cnt + 25'd1;
        end
    end

    assign led[0]   = heartbeat_cnt[24]; // 约 1.5 Hz 闪烁证明系统主频正常
    assign led[1]   = wb_valid;          // 指令退休指示
    assign led[7:2] = wb_pc[7:2];        // PC 指针低位跳动指示程序流动

endmodule
`default_nettype wire
