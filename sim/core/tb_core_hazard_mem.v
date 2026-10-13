`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_core_hazard_mem — SW 紧跟 LW 结构冒险专项定向验证测试台
//
// 验证目标：
//   1. SW 紧跟 LW 访问不同地址：
//      - sw x3, 0(x0) 将 40 存入 dmem[0]
//      - lw x4, 4(x0) 从 dmem[1] 读出（初始为 0）
//      - 验证：dmem[0] 成功写入 40，dmem[1] 保持 0，x4 成功读出 0（绝不被 SW 的 40 污染）
//   2. SW 紧跟 LW 访问相同地址：
//      - sw x6, 8(x0) 将 88 存入 dmem[2]
//      - lw x7, 8(x0) 从 dmem[2] 读出
//      - 验证：x7 成功读出新写入的 88，x8 (x7 + 2) 正确计算为 90
//   3. 采用真实 FPGA BRAM 同步时钟读出模型，不使用任何旁路作弊逻辑。
// -----------------------------------------------------------------------------
module tb_core_hazard_mem;
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
    wire        wb_we;
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
        .wb_we       (wb_we),
        .wb_pc       (wb_pc),
        .wb_rd       (wb_rd),
        .wb_wdata    (wb_wdata),
        .perf_cycle  (perf_cycle),
        .perf_instret(perf_instret)
    );

    // ---------------- 仿真指令与数据存储器 ----------------
    reg [31:0] imem [0:63];
    reg [31:0] dmem [0:63];

    // 指令读 (标准同步时钟读出，模拟 FPGA BRAM 1 拍读延迟)
    always @(posedge clk) begin
        if (imem_addr[31:2] < 64)
            imem_rdata <= imem[imem_addr[31:2]];
        else
            imem_rdata <= 32'h0000_0013; // NOP
    end

    // 数据读 (真实 FPGA BRAM 同步时钟读出，绝无测试旁路作弊)
    always @(posedge clk) begin
        if (dmem_addr[31:2] < 64)
            dmem_rdata <= dmem[dmem_addr[31:2]];
        else
            dmem_rdata <= 32'd0;
    end

    // 数据写 (同步时钟写入)
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
            if (wb_we) begin
                $display("  [COMMIT] Cycle=%0d PC=0x%08h W_REG=x%-2d W_DATA=0x%08h (%0d)",
                         perf_cycle, wb_pc, wb_rd, wb_wdata, $signed(wb_wdata));
            end else begin
                $display("  [COMMIT] Cycle=%0d PC=0x%08h",
                         perf_cycle, wb_pc);
            end
        end
    end

    // ---------------- 测试程序加载与断言校验 ----------------
    integer k;
    integer errors = 0;

    initial begin
        for (k = 0; k < 64; k = k + 1) begin
            imem[k] = 32'h0000_0013;
            dmem[k] = 32'd0;
        end

        // 汇编指令构建：
        // 【Case 1: SW 紧跟 LW 且地址不同】
        // PC=0x00: addi x3, x0, 40       (x3 = 40)
        imem[0] = 32'h02800193;
        // PC=0x04: sw   x3, 0(x0)        (Store 40 到 dmem[0])
        imem[1] = 32'h00302023;
        // PC=0x08: lw   x4, 4(x0)        (紧跟 SW，从 dmem[1] 读出，预期为 0)
        imem[2] = 32'h00402203;
        // PC=0x0C: addi x5, x4, 1        (依赖 x4，验证 Load-Use 停顿)
        imem[3] = 32'h00120293;

        // 【Case 2: SW 紧跟 LW 且地址相同】
        // PC=0x10: addi x6, x0, 88       (x6 = 88)
        imem[4] = 32'h05800313;
        // PC=0x14: sw   x6, 8(x0)        (Store 88 到 dmem[2])
        imem[5] = 32'h00602423;
        // PC=0x18: lw   x7, 8(x0)        (紧跟 SW，从同一地址 dmem[2] 读出，预期读到 88)
        imem[6] = 32'h00802383;
        // PC=0x1C: addi x8, x7, 2        (x8 = 88 + 2 = 90)
        imem[7] = 32'h00238413;

        // 启动复位
        #15 rst_n = 1'b1;

        // 等待最后一条指令 PC=0x1C 提交
        @(posedge clk);
        while (!(wb_valid && wb_pc == 32'h0000_001c)) begin
            @(posedge clk);
        end
        #1;

        $display("\n================ SW-LW 结构冒险定向核验 ================");

        // 核验 Case 1 (地址不同)
        if (dmem[0] !== 32'd40) begin
            $display("FAIL [DIFF_ADDR]: dmem[0] = %0d (exp 40, SW 数据写入错误地址！)", dmem[0]);
            errors = errors + 1;
        end else begin
            $display("PASS [DIFF_ADDR]: dmem[0] = 40 (SW 准确写入指定地址 0)");
        end

        if (dmem[1] !== 32'd0) begin
            $display("FAIL [DIFF_ADDR]: dmem[1] = %0d (exp 0, 被错误覆盖！)", dmem[1]);
            errors = errors + 1;
        end else begin
            $display("PASS [DIFF_ADDR]: dmem[1] = 0 (dmem[1] 未被错误污染)");
        end

        if (u_core.u_regfile.regs[4] !== 32'd0) begin
            $display("FAIL [DIFF_ADDR]: x4 = %0d (exp 0, 读回错误脏数据！)", u_core.u_regfile.regs[4]);
            errors = errors + 1;
        end else begin
            $display("PASS [DIFF_ADDR]: x4 = 0 (LW 准确读回目标地址数据 0)");
        end

        if (u_core.u_regfile.regs[5] !== 32'd1) begin
            $display("FAIL [DIFF_ADDR]: x5 = %0d (exp 1)", u_core.u_regfile.regs[5]);
            errors = errors + 1;
        end else begin
            $display("PASS [DIFF_ADDR]: x5 = 1 (Case 1 Load-Use 运算正确)");
        end

        // 核验 Case 2 (地址相同)
        if (dmem[2] !== 32'd88) begin
            $display("FAIL [SAME_ADDR]: dmem[2] = %0d (exp 88)", dmem[2]);
            errors = errors + 1;
        end else begin
            $display("PASS [SAME_ADDR]: dmem[2] = 88 (SW 写入成功)");
        end

        if (u_core.u_regfile.regs[7] !== 32'd88) begin
            $display("FAIL [SAME_ADDR]: x7 = %0d (exp 88, 同地址紧跟读未能读出最新写入值！)", u_core.u_regfile.regs[7]);
            errors = errors + 1;
        end else begin
            $display("PASS [SAME_ADDR]: x7 = 88 (同地址 LW 成功读出刚写入的最新数据)");
        end

        if (u_core.u_regfile.regs[8] !== 32'd90) begin
            $display("FAIL [SAME_ADDR]: x8 = %0d (exp 90)", u_core.u_regfile.regs[8]);
            errors = errors + 1;
        end else begin
            $display("PASS [SAME_ADDR]: x8 = 90 (Case 2 Load-Use 运算正确)");
        end

        $display("---------------------------------------------------------");
        $display("累计提交指令数: %0d", perf_instret);
        $display("累计运行周期数: %0d", perf_cycle);

        if (errors == 0) begin
            $display("\n>>> SW-LW HAZARD DIRECTED VERIFICATION PASSED <<<\n");
        end else begin
            $display("\n>>> %0d VERIFICATION FAILED <<<\n", errors);
        end
        $finish;
    end

endmodule
`default_nettype wire
