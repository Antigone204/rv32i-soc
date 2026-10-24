`default_nettype none

// -----------------------------------------------------------------------------
// muldiv — RV32M 硬件乘除法单元 (Hardware Multiplier & Divider Unit)
//
// 功能：
//   实现 RISC-V 32 位标准 M 扩展的全部 8 条指令：
//   - 乘法 (MUL, MULH, MULHSU, MULHU)
//   - 除法与取模 (DIV, DIVU, REM, REMU)
//   - 完整支持 RISC-V 规范规定的除以 0 与有符号溢出边界值静默返回
//
// 微架构：
//   - 乘法：33-bit x 33-bit 符号扩展可推断乘法，打 1 拍寄存器输出 (EX 级停顿 1 拍，共耗 2 拍)
//   - 除法：32 拍恢复余数试商移位减状态机 (Restoring Division)，除以 0 与溢出 1 拍快速旁路
//
// 时序假设：
//   - valid_i 有效且当拍未完成时，组合输出 busy_o = 1 驱动 hazard_unit 停顿流水线
//   - 计算完成拍置 done_o = 1，当拍 busy_o 归 0，结果送入 EX/MEM，下一拍自动回到 IDLE
//
// 所在流水级：EX (Execute) 级
// -----------------------------------------------------------------------------
module muldiv (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_i,      // EX 级当前为有效 M 扩展指令 (id_ex_valid && id_ex_muldiv_en)
    input  wire        flush_i,      // 冲刷信号
    input  wire [2:0]  funct3_i,     // 000:MUL, 001:MULH, 010:MULHSU, 011:MULHU, 100:DIV, 101:DIVU, 110:REM, 111:REMU
    input  wire [31:0] op_a_i,       // 已前推的 rs1 操作数
    input  wire [31:0] op_b_i,       // 已前推的 rs2 操作数
    output wire        busy_o,       // 正在计算且当拍尚未完成 -> 驱动 ex_muldiv_stall 冻结流水线
    output reg         done_o,       // 计算完成脉冲 (当拍 result_o 有效，busy_o 为 0，指令流入 EX/MEM)
    output reg  [31:0] result_o      // 32 位计算结果
);

    // 状态机编码
    localparam [1:0] S_IDLE = 2'd0,
                     S_DIV  = 2'd1,
                     S_DONE = 2'd2;

    reg [1:0] state;

    // 区分乘法 (funct3[2] == 0) 与除法 (funct3[2] == 1)
    wire is_div_op = funct3_i[2];

    // -------------------------------------------------------------------------
    // 1. 乘法器数据通路 (33 位符号扩展统一有符号/无符号相乘)
    // -------------------------------------------------------------------------
    // MUL: signed x signed (低 32 位有符号/无符号等价)
    // MULH: signed x signed -> 高 32 位
    // MULHSU: signed x unsigned -> 高 32 位
    // MULHU: unsigned x unsigned -> 高 32 位
    wire sign_a = (funct3_i == 3'b011) ? 1'b0 : op_a_i[31];
    wire sign_b = (funct3_i == 3'b000 || funct3_i == 3'b001) ? op_b_i[31] : 1'b0;

    wire signed [32:0] ext_a = {sign_a, op_a_i};
    wire signed [32:0] ext_b = {sign_b, op_b_i};

    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [65:0] mult_prod = ext_a * ext_b;
    /* verilator lint_on UNUSEDSIGNAL */

    wire [31:0] mult_res = (funct3_i == 3'b000) ? mult_prod[31:0] : mult_prod[63:32];

    // -------------------------------------------------------------------------
    // 2. 除法器特殊边界与绝对值预处理
    // -------------------------------------------------------------------------
    wire is_div_by_zero = is_div_op && (op_b_i == 32'd0);
    wire is_overflow    = is_div_op && (!funct3_i[0]) && (op_a_i == 32'h80000000) && (op_b_i == 32'hffffffff);

    reg [31:0] special_res;
    always @(*) begin
        special_res = 32'd0;
        if (is_div_by_zero) begin
            case (funct3_i)
                3'b100:  special_res = 32'hffffffff; // DIV: -1
                3'b101:  special_res = 32'hffffffff; // DIVU: 0xFFFFFFFF
                3'b110:  special_res = op_a_i;       // REM: dividend
                3'b111:  special_res = op_a_i;       // REMU: dividend
                default: special_res = 32'd0;
            endcase
        end else if (is_overflow) begin
            special_res = (funct3_i == 3'b100) ? 32'h80000000 : 32'd0; // DIV: -2^31, REM: 0
        end
    end

    wire is_signed = !funct3_i[0];
    wire op_a_neg  = is_signed && op_a_i[31];
    wire op_b_neg  = is_signed && op_b_i[31];

    wire [31:0] unsigned_a = op_a_neg ? (-op_a_i) : op_a_i;
    wire [31:0] unsigned_b = op_b_neg ? (-op_b_i) : op_b_i;

    // -------------------------------------------------------------------------
    // 3. 32 拍试商移位减除法数据通路
    // -------------------------------------------------------------------------
    /* verilator lint_off UNUSEDSIGNAL */
    reg [31:0] rem_reg;       // rem_reg[31] 在每拍左移时被顶出
    /* verilator lint_on UNUSEDSIGNAL */
    reg [31:0] quot_reg;
    reg [31:0] divisor_reg;
    reg        sign_quot_reg;
    reg        sign_rem_reg;
    reg        is_rem_reg;
    reg [4:0]  cnt;

    wire [31:0] rem_shifted = {rem_reg[30:0], quot_reg[31]};
    wire [32:0] sub_diff    = {1'b0, rem_shifted} - {1'b0, divisor_reg};
    wire        sub_ok      = !sub_diff[32]; // 无借位则减法成功
    wire [31:0] next_rem    = sub_ok ? sub_diff[31:0] : rem_shifted;
    wire [31:0] next_quot   = {quot_reg[30:0], sub_ok};

    wire [31:0] final_quot  = sign_quot_reg ? (-next_quot) : next_quot;
    wire [31:0] final_rem   = sign_rem_reg  ? (-next_rem)  : next_rem;
    wire [31:0] div_res     = is_rem_reg ? final_rem : final_quot;

    // -------------------------------------------------------------------------
    // 4. 流水线握手控制 (busy_o 纯组合无死锁输出)
    // -------------------------------------------------------------------------
    assign busy_o = !flush_i && ((state == S_IDLE && valid_i && !done_o) || (state == S_DIV));

    always @(posedge clk) begin
        if (!rst_n || flush_i) begin
            state         <= S_IDLE;
            done_o        <= 1'b0;
            result_o      <= 32'd0;
            rem_reg       <= 32'd0;
            quot_reg      <= 32'd0;
            divisor_reg   <= 32'd0;
            sign_quot_reg <= 1'b0;
            sign_rem_reg  <= 1'b0;
            is_rem_reg    <= 1'b0;
            cnt           <= 5'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    done_o <= 1'b0;
                    if (valid_i && !done_o) begin
                        if (!is_div_op) begin
                            // 乘法：打 1 拍寄存器输出，耗时 2 拍 (EX 停顿 1 拍)
                            result_o <= mult_res;
                            done_o   <= 1'b1;
                            state    <= S_DONE;
                        end else if (is_div_by_zero || is_overflow) begin
                            // 除法特殊情况：1 拍快速旁路返回
                            result_o <= special_res;
                            done_o   <= 1'b1;
                            state    <= S_DONE;
                        end else begin
                            // 常规除法：启动 32 拍迭代
                            rem_reg       <= 32'd0;
                            quot_reg      <= unsigned_a;
                            divisor_reg   <= unsigned_b;
                            sign_quot_reg <= is_signed && (op_a_i[31] ^ op_b_i[31]);
                            sign_rem_reg  <= is_signed && op_a_i[31];
                            is_rem_reg    <= funct3_i[1];
                            cnt           <= 5'd0;
                            state         <= S_DIV;
                        end
                    end
                end

                S_DIV: begin
                    if (cnt == 5'd31) begin
                        result_o <= div_res;
                        done_o   <= 1'b1;
                        state    <= S_DONE;
                    end else begin
                        rem_reg  <= next_rem;
                        quot_reg <= next_quot;
                        cnt      <= cnt + 5'd1;
                    end
                end

                S_DONE: begin
                    done_o <= 1'b0;
                    state  <= S_IDLE;
                end

                default: begin
                    done_o <= 1'b0;
                    state  <= S_IDLE;
                end
            endcase
        end
    end

endmodule
`default_nettype wire
