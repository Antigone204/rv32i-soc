`default_nettype none
`include "alu_ops.vh"

// -----------------------------------------------------------------------------
// decoder — RV32I 指令主控制译码器 (Instruction Decoder & Control Unit)
//
// 功能：
//   解析 32 位机器指令，提取操作码与各个功能字段，
//   生成驱动整条 5 级流水线的全部控制信号：
//   - 立即数类型选择 (imm_sel)
//   - ALU 运算码 (alu_op) 与操作数来源多路选择 (alu_src_a, alu_src_b)
//   - 内存读写使能 (mem_read, mem_write)
//   - 通用寄存器写回使能 (reg_write) 与写回数据来源选择 (wb_src_sel)
//   - 控制跳转信号 (branch, jal, jalr)
//
// 时序：纯组合逻辑，零时延。
// 所在流水级：ID (Instruction Decode) 级。
// -----------------------------------------------------------------------------
module decoder (
    input  wire [31:0] inst,

    // 寄存器索引引出 (直接透传指令字段)
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    output wire [2:0]  funct3,
    output wire [6:0]  funct7,

    // 立即数生成控制
    output reg  [2:0]  imm_sel,

    // 执行级 (EX) 控制信号
    output reg  [3:0]  alu_op,
    output reg         alu_src_a,  // 0: rs1, 1: pc
    output reg         alu_src_b,  // 0: rs2, 1: imm

    // 访存级 (MEM) 控制信号
    output reg         mem_read,
    output reg         mem_write,

    // 写回级 (WB) 控制信号
    output reg         reg_write,
    output reg  [1:0]  wb_src_sel, // 0: alu_out, 1: mem_data, 2: pc_plus_4

    // 分支与跳转控制
    output reg         branch,
    output reg         jal,
    output reg         jalr,

    // 异常/未定义指令指示
    output reg         illegal_inst,

    // M 扩展乘除法使能指示 (OPCODE_OP && funct7 == 7'b0000001)
    output reg         muldiv_en
);
    // 立即数类型编码
    localparam [2:0] IMM_I = 3'd0,
                     IMM_S = 3'd1,
                     IMM_B = 3'd2,
                     IMM_U = 3'd3,
                     IMM_J = 3'd4;

    // 写回数据来源编码
    localparam [1:0] WB_SRC_ALU = 2'd0,
                     WB_SRC_MEM = 2'd1,
                     WB_SRC_PC4 = 2'd2;

    // RV32I 基础 Opcode 编码 (低 2 位恒为 2'b11)
    localparam [6:0] OPC_R_TYPE  = 7'b0110011, // 算术逻辑计算 (ADD, SUB, AND...)
                     OPC_I_TYPE  = 7'b0010011, // 立即数计算 (ADDI, ANDI...)
                     OPC_LOAD    = 7'b0000011, // 访存读取 (LW, LB, LH...)
                     OPC_STORE   = 7'b0100011, // 访存写入 (SW, SB, SH...)
                     OPC_BRANCH  = 7'b1100011, // 条件分支 (BEQ, BNE, BLT...)
                     OPC_JAL     = 7'b1101111, // 无条件相对跳转
                     OPC_JALR    = 7'b1100111, // 间接跳转
                     OPC_LUI     = 7'b0110111, // 加载高位立即数
                     OPC_AUIPC   = 7'b0010111, // 高位立即数加至 PC
                     OPC_SYSTEM  = 7'b1110011, // 系统环境调用 (ECALL/EBREAK/CSR)
                     OPC_FENCE   = 7'b0001111; // 内存屏障 (作为 NOP 处理)

    // 字段拆解
    wire [6:0] opcode = inst[6:0];
    assign rd     = inst[11:7];
    assign funct3 = inst[14:12];
    assign rs1    = inst[19:15];
    assign rs2    = inst[24:20];
    assign funct7 = inst[31:25];

    always @(*) begin
        // ---------------- 赋全局默认值 (防锁存器产生) ----------------
        imm_sel      = IMM_I;
        alu_op       = `ALU_ADD;
        alu_src_a    = 1'b0;          // 默认选 rs1
        alu_src_b    = 1'b0;          // 默认选 rs2
        mem_read     = 1'b0;
        mem_write    = 1'b0;
        reg_write    = 1'b0;
        wb_src_sel   = WB_SRC_ALU;
        branch       = 1'b0;
        jal          = 1'b0;
        jalr         = 1'b0;
        illegal_inst = 1'b0;
        muldiv_en    = 1'b0;

        case (opcode)
            // ---------------- R-Type: 寄存器之间运算 ----------------
            OPC_R_TYPE: begin
                reg_write = 1'b1;
                alu_src_a = 1'b0; // rs1
                alu_src_b = 1'b0; // rs2
                wb_src_sel = WB_SRC_ALU;
                if (funct7 == 7'b0000001) begin
                    muldiv_en = 1'b1;
                end else begin
                    case (funct3)
                        3'b000:  alu_op = (funct7[5]) ? `ALU_SUB : `ALU_ADD;
                        3'b001:  alu_op = `ALU_SLL;
                        3'b010:  alu_op = `ALU_SLT;
                        3'b011:  alu_op = `ALU_SLTU;
                        3'b100:  alu_op = `ALU_XOR;
                        3'b101:  alu_op = (funct7[5]) ? `ALU_SRA : `ALU_SRL;
                        3'b110:  alu_op = `ALU_OR;
                        3'b111:  alu_op = `ALU_AND;
                        default: illegal_inst = 1'b1;
                    endcase
                end
            end

            // ---------------- I-Type: 立即数计算 ----------------
            OPC_I_TYPE: begin
                imm_sel   = IMM_I;
                reg_write = 1'b1;
                alu_src_a = 1'b0; // rs1
                alu_src_b = 1'b1; // imm
                wb_src_sel = WB_SRC_ALU;
                case (funct3)
                    3'b000:  alu_op = `ALU_ADD;  // ADDI
                    3'b001:  alu_op = `ALU_SLL;  // SLLI
                    3'b010:  alu_op = `ALU_SLT;  // SLTI
                    3'b011:  alu_op = `ALU_SLTU; // SLTIU
                    3'b100:  alu_op = `ALU_XOR;  // XORI
                    3'b101:  alu_op = (funct7[5]) ? `ALU_SRA : `ALU_SRL; // SRAI / SRLI
                    3'b110:  alu_op = `ALU_OR;   // ORI
                    3'b111:  alu_op = `ALU_AND;  // ANDI
                    default: illegal_inst = 1'b1;
                endcase
            end

            // ---------------- Load: 访存读 ----------------
            OPC_LOAD: begin
                imm_sel    = IMM_I;
                reg_write  = 1'b1;
                alu_src_a  = 1'b0; // rs1 (基址)
                alu_src_b  = 1'b1; // imm (偏移量)
                alu_op     = `ALU_ADD;
                mem_read   = 1'b1;
                wb_src_sel = WB_SRC_MEM;
            end

            // ---------------- Store: 访存写 ----------------
            OPC_STORE: begin
                imm_sel   = IMM_S;
                reg_write = 1'b0; // Store 不写通用寄存器
                alu_src_a = 1'b0; // rs1 (基址)
                alu_src_b = 1'b1; // imm (偏移量)
                alu_op    = `ALU_ADD;
                mem_write = 1'b1;
            end

            // ---------------- Branch: 条件分支 ----------------
            OPC_BRANCH: begin
                imm_sel   = IMM_B;
                reg_write = 1'b0; // 分支不写回寄存器
                branch    = 1'b1;
                alu_src_a = 1'b0; // rs1
                alu_src_b = 1'b0; // rs2 (比较由专用分支比较器完成)
                alu_op    = `ALU_SUB; // 默认做差
            end

            // ---------------- JAL: 无条件跳转并链接 ----------------
            OPC_JAL: begin
                imm_sel    = IMM_J;
                reg_write  = 1'b1; // 将 PC+4 写入 rd
                jal        = 1'b1;
                wb_src_sel = WB_SRC_PC4;
            end

            // ---------------- JALR: 寄存器间接跳转并链接 ----------------
            OPC_JALR: begin
                imm_sel    = IMM_I;
                reg_write  = 1'b1; // 将 PC+4 写入 rd
                jalr       = 1'b1;
                alu_src_a  = 1'b0; // rs1
                alu_src_b  = 1'b1; // imm
                alu_op     = `ALU_ADD; // 计算跳转目标 (rs1 + imm) & ~1
                wb_src_sel = WB_SRC_PC4;
            end

            // ---------------- LUI: 加载高位立即数 ----------------
            OPC_LUI: begin
                imm_sel    = IMM_U;
                reg_write  = 1'b1;
                alu_src_b  = 1'b1; // imm
                alu_op     = `ALU_PASS_B; // 直接输出立即数
                wb_src_sel = WB_SRC_ALU;
            end

            // ---------------- AUIPC: 当前 PC 加上高位立即数 ----------------
            OPC_AUIPC: begin
                imm_sel    = IMM_U;
                reg_write  = 1'b1;
                alu_src_a  = 1'b1; // 选 PC 作为加数
                alu_src_b  = 1'b1; // 选 imm 作为加数
                alu_op     = `ALU_ADD;
                wb_src_sel = WB_SRC_ALU;
            end

            // ---------------- FENCE: 内存屏障 (单发射单核作为 NOP) ----------------
            OPC_FENCE: begin
                // 保持全默认值 (NOP)
            end

            // ---------------- SYSTEM: ECALL / EBREAK / CSR ----------------
            OPC_SYSTEM: begin
                // 初期基线处理，后续接入 CSR
            end

            default: begin
                illegal_inst = 1'b1;
            end
        endcase
    end

endmodule
`default_nettype wire
