`default_nettype none
`include "alu_ops.vh"

// -----------------------------------------------------------------------------
// core — RV32I 5 级流水线处理器核 (5-Stage Pipelined RISC-V Core)
//
// 架构：经典 5 级静态流水线 (IF -> ID -> EX -> MEM -> WB)
// 特性：
//   - 支持 RV32I 基础整数指令集 (37 条指令)
//   - 动态数据前推 (Forwarding Unit) 消除 RAW 数据依赖
//   - 硬件冲突检测 (Hazard Unit) 实现 Load-Use 停顿与气泡注入
//   - 分支跳转冲刷 (Jump / Branch Flush) 处理控制冒险
//   - 硬件支持字节/半字/字访存与符号扩展 (LB/LH/LW/LBU/LHU/SB/SH/SW)
//   - 导出精确的提交追踪接口 (wb_valid, wb_pc, wb_rd, wb_wdata) 用于差分验证
//
// 时序假设：同周期同步复位 (rst_n 低有效)，时钟上升沿驱动流水线
// -----------------------------------------------------------------------------
module core (
    input  wire        clk,
    input  wire        rst_n,

    // ---------------- 指令存储器总线 (I-Bus) ----------------
    output wire [31:0] imem_addr,
    output wire        imem_req,
    input  wire [31:0] imem_rdata,

    // ---------------- 数据存储器总线 (D-Bus) ----------------
    output wire [31:0] dmem_addr,
    output reg  [31:0] dmem_wdata,
    output reg  [3:0]  dmem_byte_we,
    output wire        dmem_req,
    input  wire [31:0] dmem_rdata,

    // ---------------- 提交追踪接口 (DiffTest / 调试用) ----------------
    output wire        wb_valid,
    output wire        wb_we,
    output wire [31:0] wb_pc,
    output wire [4:0]  wb_rd,
    output wire [31:0] wb_wdata,

    // ---------------- 性能计数器输出 ----------------
    output reg  [31:0] perf_cycle,
    output reg  [31:0] perf_instret
);

    // =========================================================================
    // 0. 内部连线与控制信号声明
    // =========================================================================
    // 冒险控制信号
    wire stall_pc;
    wire stall_if_id;
    wire stall_id_ex;
    wire flush_if_id;
    wire flush_id_ex;
    wire flush_ex_mem;
    wire structural_hazard;

    // 分支与跳转信号 (在 EX 级生成)
    wire        branch_taken;
    wire [31:0] branch_target;

    // 前推控制信号
    wire [1:0] forward_a;
    wire [1:0] forward_b;

    // =========================================================================
    // 1. IF (Instruction Fetch - 取指级)
    // =========================================================================
    reg  [31:0] if_pc;
    wire [31:0] if_pc_plus_4 = if_pc + 32'd4;
    wire [31:0] if_next_pc   = (branch_taken) ? branch_target : if_pc_plus_4;

    always @(posedge clk) begin
        if (!rst_n) begin
            if_pc <= 32'h0000_0000;
        end else if (!stall_pc) begin
            if_pc <= if_next_pc;
        end
    end

    // 改动 B: 取指地址改用"下一拍的 PC" (if_next_pc) 提前一拍去读，停顿时保持不变
    assign imem_addr = (!rst_n)   ? 32'h0000_0000 :
                       (stall_pc) ? if_pc :
                       if_next_pc;
    assign imem_req  = 1'b1;

    // ---------------- 级间寄存器 1: IF/ID ----------------
    reg [31:0] if_id_pc;
    reg [31:0] if_id_inst;
    reg        if_id_valid;

    always @(posedge clk) begin
        if (!rst_n || flush_if_id) begin
            if_id_pc    <= 32'd0;
            if_id_inst  <= 32'h0000_0013; // 注入 NOP (addi x0, x0, 0)
            if_id_valid <= 1'b0;
        end else if (!stall_if_id) begin
            if_id_pc    <= if_pc;
            if_id_inst  <= imem_rdata;
            if_id_valid <= 1'b1;
        end
    end

    // =========================================================================
    // 2. ID (Instruction Decode - 译码级)
    // =========================================================================
    wire [4:0]  id_rs1;
    wire [4:0]  id_rs2;
    wire [4:0]  id_rd;
    wire [2:0]  id_funct3;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [6:0]  id_funct7;        // decoder 内部已完成 funct7 译码，此处仅为调试引出
    /* verilator lint_on UNUSEDSIGNAL */
    wire [2:0]  id_imm_sel;
    wire [3:0]  id_alu_op;
    wire        id_alu_src_a;
    wire        id_alu_src_b;
    wire        id_mem_read;
    wire        id_mem_write;
    wire        id_reg_write;
    wire [1:0]  id_wb_src_sel;
    wire        id_branch;
    wire        id_jal;
    wire        id_jalr;
    /* verilator lint_off UNUSEDSIGNAL */
    wire        id_illegal_inst;  // 异常处理扩展预留
    /* verilator lint_on UNUSEDSIGNAL */

    // 实例化主控制译码器
    decoder u_decoder (
        .inst        (if_id_inst),
        .rs1         (id_rs1),
        .rs2         (id_rs2),
        .rd          (id_rd),
        .funct3      (id_funct3),
        .funct7      (id_funct7),
        .imm_sel     (id_imm_sel),
        .alu_op      (id_alu_op),
        .alu_src_a   (id_alu_src_a),
        .alu_src_b   (id_alu_src_b),
        .mem_read    (id_mem_read),
        .mem_write   (id_mem_write),
        .reg_write   (id_reg_write),
        .wb_src_sel  (id_wb_src_sel),
        .branch      (id_branch),
        .jal         (id_jal),
        .jalr        (id_jalr),
        .illegal_inst(id_illegal_inst)
    );

    // 实例化立即数扩展单元
    wire [31:0] id_imm;
    imm_gen u_imm_gen (
        .inst   (if_id_inst),
        .imm_sel(id_imm_sel),
        .imm_out(id_imm)
    );

    // 实例化通用寄存器堆 (32x32)
    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;
    wire        wb_reg_write;
    wire [4:0]  wb_rd_addr;
    wire [31:0] wb_final_data;

    regfile u_regfile (
        .clk   (clk),
        .rst_n (rst_n),
        .raddr1(id_rs1),
        .rdata1(id_rs1_data),
        .raddr2(id_rs2),
        .rdata2(id_rs2_data),
        .we    (wb_reg_write),
        .waddr (wb_rd_addr),
        .wdata (wb_final_data)
    );

    // ---------------- 级间寄存器 2: ID/EX ----------------
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_rs1_data;
    reg [31:0] id_ex_rs2_data;
    reg [31:0] id_ex_imm;
    reg [4:0]  id_ex_rs1;
    reg [4:0]  id_ex_rs2;
    reg [4:0]  id_ex_rd;
    reg [2:0]  id_ex_funct3;
    reg [3:0]  id_ex_alu_op;
    reg        id_ex_alu_src_a;
    reg        id_ex_alu_src_b;
    reg        id_ex_mem_read;
    reg        id_ex_mem_write;
    reg        id_ex_reg_write;
    reg [1:0]  id_ex_wb_src_sel;
    reg        id_ex_branch;
    reg        id_ex_jal;
    reg        id_ex_jalr;
    reg        id_ex_valid;

    // 前推多路选择器输出声明 (供 ID/EX 停顿锁存及 EX 计算使用)
    reg [31:0] ex_fwd_val_a;
    reg [31:0] ex_fwd_val_b;

    always @(posedge clk) begin
        if (!rst_n || flush_id_ex) begin
            id_ex_pc         <= 32'd0;
            id_ex_rs1_data   <= 32'd0;
            id_ex_rs2_data   <= 32'd0;
            id_ex_imm        <= 32'd0;
            id_ex_rs1        <= 5'd0;
            id_ex_rs2        <= 5'd0;
            id_ex_rd         <= 5'd0;
            id_ex_funct3     <= 3'd0;
            id_ex_alu_op     <= `ALU_ADD;
            id_ex_alu_src_a  <= 1'b0;
            id_ex_alu_src_b  <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_reg_write  <= 1'b0;
            id_ex_wb_src_sel <= 2'd0;
            id_ex_branch     <= 1'b0;
            id_ex_jal        <= 1'b0;
            id_ex_jalr       <= 1'b0;
            id_ex_valid      <= 1'b0;
        end else if (stall_id_ex) begin
            // BUG-003: 停顿期间锁存当拍前推结果，防止前推源在后续周期写回后离开流水线导致操作数丢失
            id_ex_rs1_data   <= ex_fwd_val_a;
            id_ex_rs2_data   <= ex_fwd_val_b;
        end else begin
            id_ex_pc         <= if_id_pc;
            id_ex_rs1_data   <= id_rs1_data;
            id_ex_rs2_data   <= id_rs2_data;
            id_ex_imm        <= id_imm;
            id_ex_rs1        <= id_rs1;
            id_ex_rs2        <= id_rs2;
            id_ex_rd         <= id_rd;
            id_ex_funct3     <= id_funct3;
            id_ex_alu_op     <= id_alu_op;
            id_ex_alu_src_a  <= id_alu_src_a;
            id_ex_alu_src_b  <= id_alu_src_b;
            id_ex_mem_read   <= id_mem_read;
            id_ex_mem_write  <= id_mem_write;
            id_ex_reg_write  <= id_reg_write;
            id_ex_wb_src_sel <= id_wb_src_sel;
            id_ex_branch     <= id_branch;
            id_ex_jal        <= id_jal;
            id_ex_jalr       <= id_jalr;
            id_ex_valid      <= if_id_valid;
        end
    end

    // =========================================================================
    // 3. EX (Execute - 执行级)
    // =========================================================================
    // 前推多路选择器 (3-to-1)
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_reg_write;
    reg [31:0] ex_mem_alu_out;

    // 前推多路选择器逻辑 (3-to-1)
    always @(*) begin
        case (forward_a)
            2'b10:   ex_fwd_val_a = ex_mem_alu_out; // EX-EX 前推
            2'b01:   ex_fwd_val_a = wb_final_data;  // MEM-EX 前推
            default: ex_fwd_val_a = id_ex_rs1_data; // 无前推
        endcase
    end

    always @(*) begin
        case (forward_b)
            2'b10:   ex_fwd_val_b = ex_mem_alu_out; // EX-EX 前推
            2'b01:   ex_fwd_val_b = wb_final_data;  // MEM-EX 前推
            default: ex_fwd_val_b = id_ex_rs2_data; // 无前推
        endcase
    end

    // ALU 输入操作数多路选择
    wire [31:0] ex_alu_op_a = (id_ex_alu_src_a) ? id_ex_pc : ex_fwd_val_a;
    wire [31:0] ex_alu_op_b = (id_ex_alu_src_b) ? id_ex_imm : ex_fwd_val_b;

    // 实例化 ALU
    wire [31:0] ex_alu_out;
    /* verilator lint_off UNUSEDSIGNAL */
    wire        ex_alu_zero;      // 分支由专用比较器裁决，此处 zero 信号不接入控制通路
    /* verilator lint_on UNUSEDSIGNAL */
    alu u_alu (
        .alu_op (id_ex_alu_op),
        .op_a   (ex_alu_op_a),
        .op_b   (ex_alu_op_b),
        .alu_out(ex_alu_out),
        .zero   (ex_alu_zero)
    );

    // 分支条件裁决逻辑 (Branch Comparator)
    reg ex_br_cond;
    always @(*) begin
        case (id_ex_funct3)
            3'b000:  ex_br_cond = (ex_fwd_val_a == ex_fwd_val_b);                          // BEQ
            3'b001:  ex_br_cond = (ex_fwd_val_a != ex_fwd_val_b);                          // BNE
            3'b100:  ex_br_cond = ($signed(ex_fwd_val_a) < $signed(ex_fwd_val_b));         // BLT
            3'b101:  ex_br_cond = ($signed(ex_fwd_val_a) >= $signed(ex_fwd_val_b));        // BGE
            3'b110:  ex_br_cond = (ex_fwd_val_a < ex_fwd_val_b);                           // BLTU
            3'b111:  ex_br_cond = (ex_fwd_val_a >= ex_fwd_val_b);                          // BGEU
            default: ex_br_cond = 1'b0;
        endcase
    end

    // 跳转有效与目标计算 (受 id_ex_valid 门控)
    assign branch_taken = id_ex_valid & ((id_ex_branch & ex_br_cond) | id_ex_jal | id_ex_jalr);

    wire [31:0] ex_jump_base = (id_ex_jalr) ? ex_fwd_val_a : id_ex_pc;
    assign branch_target     = (id_ex_jalr) ?
                                ((ex_jump_base + id_ex_imm) & ~32'd1) :
                                (ex_jump_base + id_ex_imm);

    // ---------------- 级间寄存器 3: EX/MEM ----------------
    reg [31:0] ex_mem_pc;
    reg [31:0] ex_mem_rs2_data;
    reg [2:0]  ex_mem_funct3;
    /* verilator lint_off UNUSEDSIGNAL */
    reg        ex_mem_mem_read;   // 访存读地址在 EX 级提前发出，MEM 级保留此信号供后续总线握手使用
    /* verilator lint_on UNUSEDSIGNAL */
    reg        ex_mem_mem_write;
    reg [1:0]  ex_mem_wb_src_sel;
    reg        ex_mem_valid;

    always @(posedge clk) begin
        if (!rst_n || flush_ex_mem) begin
            ex_mem_pc         <= 32'd0;
            ex_mem_alu_out    <= 32'd0;
            ex_mem_rs2_data   <= 32'd0;
            ex_mem_rd         <= 5'd0;
            ex_mem_funct3     <= 3'd0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_wb_src_sel <= 2'd0;
            ex_mem_valid      <= 1'b0;
        end else begin
            ex_mem_pc         <= id_ex_pc;
            ex_mem_alu_out    <= ex_alu_out;
            ex_mem_rs2_data   <= ex_fwd_val_b;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_funct3     <= id_ex_funct3;
            ex_mem_mem_read   <= id_ex_mem_read;
            ex_mem_mem_write  <= id_ex_mem_write;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_wb_src_sel <= id_ex_wb_src_sel;
            ex_mem_valid      <= id_ex_valid;
        end
    end

    // =========================================================================
    // 4. MEM (Memory Access - 访存级)
    // =========================================================================
    // 内存总线仲裁：若 MEM 级是有效 Store，端口属于 Store (ex_mem_alu_out)；
    // 否则若 EX 级是有效 Load，发出读地址 (ex_alu_out)。结构冒险时本拍端口让给 Store，Load 暂停 1 拍。
    assign dmem_addr = (ex_mem_valid & ex_mem_mem_write) ? ex_mem_alu_out : ex_alu_out;
    assign dmem_req  = (ex_mem_valid & ex_mem_mem_write) | (id_ex_valid & id_ex_mem_read & !structural_hazard);

    // ---------------- Store 字节对齐与使能生成 ----------------
    wire [1:0] mem_byte_offset = ex_mem_alu_out[1:0];

    always @(*) begin
        dmem_byte_we = 4'b0000;
        dmem_wdata   = 32'd0;
        if (ex_mem_valid && ex_mem_mem_write) begin
            case (ex_mem_funct3)
                3'b000: begin // SB (Store Byte)
                    case (mem_byte_offset)
                        2'b00: begin dmem_byte_we = 4'b0001; dmem_wdata = {24'd0, ex_mem_rs2_data[7:0]}; end
                        2'b01: begin dmem_byte_we = 4'b0010; dmem_wdata = {16'd0, ex_mem_rs2_data[7:0], 8'd0}; end
                        2'b10: begin dmem_byte_we = 4'b0100; dmem_wdata = {8'd0,  ex_mem_rs2_data[7:0], 16'd0}; end
                        2'b11: begin dmem_byte_we = 4'b1000; dmem_wdata = {ex_mem_rs2_data[7:0], 24'd0}; end
                    endcase
                end
                3'b001: begin // SH (Store Halfword)
                    case (mem_byte_offset[1])
                        1'b0: begin dmem_byte_we = 4'b0011; dmem_wdata = {16'd0, ex_mem_rs2_data[15:0]}; end
                        1'b1: begin dmem_byte_we = 4'b1100; dmem_wdata = {ex_mem_rs2_data[15:0], 16'd0}; end
                    endcase
                end
                3'b010: begin // SW (Store Word)
                    dmem_byte_we = 4'b1111;
                    dmem_wdata   = ex_mem_rs2_data;
                end
                default: begin
                    dmem_byte_we = 4'b0000;
                    dmem_wdata   = 32'd0;
                end
            endcase
        end
    end

    // ---------------- Load 符号扩展与对齐处理 ----------------
    reg [31:0] mem_load_data;
    always @(*) begin
        case (ex_mem_funct3)
            3'b000: begin // LB (Load Byte, 符号扩展)
                case (mem_byte_offset)
                    2'b00: mem_load_data = {{24{dmem_rdata[7]}},  dmem_rdata[7:0]};
                    2'b01: mem_load_data = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
                    2'b10: mem_load_data = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
                    2'b11: mem_load_data = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
                endcase
            end
            3'b100: begin // LBU (Load Byte Unsigned, 零扩展)
                case (mem_byte_offset)
                    2'b00: mem_load_data = {24'd0, dmem_rdata[7:0]};
                    2'b01: mem_load_data = {24'd0, dmem_rdata[15:8]};
                    2'b10: mem_load_data = {24'd0, dmem_rdata[23:16]};
                    2'b11: mem_load_data = {24'd0, dmem_rdata[31:24]};
                endcase
            end
            3'b001: begin // LH (Load Halfword, 符号扩展)
                case (mem_byte_offset[1])
                    1'b0: mem_load_data = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
                    1'b1: mem_load_data = {{16{dmem_rdata[31]}}, dmem_rdata[31:16]};
                endcase
            end
            3'b101: begin // LHU (Load Halfword Unsigned, 零扩展)
                case (mem_byte_offset[1])
                    1'b0: mem_load_data = {16'd0, dmem_rdata[15:0]};
                    1'b1: mem_load_data = {16'd0, dmem_rdata[31:16]};
                endcase
            end
            3'b010: begin // LW (Load Word)
                mem_load_data = dmem_rdata;
            end
            default: mem_load_data = dmem_rdata;
        endcase
    end

    // ---------------- 级间寄存器 4: MEM/WB ----------------
    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_alu_out;
    reg [31:0] mem_wb_load_data;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write;
    reg [1:0]  mem_wb_wb_src_sel;
    reg        mem_wb_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            mem_wb_pc         <= 32'd0;
            mem_wb_alu_out    <= 32'd0;
            mem_wb_load_data  <= 32'd0;
            mem_wb_rd         <= 5'd0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_wb_src_sel <= 2'd0;
            mem_wb_valid      <= 1'b0;
        end else begin
            mem_wb_pc         <= ex_mem_pc;
            mem_wb_alu_out    <= ex_mem_alu_out;
            mem_wb_load_data  <= mem_load_data;
            mem_wb_rd         <= ex_mem_rd;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_wb_src_sel <= ex_mem_wb_src_sel;
            mem_wb_valid      <= ex_mem_valid;
        end
    end

    // =========================================================================
    // 5. WB (Write Back - 写回级)
    // =========================================================================
    assign wb_reg_write = mem_wb_valid & mem_wb_reg_write;
    assign wb_rd_addr   = mem_wb_rd;

    wire [31:0] mem_wb_pc_plus_4 = mem_wb_pc + 32'd4;

    reg [31:0] wb_mux_data;
    always @(*) begin
        case (mem_wb_wb_src_sel)
            2'd0:    wb_mux_data = mem_wb_alu_out;
            2'd1:    wb_mux_data = mem_wb_load_data;
            2'd2:    wb_mux_data = mem_wb_pc_plus_4;
            default: wb_mux_data = mem_wb_alu_out;
        endcase
    end
    assign wb_final_data = wb_mux_data;

    // 提交追踪输出 (用于 DiffTest 和跟踪)
    assign wb_valid = mem_wb_valid;
    assign wb_we    = wb_reg_write & (wb_rd_addr != 5'd0); // 真正写有效寄存器 (非 x0) 时为 1
    assign wb_pc    = mem_wb_pc;
    assign wb_rd    = mem_wb_rd;
    assign wb_wdata = wb_final_data;

    // =========================================================================
    // 6. 控制中枢实例化: Forwarding Unit & Hazard Unit
    // =========================================================================
    forwarding_unit u_forwarding (
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .ex_mem_rd       (ex_mem_rd),
        .ex_mem_reg_write(ex_mem_valid & ex_mem_reg_write),
        .mem_wb_rd       (mem_wb_rd),
        .mem_wb_reg_write(mem_wb_valid & mem_wb_reg_write),
        .forward_a       (forward_a),
        .forward_b       (forward_b)
    );

    hazard_unit u_hazard (
        .if_id_rs1        (id_rs1),
        .if_id_rs2        (id_rs2),
        .id_ex_mem_read   (id_ex_valid & id_ex_mem_read),
        .id_ex_rd         (id_ex_rd),
        .ex_mem_mem_write (ex_mem_valid & ex_mem_mem_write),
        .branch_taken     (branch_taken),
        .jal              (id_ex_valid & id_ex_jal),
        .jalr             (id_ex_valid & id_ex_jalr),
        .stall_pc         (stall_pc),
        .stall_if_id      (stall_if_id),
        .stall_id_ex      (stall_id_ex),
        .flush_if_id      (flush_if_id),
        .flush_id_ex      (flush_id_ex),
        .flush_ex_mem     (flush_ex_mem),
        .structural_hazard(structural_hazard)
    );

    // =========================================================================
    // 7. 性能计数器 (Performance Counters)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            perf_cycle   <= 32'd0;
            perf_instret <= 32'd0;
        end else begin
            perf_cycle <= perf_cycle + 32'd1;
            if (wb_valid) begin
                perf_instret <= perf_instret + 32'd1;
            end
        end
    end

endmodule
`default_nettype wire
