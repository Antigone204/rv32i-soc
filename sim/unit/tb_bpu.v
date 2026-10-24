`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_bpu — BPU (Branch Prediction Unit) 独立单元测试
//
// 验证目标：
//   1. 初始冷启动未命中 (pred_taken_o == 0)；
//   2. 条件分支首次 Taken 分配表项后为 Weakly Taken (2'b10)，下一次查询命中预测 Taken；
//   3. 连续 Taken 饱和到 2'b11 (Strongly Taken)，偶发 1 次 Not-Taken 保持预测 Taken (抗颠簸)；
//   4. 连续 2 次 Not-Taken 退化到 2'b01 (Weakly Not-Taken)，预测变为 Not-Taken；
//   5. 无条件跳转 (upd_is_uncond_i = 1) 分配后恒预测 Taken；
//   6. 别名冲突与 Tag 替换验证 (相同 Index，不同 Tag)。
// -----------------------------------------------------------------------------
module tb_bpu;

    reg         clk;
    reg         rst_n;

    // IF 级查询
    reg  [31:0] if_pc;
    wire        pred_taken;
    wire [31:0] pred_target;

    // EX 级更新
    reg         upd_valid;
    reg  [31:0] upd_pc;
    reg         upd_is_uncond;
    reg         upd_taken;
    reg  [31:0] upd_target;

    // 例化待测 BPU (INDEX_BITS = 6, 64 项)
    bpu #(
        .INDEX_BITS(6)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .if_pc_i        (if_pc),
        .pred_taken_o   (pred_taken),
        .pred_target_o  (pred_target),
        .upd_valid_i    (upd_valid),
        .upd_pc_i       (upd_pc),
        .upd_is_uncond_i(upd_is_uncond),
        .upd_taken_i    (upd_taken),
        .upd_target_i   (upd_target)
    );

    // 时钟生成：周期 10ns
    always #5 clk = ~clk;

    // 测试流程
    initial begin
        clk           = 0;
        rst_n         = 0;
        if_pc         = 32'd0;
        upd_valid     = 0;
        upd_pc        = 32'd0;
        upd_is_uncond = 0;
        upd_taken     = 0;
        upd_target    = 32'd0;

        // 复位 2 拍
        #20;
        @(negedge clk);
        rst_n = 1;
        @(posedge clk);

        // ---------------------------------------------------------------------
        // 测试用例 1: 初始冷启动未命中
        // ---------------------------------------------------------------------
        $display("[TEST 1] Testing Cold Miss...");
        if_pc = 32'h0000_1000;
        #1;
        if (pred_taken !== 1'b0) begin
            $display("FAIL [TEST 1]: Expected pred_taken=0, got %b", pred_taken);
            $fatal;
        end
        $display("PASS [TEST 1]: Cold Miss verified (pred_taken=0).");

        // ---------------------------------------------------------------------
        // 测试用例 2: 条件分支首次 Taken 分配表项 (Weakly Taken 2'b10)
        // ---------------------------------------------------------------------
        $display("[TEST 2] Testing First Taken Allocation (Weakly Taken)...");
        @(negedge clk);
        upd_valid     = 1;
        upd_pc        = 32'h0000_1000;
        upd_is_uncond = 0;
        upd_taken     = 1;
        upd_target    = 32'h0000_2000;
        @(posedge clk);
        #1;
        upd_valid     = 0;

        // 查询刚刚分配的表项
        if_pc = 32'h0000_1000;
        #1;
        if (pred_taken !== 1'b1 || pred_target !== 32'h0000_2000) begin
            $display("FAIL [TEST 2]: Expected pred_taken=1, target=0x2000, got taken=%b, target=0x%08x",
                     pred_taken, pred_target);
            $fatal;
        end
        $display("PASS [TEST 2]: First Taken Allocation verified (pred_taken=1, target=0x%08x).", pred_target);

        // ---------------------------------------------------------------------
        // 测试用例 3: 连续 Taken 饱和至 2'b11 (Strongly Taken)，偶发 1 次 Not-Taken 验证抗颠簸
        // ---------------------------------------------------------------------
        $display("[TEST 3] Testing Saturation to 2'b11 & Anti-Thrashing on 1 Not-Taken...");
        @(negedge clk);
        upd_valid     = 1;
        upd_pc        = 32'h0000_1000;
        upd_is_uncond = 0;
        upd_taken     = 1;
        upd_target    = 32'h0000_2000;
        @(posedge clk);
        #1;
        upd_valid     = 0;

        // 此时计数器应为 2'b11 (Strongly Taken)
        // 模拟循环最后一次退出：Not-Taken
        @(negedge clk);
        upd_valid     = 1;
        upd_pc        = 32'h0000_1000;
        upd_is_uncond = 0;
        upd_taken     = 0;
        upd_target    = 32'h0000_2000;
        @(posedge clk);
        #1;
        upd_valid     = 0;

        // 偶发 1 次 Not-Taken 后计数器退化为 2'b10，但高位仍为 1，应保持预测 Taken！
        if_pc = 32'h0000_1000;
        #1;
        if (pred_taken !== 1'b1) begin
            $display("FAIL [TEST 3]: Expected pred_taken=1 after 1 Not-Taken (Anti-thrashing), got %b", pred_taken);
            $fatal;
        end
        $display("PASS [TEST 3]: Anti-thrashing verified (still pred_taken=1).");

        // ---------------------------------------------------------------------
        // 测试用例 4: 连续 2 次 Not-Taken 退化到 2'b01，预测翻转为 Not-Taken
        // ---------------------------------------------------------------------
        $display("[TEST 4] Testing Degradation to 2'b01 (Weakly Not-Taken)...");
        @(negedge clk);
        upd_valid     = 1;
        upd_pc        = 32'h0000_1000;
        upd_is_uncond = 0;
        upd_taken     = 0;
        upd_target    = 32'h0000_2000;
        @(posedge clk);
        #1;
        upd_valid     = 0;

        // 再次查询，计数器退到 2'b01，pred_taken 应变为 0
        if_pc = 32'h0000_1000;
        #1;
        if (pred_taken !== 1'b0) begin
            $display("FAIL [TEST 4]: Expected pred_taken=0 after 2 consecutive Not-Takens, got %b", pred_taken);
            $fatal;
        end
        $display("PASS [TEST 4]: Degradation to Weakly Not-Taken verified (pred_taken=0).");

        // ---------------------------------------------------------------------
        // 测试用例 5: 无条件跳转 (JAL/JALR) 分配与恒预测 Taken
        // ---------------------------------------------------------------------
        $display("[TEST 5] Testing Unconditional Jump Allocation...");
        @(negedge clk);
        upd_valid     = 1;
        upd_pc        = 32'h0000_3000;
        upd_is_uncond = 1;
        upd_taken     = 1;
        upd_target    = 32'h0000_4000;
        @(posedge clk);
        #1;
        upd_valid     = 0;

        if_pc = 32'h0000_3000;
        #1;
        if (pred_taken !== 1'b1 || pred_target !== 32'h0000_4000) begin
            $display("FAIL [TEST 5]: Expected unconditional jump pred_taken=1, target=0x4000, got taken=%b, target=0x%08x",
                     pred_taken, pred_target);
            $fatal;
        end
        $display("PASS [TEST 5]: Unconditional jump verified (pred_taken=1, target=0x%08x).", pred_target);

        // ---------------------------------------------------------------------
        // 测试用例 6: Tag 冲突与表项替换验证 (相同 Index, 不同 Tag)
        // ---------------------------------------------------------------------
        $display("[TEST 6] Testing Tag Mismatch & Direct-Mapped Replacement...");
        // 0x0000_1000 与 0x0004_1000 在 INDEX_BITS=6 时具有相同的 index (bits[7:2] = 0x00)
        // 但 Tag (bits[31:8]) 不同：0x000010 vs 0x000410
        if_pc = 32'h0004_1000;
        #1;
        if (pred_taken !== 1'b0) begin
            $display("FAIL [TEST 6]: Expected Tag mismatch cold miss, got pred_taken=%b", pred_taken);
            $fatal;
        end

        // 训练 0x0004_1000 发生 Taken 跳转，替换原有表项
        @(negedge clk);
        upd_valid     = 1;
        upd_pc        = 32'h0004_1000;
        upd_is_uncond = 0;
        upd_taken     = 1;
        upd_target    = 32'h0000_8888;
        @(posedge clk);
        #1;
        upd_valid     = 0;

        // 查询新 PC
        if_pc = 32'h0004_1000;
        #1;
        if (pred_taken !== 1'b1 || pred_target !== 32'h0000_8888) begin
            $display("FAIL [TEST 6]: Expected new Tag hit with target 0x8888, got taken=%b, target=0x%08x",
                     pred_taken, pred_target);
            $fatal;
        end

        // 再次查询老 PC (0x0000_1000)，已被驱逐，应出现 Tag 失配 (pred_taken=0)
        if_pc = 32'h0000_1000;
        #1;
        if (pred_taken !== 1'b0) begin
            $display("FAIL [TEST 6]: Expected old PC evicted (pred_taken=0), got %b", pred_taken);
            $fatal;
        end
        $display("PASS [TEST 6]: Direct-Mapped Tag replacement verified.");

        $display("\n>>> ALL BPU TESTS PASSED <<<\n");
        $finish;
    end

endmodule
`default_nettype wire
