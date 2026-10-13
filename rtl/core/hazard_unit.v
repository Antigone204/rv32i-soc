`default_nettype none

// -----------------------------------------------------------------------------
// hazard_unit — 冒险停顿与冲刷控制单元 (Hazard Detection & Stall/Flush Unit)
//
// 功能：
//   1. 解决 Load-Use 数据冒险 (Load-Use Data Hazard)：
//      当 EX 级为 Load 指令，且 ID 级指令正要使用其目标寄存器时，
//      由于数据尚未从内存读出，前推通路无法解决，必须暂停流水线：
//      - 冻结 PC (stall_pc = 1)；
//      - 冻结 IF/ID 流水线寄存器 (stall_if_id = 1)；
//      - 向 ID/EX 寄存器注入气泡/清零 (flush_id_ex = 1)。
//
//   2. 解决控制冒险 (Control Hazard / Branch Misprediction Flush)：
//      当 EX 级判定分支跳转成立 (branch_taken) 或执行无条件跳转 (jal / jalr) 时，
//      后续已经取入流水线的 2 条指令属于错误路径指令，必须被清除：
//      - 冲刷 IF/ID 寄存器 (flush_if_id = 1)；
//      - 冲刷 ID/EX 寄存器 (flush_id_ex = 1)。
//
// 时序：纯组合逻辑，零时延。
// 所在流水级：连接 ID、EX 级与流水线控制寄存器。
// -----------------------------------------------------------------------------
module hazard_unit (
    // ID 级当前指令的源寄存器
    input  wire [4:0] if_id_rs1,
    input  wire [4:0] if_id_rs2,

    // EX 级当前指令的信息 (检测 Load-Use)
    input  wire       id_ex_mem_read,
    input  wire [4:0] id_ex_rd,

    // 分支/跳转触发信号 (来自 EX 级)
    input  wire       branch_taken,
    input  wire       jal,
    input  wire       jalr,

    // 控制输出：流水线停顿 (Stall) 信号 (高电平有效)
    output reg        stall_pc,
    output reg        stall_if_id,

    // 控制输出：流水线清零冲刷 (Flush) 信号 (高电平有效)
    output reg        flush_if_id,
    output reg        flush_id_ex
);
    // 判断是否发生跳转 (控制冒险)
    wire jump_or_branch = branch_taken | jal | jalr;

    // 判断是否发生 Load-Use 冲突
    // 条件：EX 级读内存 + 目标寄存器非 x0 + 目标寄存器与 ID 级源寄存器重合
    wire load_use_hazard = id_ex_mem_read & (id_ex_rd != 5'd0) &
                           ((id_ex_rd == if_id_rs1) | (id_ex_rd == if_id_rs2));

    always @(*) begin
        // 默认状态：流水线全速自由前进
        stall_pc    = 1'b0;
        stall_if_id = 1'b0;
        flush_if_id = 1'b0;
        flush_id_ex = 1'b0;

        // 1. 控制冒险处理 (优先级最高：跳转成立时，必须无条件冲刷错误指令)
        if (jump_or_branch) begin
            flush_if_id = 1'b1; // 清空 IF/ID 寄存器
            flush_id_ex = 1'b1; // 清空 ID/EX 寄存器
        end
        // 2. Load-Use 冒险处理 (停顿 1 拍并注入气泡)
        else if (load_use_hazard) begin
            stall_pc    = 1'b1; // 冻结 PC
            stall_if_id = 1'b1; // 保持 IF/ID 指令不变
            flush_id_ex = 1'b1; // 向 ID/EX 注入气泡 (清零控制信号)
        end
    end

endmodule
`default_nettype wire
