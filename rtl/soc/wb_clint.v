`default_nettype none
// -----------------------------------------------------------------------------
// wb_clint — Wishbone B4 CLINT 定时器 (Core-Local Interruptor)
//
// 特性：
//   - 遵循 RISC-V 特权级规范 v1.12 的标准 CLINT 内存布局 (基地址 0x0200_0000)：
//       0x0000 MSIP        : 软件中断挂起 (S1 读恒 0，写忽略)
//       0x4000 MTIMECMP_LO : 定时器比较值低 32 位
//       0x4004 MTIMECMP_HI : 定时器比较值高 32 位
//       0xBFF8 MTIME_LO    : 64 位自由运行计数器低 32 位 (每个时钟周期 +1)
//       0xBFFC MTIME_HI    : 64 位自由运行计数器高 32 位
//   - 导出 timer_irq = (mtime >= mtimecmp)，为 S2 阶段接入特权级中断预留；
//   - 1 拍同步读出，单周期 ACK 响应。
// -----------------------------------------------------------------------------
module wb_clint (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Wishbone Slave 接口 ----
    input  wire        wbs_cyc_i,
    input  wire        wbs_stb_i,
    input  wire        wbs_we_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] wbs_adr_i,
    input  wire [3:0]  wbs_sel_i,
    /* verilator lint_on  UNUSEDSIGNAL */
    input  wire [31:0] wbs_dat_i,
    output reg  [31:0] wbs_dat_o,
    output reg         wbs_ack_o,

    // ---- 定时器中断信号 (输出至 CPU CSR / S2 阶段) ----
    output wire        timer_irq
);
    reg [63:0] mtime;
    reg [63:0] mtimecmp;

    assign timer_irq = (mtime >= mtimecmp);

    wire [15:0] reg_offset = wbs_adr_i[15:0];

    // =========================================================================
    // 64 位 mtime 自由运行计数与 mtimecmp 比较值维护
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            mtime    <= 64'd0;
            mtimecmp <= 64'hFFFF_FFFF_FFFF_FFFF; // 默认最大值，不上电误触发
        end else begin
            // 默认每个时钟周期自增 1
            mtime <= mtime + 64'd1;

            // 软件写入覆盖
            if (wbs_cyc_i & wbs_stb_i & wbs_we_i) begin
                case (reg_offset)
                    16'h4000: mtimecmp[31:0]  <= wbs_dat_i;
                    16'h4004: mtimecmp[63:32] <= wbs_dat_i;
                    16'hBFF8: mtime[31:0]     <= wbs_dat_i;
                    16'hBFFC: mtime[63:32]    <= wbs_dat_i;
                    default:  ; // 其余地址写忽略
                endcase
            end
        end
    end

    // =========================================================================
    // Wishbone 读逻辑与 ACK 响应 (1 拍延迟同步读)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            wbs_dat_o <= 32'd0;
            wbs_ack_o <= 1'b0;
        end else begin
            wbs_ack_o <= wbs_cyc_i & wbs_stb_i;

            if (wbs_cyc_i & wbs_stb_i & ~wbs_we_i) begin
                case (reg_offset)
                    16'h0000: wbs_dat_o <= 32'd0;
                    16'h4000: wbs_dat_o <= mtimecmp[31:0];
                    16'h4004: wbs_dat_o <= mtimecmp[63:32];
                    16'hBFF8: wbs_dat_o <= mtime[31:0];
                    16'hBFFC: wbs_dat_o <= mtime[63:32];
                    default:  wbs_dat_o <= 32'd0;
                endcase
            end
        end
    end

endmodule
`default_nettype wire
