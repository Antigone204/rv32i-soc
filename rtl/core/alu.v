`default_nettype none
`include "rtl/core/alu_ops.vh"

// -----------------------------------------------------------------------------
// alu — RV32I 32 位算术逻辑单元
//
// 功能：
//   执行 RV32I 基础指令集中所要求的全部 32 位运算：
//   - 加法/减法 (ADD, SUB)
//   - 移位运算 (SLL, SRL, SRA，仅使用 op_b 的低 5 位作为移位量)
//   - 大小比较 (SLT: 有符号比较, SLTU: 无符号比较)
//   - 逻辑运算 (AND, OR, XOR)
//   - 操作数直通 (PASS_B: 用于 LUI 等操作)
//
// 接口：
//   op_a, op_b : 32 位运算输入
//   alu_op     : 4 位 ALU 控制码 (详见 alu_ops.vh)
//   alu_out    : 32 位运算结果
//   zero       : 零标志位 (当 alu_out == 0 时为 1)
//
// 时序：纯组合逻辑，零周期延迟
// 所在流水级：EX (Execute) 级
// -----------------------------------------------------------------------------
module alu (
    input  wire [3:0]  alu_op,
    input  wire [31:0] op_a,
    input  wire [31:0] op_b,
    output reg  [31:0] alu_out,
    output wire        zero
);
    wire [4:0] shamt = op_b[4:0];

    always @(*) begin
        case (alu_op)
            `ALU_ADD:    alu_out = op_a + op_b;
            `ALU_SUB:    alu_out = op_a - op_b;
            `ALU_SLL:    alu_out = op_a << shamt;
            `ALU_SLT:    alu_out = ($signed(op_a) < $signed(op_b)) ? 32'd1 : 32'd0;
            `ALU_SLTU:   alu_out = (op_a < op_b) ? 32'd1 : 32'd0;
            `ALU_XOR:    alu_out = op_a ^ op_b;
            `ALU_SRL:    alu_out = op_a >> shamt;
            `ALU_SRA:    alu_out = $signed(op_a) >>> shamt;
            `ALU_OR:     alu_out = op_a | op_b;
            `ALU_AND:    alu_out = op_a & op_b;
            `ALU_PASS_B: alu_out = op_b;
            default:     alu_out = 32'd0;
        endcase
    end

    assign zero = (alu_out == 32'd0);

endmodule
`default_nettype wire
