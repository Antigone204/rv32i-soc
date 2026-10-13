`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_core_basic — RV32I 五级流水线完整功能集成自检测试台
//
// 验证目标：
//   1. 基本运算与通用寄存器写入；
//   2. RAW 数据依赖下的 EX-EX 和 MEM-EX 数据前推；
//   3. Load-Use 冲突下的硬件停顿 (Stall) 1 周期与气泡 (Bubble) 注入；
//   4. Store 与 Load 内存交互 (SW / LW)；
//   5. 分支跳转成功时的两级流水线冲刷 (Flush)，确保错误路径指令不写回；
//   6. 观察提交追踪接口 (wb_valid, wb_pc, wb_rd, wb_wdata) 与性能计数器。
// -----------------------------------------------------------------------------
module tb_core_basic;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;

    // 内存总线接口
    wire [31:0] imem_addr;
    wire        imem_req;
    reg  [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_byte_we;
    wire        dmem_req;
    reg  [31:0] dmem_rdata;

    // 追踪接口
    wire        wb_valid;
    wire [31:0] wb_pc;
    wire [4:0]  wb_rd;
    wire [31:0] wb_wdata;
    wire [31:0] perf_cycle;
    wire [31:0] perf_instret;

    // ---------------- 实例化 5 级流水线 CPU 核心 ----------------
    core u_core (
        .clk         (clk),
        .rst_n       (rst_n),
        .imem_addr   (imem_addr),
        .imem_req    (imem_req),
        .imem_rdata  (imem_rdata),
        .dmem_addr   (dmem_addr),
        .dmem_wdata  (dmem_wdata),
        .dmem_byte_we(dmem_byte_we),
        .dmem_req    (dmem_req),
        .dmem_rdata  (dmem_rdata),
        .wb_valid    (wb_valid),
        .wb_pc       (wb_pc),
        .wb_rd       (wb_rd),
        .wb_wdata    (wb_wdata),
        .perf_cycle  (perf_cycle),
        .perf_instret(perf_instret)
    );

    // ---------------- 仿真指令与数据存储器 ----------------
    reg [31:0] imem [0:63];
    reg [31:0] dmem [0:63];

    // 指令读 (纯组合异步读出，模拟单周期指令 RAM)
    always @(*) begin
        if (imem_addr[31:2] < 64)
            imem_rdata = imem[imem_addr[31:2]];
        else
            imem_rdata = 32'h0000_0013; // NOP
    end

    // 数据读写
    always @(*) begin
        if (dmem_addr[31:2] < 64)
            dmem_rdata = dmem[dmem_addr[31:2]];
        else
            dmem_rdata = 32'd0;
    end

    integer k;
    always @(posedge clk) begin
        if (dmem_req && (|dmem_byte_we) && (dmem_addr[31:2] < 64)) begin
            if (dmem_byte_we[0]) dmem[dmem_addr[31:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_byte_we[1]) dmem[dmem_addr[31:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_byte_we[2]) dmem[dmem_addr[31:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_byte_we[3]) dmem[dmem_addr[31:2]][31:24] <= dmem_wdata[31:24];
        end
    end

    // ---------------- 打印提交跟踪日志 ----------------
    always @(posedge clk) begin
        if (rst_n && wb_valid) begin
            $display("  [COMMIT] Cycle=%0d PC=0x%08h W_REG=x%-2d W_DATA=0x%08h (%0d)",
                     perf_cycle, wb_pc, wb_rd, wb_wdata, $signed(wb_wdata));
        end
    end

    // ---------------- 测试程序加载与断言校验 ----------------
    integer errors = 0;

    initial begin
        // 初始化存储器为 NOP
        for (k = 0; k < 64; k = k + 1) begin
            imem[k] = 32'h0000_0013;
            dmem[k] = 32'd0;
        end

        // 汇编程序硬编码载入：
        // PC=0x00: addi x1, x0, 10           (x1 = 10)
        imem[0]  = 32'h00a00093;
        // PC=0x04: addi x2, x1, 20           (x2 = 30，依赖 x1，触发 EX-EX 前推)
        imem[1]  = 32'h01408113;
        // PC=0x08: add  x3, x2, x1           (x3 = 40，同时依赖 x2 和 x1，双路前推)
        imem[2]  = 32'h001101b3;
        // PC=0x0C: sw   x3, 0(x0)            (将 40 存入 dmem[0])
        imem[3]  = 32'h00302023;
        // PC=0x10: lw   x4, 0(x0)            (从 dmem[0] 读出 40 到 x4)
        imem[4]  = 32'h00002203;
        // PC=0x14: addi x5, x4, 5            (x5 = 45，紧跟 Load，必须触发 Load-Use 停顿 1 拍)
        imem[5]  = 32'h00520293;
        // PC=0x18: beq  x1, x2, +16          (10 != 30，不跳)
        imem[6]  = 32'h00208863;
        // PC=0x1C: addi x6, x0, 100          (x6 = 100)
        imem[7]  = 32'h06400313;
        // PC=0x20: beq  x1, x1, +12          (10 == 10，跳转到 0x2C！)
        imem[8]  = 32'h00108663;
        // PC=0x24: addi x6, x0, 999          (位于跳转延迟槽中，必须被冲刷！不能写回 x6)
        imem[9]  = 32'h3e700313;
        // PC=0x28: addi x6, x0, 888          (同上，必须被冲刷！)
        imem[10] = 32'h37800313;
        // PC=0x2C: addi x7, x0, 1            (跳转目标！x7 = 1 表示成功)
        imem[11] = 32'h00100393;

        // 启动复位
        #15 rst_n = 1'b1;

        // 运行 40 个时钟周期，等待程序流水执行完毕
        #400;

        $display("\n================ 结果状态核验 ================");
        // 验证各通用寄存器最终状态 (通过读取 regfile 内部 regs)
        // x1 应该为 10
        if (u_core.u_regfile.regs[1] !== 32'd10) begin
            $display("FAIL: x1 = %0d (exp 10)", u_core.u_regfile.regs[1]);
            errors = errors + 1;
        end else begin
            $display("PASS: x1 = 10 (基础立即数运算)");
        end

        // x2 应该为 30 (验证了 EX-EX 前推)
        if (u_core.u_regfile.regs[2] !== 32'd30) begin
            $display("FAIL: x2 = %0d (exp 30)", u_core.u_regfile.regs[2]);
            errors = errors + 1;
        end else begin
            $display("PASS: x2 = 30 (EX-EX 数据前推生效)");
        end

        // x3 应该为 40 (验证了双路前推)
        if (u_core.u_regfile.regs[3] !== 32'd40) begin
            $display("FAIL: x3 = %0d (exp 40)", u_core.u_regfile.regs[3]);
            errors = errors + 1;
        end else begin
            $display("PASS: x3 = 40 (双路前推同时生效)");
        end

        // dmem[0] 应该为 40 (验证了 SW)
        if (dmem[0] !== 32'd40) begin
            $display("FAIL: dmem[0] = %0d (exp 40)", dmem[0]);
            errors = errors + 1;
        end else begin
            $display("PASS: dmem[0] = 40 (SW 内存写入成功)");
        end

        // x4 应该为 40 (验证了 LW)
        if (u_core.u_regfile.regs[4] !== 32'd40) begin
            $display("FAIL: x4 = %0d (exp 40)", u_core.u_regfile.regs[4]);
            errors = errors + 1;
        end else begin
            $display("PASS: x4 = 40 (LW 内存加载成功)");
        end

        // x5 应该为 45 (验证了 Load-Use 停顿 1 拍并前推)
        if (u_core.u_regfile.regs[5] !== 32'd45) begin
            $display("FAIL: x5 = %0d (exp 45)", u_core.u_regfile.regs[5]);
            errors = errors + 1;
        end else begin
            $display("PASS: x5 = 45 (Load-Use 停顿与气泡注入生效)");
        end

        // x6 应该保持为 100，绝不能被分支阴影里的 999 污染 (验证了 Branch Flush)
        if (u_core.u_regfile.regs[6] !== 32'd100) begin
            $display("FAIL: x6 = %0d (exp 100, 被错误分支指令污染！)", u_core.u_regfile.regs[6]);
            errors = errors + 1;
        end else begin
            $display("PASS: x6 = 100 (分支冲刷生效，错误路径指令被成功废弃)");
        end

        // x7 应该为 1 (验证了跳转成功着陆)
        if (u_core.u_regfile.regs[7] !== 32'd1) begin
            $display("FAIL: x7 = %0d (exp 1)", u_core.u_regfile.regs[7]);
            errors = errors + 1;
        end else begin
            $display("PASS: x7 = 1 (跳转目标正常执行)");
        end

        $display("----------------------------------------------");
        $display("累计提交指令数: %0d", perf_instret);
        $display("累计运行周期数: %0d", perf_cycle);

        if (errors == 0) begin
            $display("\n>>> 5-STAGE RV32I CORE BASIC VERIFICATION PASSED <<<\n");
        end else begin
            $display("\n>>> %0d VERIFICATION FAILED <<<\n", errors);
        end
        $finish;
    end

endmodule
`default_nettype wire
