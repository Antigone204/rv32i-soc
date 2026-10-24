`default_nettype none
// -----------------------------------------------------------------------------
// wb_interconnect — Wishbone B4 共享总线互连（单 Master → 多 Slave）
//
// 功能：地址译码 + 读数据/ACK 多路选择。
// 地址映射：
//   Slave 0 (SRAM)  : 0x0000_0000 – 0x0000_FFFF  (adr[31:16] == 0x0000)
//   Slave 1 (UART)  : 0x1001_0000 – 0x1001_FFFF  (adr[31:16] == 0x1001)
//   Slave 2 (CLINT) : 0x0200_0000 – 0x0200_FFFF  (adr[31:16] == 0x0200)
//   Slave 3 (ACC)   : 0x2000_0000 – 0x2000_FFFF  (adr[31:16] == 0x2000)
// 时序：stb 路由基于当拍地址（组合），响应路由基于上一拍地址（寄存），
//       匹配 core 的 fire-and-forget 访存时序。
// -----------------------------------------------------------------------------
module wb_interconnect (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Wishbone Master 端口 (来自 wb_core_bridge) ----
    input  wire        wbm_cyc_i,
    input  wire        wbm_stb_i,
    input  wire        wbm_we_i,
    input  wire [31:0] wbm_adr_i,
    input  wire [31:0] wbm_dat_i,
    input  wire [3:0]  wbm_sel_i,
    output reg  [31:0] wbm_dat_o,
    output reg         wbm_ack_o,

    // ---- Slave 0: SRAM (0x0000_xxxx) ----
    output wire        wbs0_cyc_o,
    output wire        wbs0_stb_o,
    output wire        wbs0_we_o,
    output wire [31:0] wbs0_adr_o,
    output wire [31:0] wbs0_dat_o,
    output wire [3:0]  wbs0_sel_o,
    input  wire [31:0] wbs0_dat_i,
    input  wire        wbs0_ack_i,

    // ---- Slave 1: UART (0x1001_xxxx) ----
    output wire        wbs1_cyc_o,
    output wire        wbs1_stb_o,
    output wire        wbs1_we_o,
    output wire [31:0] wbs1_adr_o,
    output wire [31:0] wbs1_dat_o,
    output wire [3:0]  wbs1_sel_o,
    input  wire [31:0] wbs1_dat_i,
    input  wire        wbs1_ack_i,

    // ---- Slave 2: CLINT (0x0200_xxxx) ----
    output wire        wbs2_cyc_o,
    output wire        wbs2_stb_o,
    output wire        wbs2_we_o,
    output wire [31:0] wbs2_adr_o,
    output wire [31:0] wbs2_dat_o,
    output wire [3:0]  wbs2_sel_o,
    input  wire [31:0] wbs2_dat_i,
    input  wire        wbs2_ack_i,

    // ---- Slave 3: MAC Accelerator (0x2000_xxxx) ----
    output wire        wbs3_cyc_o,
    output wire        wbs3_stb_o,
    output wire        wbs3_we_o,
    output wire [31:0] wbs3_adr_o,
    output wire [31:0] wbs3_dat_o,
    output wire [3:0]  wbs3_sel_o,
    input  wire [31:0] wbs3_dat_i,
    input  wire        wbs3_ack_i
);

    // =========================================================================
    // 地址译码（组合逻辑，当拍有效）
    // =========================================================================
    wire sel_sram     = (wbm_adr_i[31:16] == 16'h0000);
    wire sel_uart     = (wbm_adr_i[31:16] == 16'h1001);
    wire sel_clint    = (wbm_adr_i[31:16] == 16'h0200);
    wire sel_acc      = (wbm_adr_i[31:16] == 16'h2000);
    wire sel_unmapped = ~(sel_sram | sel_uart | sel_clint | sel_acc);

    // =========================================================================
    // 请求路由：stb/cyc 按组合译码门控到选中的从设备
    // =========================================================================
    assign wbs0_cyc_o = wbm_cyc_i & sel_sram;
    assign wbs0_stb_o = wbm_stb_i & sel_sram;
    assign wbs1_cyc_o = wbm_cyc_i & sel_uart;
    assign wbs1_stb_o = wbm_stb_i & sel_uart;
    assign wbs2_cyc_o = wbm_cyc_i & sel_clint;
    assign wbs2_stb_o = wbm_stb_i & sel_clint;
    assign wbs3_cyc_o = wbm_cyc_i & sel_acc;
    assign wbs3_stb_o = wbm_stb_i & sel_acc;

    // we / adr / dat / sel 广播给所有从设备（仅 stb 有效时从设备才响应）
    assign wbs0_we_o  = wbm_we_i;
    assign wbs1_we_o  = wbm_we_i;
    assign wbs2_we_o  = wbm_we_i;
    assign wbs3_we_o  = wbm_we_i;
    assign wbs0_adr_o = wbm_adr_i;
    assign wbs1_adr_o = wbm_adr_i;
    assign wbs2_adr_o = wbm_adr_i;
    assign wbs3_adr_o = wbm_adr_i;
    assign wbs0_dat_o = wbm_dat_i;
    assign wbs1_dat_o = wbm_dat_i;
    assign wbs2_dat_o = wbm_dat_i;
    assign wbs3_dat_o = wbm_dat_i;
    assign wbs0_sel_o = wbm_sel_i;
    assign wbs1_sel_o = wbm_sel_i;
    assign wbs2_sel_o = wbm_sel_i;
    assign wbs3_sel_o = wbm_sel_i;

    // =========================================================================
    // 响应路由：使用寄存的地址译码结果选择返回数据
    //
    // 原因：core 的 dmem 端口为 fire-and-forget 风格（读地址在 EX 级发出，
    //       下一拍可能已切换到新地址），但从设备的 ack 和 dat 在请求后 1 拍
    //       才有效。因此必须用寄存的译码结果来路由返回路径。
    // =========================================================================
    reg [2:0] sel_r;              // 0=SRAM, 1=UART, 2=CLINT, 3=ACC, 4=unmapped
    reg       unmapped_pending_r; // 记录上一拍是否存在有效的未映射请求

    always @(posedge clk) begin
        if (!rst_n) begin
            sel_r              <= 3'd4;
            unmapped_pending_r <= 1'b0;
        end else begin
            unmapped_pending_r <= wbm_cyc_i & wbm_stb_i & sel_unmapped;
            if (wbm_stb_i) begin
                if (sel_sram)       sel_r <= 3'd0;
                else if (sel_uart)  sel_r <= 3'd1;
                else if (sel_clint) sel_r <= 3'd2;
                else if (sel_acc)   sel_r <= 3'd3;
                else                sel_r <= 3'd4;
            end
        end
    end

    // 读数据 + ACK 多路选择（基于上一拍的译码结果）
    always @(*) begin
        case (sel_r)
            3'd0: begin
                wbm_dat_o = wbs0_dat_i;
                wbm_ack_o = wbs0_ack_i;
            end
            3'd1: begin
                wbm_dat_o = wbs1_dat_i;
                wbm_ack_o = wbs1_ack_i;
            end
            3'd2: begin
                wbm_dat_o = wbs2_dat_i;
                wbm_ack_o = wbs2_ack_i;
            end
            3'd3: begin
                wbm_dat_o = wbs3_dat_i;
                wbm_ack_o = wbs3_ack_i;
            end
            default: begin
                wbm_dat_o = 32'h0000_0000;
                wbm_ack_o = unmapped_pending_r;
            end
        endcase
    end

endmodule
`default_nettype wire
