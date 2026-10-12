`default_nettype none

// -----------------------------------------------------------------------------
// imm_gen — RV32I 立即数生成扩展单元 (Immediate Generator)
//
// 功能：
//   根据指令的编码类型，提取分散在 32 位指令字中的立即数字段，
//   按照 RISC-V 规范重组并进行符号扩展，输出 32 位有符号立即数。
//
// 支持的立即数类型 (imm_sel):
//   3'd0 : I-type  — 用于计算/Load/JALR，12 位立即数 inst[31:20]
//   3'd1 : S-type  — 用于 Store 访存，12 位立即数拆分为 inst[31:25] 与 inst[11:7]
//   3'd2 : B-type  — 用于条件分支，13 位偏移量 (最低位补 0)
//   3'd3 : U-type  — 用于 LUI/AUIPC，高 20 位立即数 inst[31:12]，低 12 位补 0
//   3'd4 : J-type  — 用于 JAL 跳转，21 位偏移量 (最低位补 0)
//
// 时序：纯组合逻辑，零延迟。
// 所在流水级：ID (Instruction Decode) 级。
// -----------------------------------------------------------------------------
module imm_gen (
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] inst,    // inst[6:0] 为操作码 opcode，立即数拼装不使用低 7 位
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [2:0]  imm_sel,
    output reg  [31:0] imm_out
);
    // 立即数类型枚举定义
    localparam [2:0] IMM_I = 3'd0,
                     IMM_S = 3'd1,
                     IMM_B = 3'd2,
                     IMM_U = 3'd3,
                     IMM_J = 3'd4;

    always @(*) begin
        case (imm_sel)
            // I-type: imm[11:0] = inst[31:20]，高 20 位符号扩展
            IMM_I: begin
                imm_out = {{20{inst[31]}}, inst[31:20]};
            end

            // S-type: imm[11:0] = {inst[31:25], inst[11:7]}，高 20 位符号扩展
            IMM_S: begin
                imm_out = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            end

            // B-type: imm[12:0] = {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
            // 高 19 位符号扩展
            IMM_B: begin
                imm_out = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            end

            // U-type: imm[31:0] = {inst[31:12], 12'b0}
            IMM_U: begin
                imm_out = {inst[31:12], 12'b0};
            end

            // J-type: imm[20:0] = {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
            // 高 11 位符号扩展
            IMM_J: begin
                imm_out = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
            end

            default: begin
                imm_out = 32'd0;
            end
        endcase
    end

endmodule
`default_nettype wire
