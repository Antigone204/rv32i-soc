`default_nettype none

// -----------------------------------------------------------------------------
// bpu — 分支预测单元 (Branch Prediction Unit)
//
// 架构：直接映射 BTB (Branch Target Buffer) + 2-bit 饱和计数器 BHT
// 所在流水级：
//   - IF 级：纯组合逻辑查表预测 (零气泡提供 pred_taken 与 pred_target)
//   - EX 级：分支指令裁决后在时钟上升沿训练更新 (Taken-only 动态分配)
//
// 复杂度控制铁律：130~160 行以内，逻辑清晰极简、高内聚，零组合逻辑环路
// -----------------------------------------------------------------------------
module bpu #(
    parameter integer INDEX_BITS = 6
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- IF 级预测查询接口 (纯组合逻辑读) ----
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] if_pc_i,
    /* verilator lint_on  UNUSEDSIGNAL */
    output wire        pred_taken_o,
    output wire [31:0] pred_target_o,

    // ---- EX 级训练与更新接口 (时钟上升沿写) ----
    input  wire        upd_valid_i,     // EX 级为有效分支/跳转指令且未停顿
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] upd_pc_i,        // EX 级指令 PC (id_ex_pc)
    /* verilator lint_on  UNUSEDSIGNAL */
    input  wire        upd_is_uncond_i, // 1: JAL/JALR 无条件跳转, 0: 条件分支
    input  wire        upd_taken_i,     // EX 级实际是否跳转
    input  wire [31:0] upd_target_i     // EX 级实际跳转目标地址
);

    // =========================================================================
    // 0. 参数与存储阵列定义
    // =========================================================================
    localparam integer ENTRIES  = (1 << INDEX_BITS); // 默认 64 项
    localparam integer TAG_BITS = 30 - INDEX_BITS;   // pc[31 : INDEX_BITS+2]，默认 24 位

    // BTB 表项阵列
    reg                  btb_valid  [0:ENTRIES-1];
    reg                  btb_uncond [0:ENTRIES-1];
    reg [TAG_BITS-1:0]   btb_tag    [0:ENTRIES-1];
    reg [31:0]           btb_target [0:ENTRIES-1];

    // 2-bit 饱和计数器 BHT 阵列 (00: 强不跳, 01: 弱不跳, 10: 弱跳, 11: 强跳)
    reg [1:0]            bht        [0:ENTRIES-1];

    // =========================================================================
    // 1. IF 级预测查询逻辑 (纯组合逻辑，零延时读出)
    // =========================================================================
    wire [INDEX_BITS-1:0] if_idx = if_pc_i[INDEX_BITS+1 : 2];
    wire [TAG_BITS-1:0]   if_tag = if_pc_i[31 : INDEX_BITS+2];

    wire if_btb_hit = btb_valid[if_idx] && (btb_tag[if_idx] == if_tag);

    // 预测跳转条件：BTB 命中 且 (无条件跳转 标识置位 或 2-bit 状态机高位为 1)
    assign pred_taken_o  = if_btb_hit && (btb_uncond[if_idx] || bht[if_idx][1]);
    assign pred_target_o = btb_target[if_idx];

    // =========================================================================
    // 2. EX 级训练与更新逻辑 (时钟上升沿同步写入)
    // =========================================================================
    wire [INDEX_BITS-1:0] upd_idx = upd_pc_i[INDEX_BITS+1 : 2];
    wire [TAG_BITS-1:0]   upd_tag = upd_pc_i[31 : INDEX_BITS+2];

    wire upd_hit = btb_valid[upd_idx] && (btb_tag[upd_idx] == upd_tag);

    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            // 同步复位：清空有效位与无条件位，BHT 初始化为 01 (弱不跳)
            for (i = 0; i < ENTRIES; i = i + 1) begin
                btb_valid[i]  <= 1'b0;
                btb_uncond[i] <= 1'b0;
                btb_tag[i]    <= {TAG_BITS{1'b0}};
                btb_target[i] <= 32'd0;
                bht[i]        <= 2'b01;
            end
        end else if (upd_valid_i) begin
            if (upd_hit) begin
                // 表项命中：更新跳转目标地址与无条件标记
                if (upd_taken_i) begin
                    btb_target[upd_idx] <= upd_target_i;
                    btb_uncond[upd_idx] <= upd_is_uncond_i;
                    // 饱和计数器加 1 (最大 2'b11)
                    if (bht[upd_idx] != 2'b11) begin
                        bht[upd_idx] <= bht[upd_idx] + 2'd1;
                    end
                end else begin
                    // 实际未跳转：饱和计数器减 1 (最小 2'b00)
                    if (bht[upd_idx] != 2'b00) begin
                        bht[upd_idx] <= bht[upd_idx] - 2'd1;
                    end
                end
            end else begin
                // 表项未命中：采用 Taken-only 策略分配新表项 (避免从不跳转的冷分支污染 BTB)
                if (upd_taken_i) begin
                    btb_valid[upd_idx]  <= 1'b1;
                    btb_uncond[upd_idx] <= upd_is_uncond_i;
                    btb_tag[upd_idx]    <= upd_tag;
                    btb_target[upd_idx] <= upd_target_i;
                    // JAL/JALR 初始赋 2'b11 强跳，条件分支初始赋 2'b10 弱跳
                    bht[upd_idx]        <= upd_is_uncond_i ? 2'b11 : 2'b10;
                end
            end
        end
    end

endmodule
`default_nettype wire
