`default_nettype none
// -----------------------------------------------------------------------------
// fpga_top — 盘古 200K-MINI (PG2L200H-6FBB676) SoC 板级综合顶层
//
// 功能：
//   - 将 RISC-V SoC (soc_top) 适配到紫光同创 Logos-2 核心板；
//   - 晶振频率：27 MHz (sys_clk, 引脚 D18)；
//   - 板载复位与按键：C22 (rst_n), C23/B22/A22/B20 (key[3:0])；
//   - 板载指示灯：A20/C18/C19/E18/A17/A18/C17/B17 (led[7:0])；
//   - 串口引脚：C24 (uart_txd), B24 (uart_rxd)；
//   - 上电复位与按键重跑：
//       * 16 位计数器实现自动上电复位 (~2.4ms @ 27MHz)；
//       * 双级同步打拍采样外部按键，检测 rst_n 下降沿或 key 变换，
//         产生 256 拍软复位脉冲重跑 CPU，防止按键空闲极性不一致造成死锁；
//   - 支持 BRAM 固件初始化镜像综合 (firmware_words.hex)。
// -----------------------------------------------------------------------------
module fpga_top #(
    parameter integer CLK_HZ        = 27_000_000,
    parameter integer BAUD          = 115_200,
    parameter integer SRAM_WORDS    = 16384,
    parameter         MEM_INIT_FILE = "firmware_words.hex"
) (
    input  wire       sys_clk,   // D18: 27 MHz
    input  wire       rst_n,     // C22: USER_BUTTON0
    input  wire [3:0] key,       // C23, B22, A22, B20
    output wire [7:0] led,       // A20, C18, C19, E18, A17, A18, C17, B17
    output wire       uart_txd,  // C24
    input  wire       uart_rxd   // B24
);

    // =========================================================================
    // 1. 上电自动复位逻辑 (Power-on Reset)
    // =========================================================================
    // FPGA 配置完成后寄存器初始化为 0，计数 65536 拍 (~2.4ms @ 27MHz) 后撤除复位
    /* verilator lint_off PROCASSINIT */
    reg [15:0] por_cnt = 16'd0;
    /* verilator lint_on  PROCASSINIT */
    wire por_rst_n = &por_cnt;

    always @(posedge sys_clk) begin
        if (!por_rst_n) begin
            por_cnt <= por_cnt + 16'd1;
        end
    end

    // =========================================================================
    // 2. 按键同步与边沿触发软复位 (Soft Reset Generator)
    // =========================================================================
    reg [4:0] btn_sync_0;
    reg [4:0] btn_sync_1;
    reg [4:0] btn_sync_2;

    always @(posedge sys_clk) begin
        btn_sync_0 <= {rst_n, key};
        btn_sync_1 <= btn_sync_0;
        btn_sync_2 <= btn_sync_1;
    end

    // 检测 rst_n 下降沿 (按键按下) 或 key 状态变换
    wire rst_n_falling = btn_sync_2[4] & ~btn_sync_1[4];
    wire key_changed   = (btn_sync_2[3:0] != btn_sync_1[3:0]);
    wire rst_trigger   = rst_n_falling | key_changed;

    // 触发 256 拍同步复位脉冲
    reg [7:0] soft_rst_cnt;
    wire      soft_rst_n = (soft_rst_cnt == 8'd0);

    always @(posedge sys_clk) begin
        if (!por_rst_n) begin
            soft_rst_cnt <= 8'd0;
        end else if (rst_trigger) begin
            soft_rst_cnt <= 8'hFF;
        end else if (soft_rst_cnt != 8'd0) begin
            soft_rst_cnt <= soft_rst_cnt - 8'd1;
        end
    end

    // SoC 全局同步复位
    wire soc_rst_n = por_rst_n & soft_rst_n;

    // =========================================================================
    // 3. 例化 SoC 顶层
    // =========================================================================
    /* verilator lint_off UNUSED */
    wire        soc_wb_valid;
    wire        soc_wb_we;
    wire [31:0] soc_wb_pc;
    wire [4:0]  soc_wb_rd;
    wire [31:0] soc_wb_wdata;
    wire [31:0] soc_perf_cycle;
    wire [31:0] soc_perf_instret;
    /* verilator lint_on  UNUSED */

    soc_top #(
        .CLK_HZ       (CLK_HZ),
        .BAUD         (BAUD),
        .SRAM_WORDS   (SRAM_WORDS),
        .MEM_INIT_FILE(MEM_INIT_FILE)
    ) u_soc (
        .clk         (sys_clk),
        .rst_n       (soc_rst_n),
        .uart_txd    (uart_txd),
        .uart_rxd    (uart_rxd),
        .led         (led),
        .wb_valid    (soc_wb_valid),
        .wb_we       (soc_wb_we),
        .wb_pc       (soc_wb_pc),
        .wb_rd       (soc_wb_rd),
        .wb_wdata    (soc_wb_wdata),
        .perf_cycle  (soc_perf_cycle),
        .perf_instret(soc_perf_instret)
    );

endmodule
`default_nettype wire
