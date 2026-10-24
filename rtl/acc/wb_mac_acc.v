`default_nettype none
// -----------------------------------------------------------------------------
// wb_mac_acc — Wishbone B4 4 路并行 SIMD INT8 乘累加与 ReLU 硬件加速器
//
// 所属项目：RISC-V 并行加速系统 (全国大学生嵌入式芯片与系统设计竞赛)
// 基地址   ：0x2000_0000 (Wishbone Slave 接口)
// 所在层级：SoC 外设 / 算子硬件加速扩展单元
//
// 特性：
//   1. 4 路 SIMD INT8 并行乘法 + 32 位累加器 (单拍内完成 4 路乘加)：
//      - ACC_OPA (0x04) 锁存打包操作数 A: {a3, a2, a1, a0} (4 个 signed int8)
//      - ACC_OPB_TRIG (0x08) 隐式触发写入 (Implicit Trigger-on-Write)：
//        写入打包操作数 B 时，当拍同时完成 dot4 = (a0*b0 + a1*b1 + a2*b2 + a3*b3)，
//        并累加至 acc_reg，mac_count 自动自增 1。
//   2. 偏置与激活支持：
//      - ACC_RESULT (0x0C) 支持直接写入，用于预置神经网络全连接层/卷积层的 bias。
//      - ACC_RELU   (0x10) 硬件零延迟输出 max(0, acc_reg)，读出即完成激活。
//   3. 零等待单周期 ACK：Wishbone 1 拍同步读出，吞吐率可达每 1~2 拍一次 4-MAC。
// -----------------------------------------------------------------------------
module wb_mac_acc (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Wishbone B4 Slave 接口 ----
    input  wire        wbs_cyc_i,
    input  wire        wbs_stb_i,
    input  wire        wbs_we_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] wbs_adr_i,
    input  wire [3:0]  wbs_sel_i,
    /* verilator lint_on  UNUSEDSIGNAL */
    input  wire [31:0] wbs_dat_i,
    output reg  [31:0] wbs_dat_o,
    output reg         wbs_ack_o
);

    // =========================================================================
    // 1. 内部寄存器定义
    // =========================================================================
    reg [31:0] op_a_reg;   // 打包操作数 A 寄存器: {a3, a2, a1, a0}
    reg [31:0] op_b_reg;   // 打包操作数 B 寄存器: {b3, b2, b1, b0}
    reg [31:0] acc_reg;    // 32 位有符号累加器
    reg [31:0] mac_count;  // 4 路 MAC 执行批次计数器 (累计完成 4 * mac_count 次乘加)

    // =========================================================================
    // 2. 4 路 SIMD INT8 乘法与符号扩展求和数据流 (组合逻辑)
    // =========================================================================
    // 操作数 A 解包为 4 个 signed 8-bit
    wire signed [7:0] a0 = $signed(op_a_reg[7:0]);
    wire signed [7:0] a1 = $signed(op_a_reg[15:8]);
    wire signed [7:0] a2 = $signed(op_a_reg[23:16]);
    wire signed [7:0] a3 = $signed(op_a_reg[31:24]);

    // 操作数 B 取自当拍总线写入数据 wbs_dat_i，解包为 4 个 signed 8-bit
    wire signed [7:0] b0 = $signed(wbs_dat_i[7:0]);
    wire signed [7:0] b1 = $signed(wbs_dat_i[15:8]);
    wire signed [7:0] b2 = $signed(wbs_dat_i[23:16]);
    wire signed [7:0] b3 = $signed(wbs_dat_i[31:24]);

    // 4 路并行有符号 8-bit * 8-bit 乘法器，生成 16-bit 有符号乘积
    wire signed [15:0] prod0 = a0 * b0;
    wire signed [15:0] prod1 = a1 * b1;
    wire signed [15:0] prod2 = a2 * b2;
    wire signed [15:0] prod3 = a3 * b3;

    // 符号扩展至 32-bit 并求和，得到 4 路点积结果
    wire signed [31:0] dot4 = {{16{prod0[15]}}, prod0} +
                              {{16{prod1[15]}}, prod1} +
                              {{16{prod2[15]}}, prod2} +
                              {{16{prod3[15]}}, prod3};

    // 硬件零延迟 ReLU 激活：最高位符号位为 1 (负数) 则输出 0，否则原值输出
    wire [31:0] acc_relu = acc_reg[31] ? 32'd0 : acc_reg;

    // =========================================================================
    // 3. 寄存器写入与隐式触发累加逻辑 (时序逻辑)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            op_a_reg  <= 32'd0;
            op_b_reg  <= 32'd0;
            acc_reg   <= 32'd0;
            mac_count <= 32'd0;
        end else if (wbs_cyc_i & wbs_stb_i & wbs_we_i) begin
            case (wbs_adr_i[7:0])
                8'h00: begin // ACC_CTRL: bit[0]=1 时清零累加器与计数器
                    if (wbs_dat_i[0]) begin
                        acc_reg   <= 32'd0;
                        mac_count <= 32'd0;
                    end
                end
                8'h04: begin // ACC_OPA: 写入打包操作数 A
                    op_a_reg  <= wbs_dat_i;
                end
                8'h08: begin // ACC_OPB_TRIG: 写入操作数 B 并隐式触发 4 路 MAC 累加
                    op_b_reg  <= wbs_dat_i;
                    acc_reg   <= $signed(acc_reg) + dot4;
                    mac_count <= mac_count + 32'd1;
                end
                8'h0C: begin // ACC_RESULT: 直接写入累加器 (预置初始 Bias)
                    acc_reg   <= wbs_dat_i;
                end
                default: ; // 8'h10 (ReLU) 与 8'h14 (COUNT) 为只读，写忽略
            endcase
        end
    end

    // =========================================================================
    // 4. Wishbone 读逻辑与 ACK 握手响应 (1 拍同步读出)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            wbs_dat_o <= 32'd0;
            wbs_ack_o <= 1'b0;
        end else begin
            // 单周期同步 ACK 响应
            wbs_ack_o <= wbs_cyc_i & wbs_stb_i;

            if (wbs_cyc_i & wbs_stb_i & ~wbs_we_i) begin
                case (wbs_adr_i[7:0])
                    8'h00:   wbs_dat_o <= 32'd0;     // ACC_CTRL
                    8'h04:   wbs_dat_o <= op_a_reg;  // ACC_OPA
                    8'h08:   wbs_dat_o <= op_b_reg;  // ACC_OPB_TRIG
                    8'h0C:   wbs_dat_o <= acc_reg;   // ACC_RESULT
                    8'h10:   wbs_dat_o <= acc_relu;  // ACC_RELU
                    8'h14:   wbs_dat_o <= mac_count; // ACC_COUNT
                    default: wbs_dat_o <= 32'd0;
                endcase
            end
        end
    end

endmodule
`default_nettype wire
