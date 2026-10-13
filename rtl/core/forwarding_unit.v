`default_nettype none

// -----------------------------------------------------------------------------
// forwarding_unit — 数据前推单元 (Forwarding / Bypass Unit)
//
// 功能：
//   检测当前执行级 (EX) 所需的源操作数 (rs1, rs2) 是否与后续流水级
//   (EX/MEM 级或 MEM/WB 级) 即将写回的目标寄存器 (rd) 存在 RAW 数据依赖。
//   若存在依赖，输出多路选择器控制信号 (forward_a, forward_b)，
//   将最新的计算结果直接旁路前推回 EX 级 ALU 输入端，避免产生停顿气泡。
//
// 控制编码定义：
//   2'b00 : 无前推，ALU 操作数取自 ID/EX 寄存器 (寄存器堆原始读出值)
//   2'b10 : EX-EX 前推，ALU 操作数截胡自 EX/MEM 级 (前一条指令的 ALU 结果)
//   2'b01 : MEM-EX 前推，ALU 操作数截胡自 MEM/WB 级 (前前条指令的最终写回数据)
//
// 关键优先级规则：
//   EX-EX 前推的优先级必须严格高于 MEM-EX 前推！
//   当连续三条指令连续修改同一寄存器时，EX 级必须拿到最新一条 (即紧邻前一条) 的值。
//
// 时序：纯组合逻辑，零时延。
// 所在流水级：连接 ID/EX、EX/MEM、MEM/WB。
// -----------------------------------------------------------------------------
module forwarding_unit (
    // 当前处于 EX 级的源寄存器索引
    input  wire [4:0] id_ex_rs1,
    input  wire [4:0] id_ex_rs2,

    // 处于 EX/MEM 级的前一条指令写目标信息
    input  wire [4:0] ex_mem_rd,
    input  wire       ex_mem_reg_write,

    // 处于 MEM/WB 级的前前条指令写目标信息
    input  wire [4:0] mem_wb_rd,
    input  wire       mem_wb_reg_write,

    // 前推多路选择器控制输出 (控制 ALU 输入端 MUX)
    output reg  [1:0] forward_a,
    output reg  [1:0] forward_b
);
    // ---------------- 操作数 A 前推决策 ----------------
    always @(*) begin
        // 1. 优先检查 EX-EX 前推 (前一条指令)
        // 条件：写使能有效 + 目标寄存器非 x0 + 目标寄存器匹配当前 rs1
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) begin
            forward_a = 2'b10;
        end
        // 2. 其次检查 MEM-EX 前推 (前前条指令)
        // 条件：写使能有效 + 目标寄存器非 x0 + 目标寄存器匹配当前 rs1
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) begin
            forward_a = 2'b01;
        end
        // 3. 无依赖，直接使用寄存器堆读出的原始值
        else begin
            forward_a = 2'b00;
        end
    end

    // ---------------- 操作数 B 前推决策 ----------------
    always @(*) begin
        // 1. 优先检查 EX-EX 前推 (前一条指令)
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)) begin
            forward_b = 2'b10;
        end
        // 2. 其次检查 MEM-EX 前推 (前前条指令)
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2)) begin
            forward_b = 2'b01;
        end
        // 3. 无依赖
        else begin
            forward_b = 2'b00;
        end
    end

endmodule
`default_nettype wire
