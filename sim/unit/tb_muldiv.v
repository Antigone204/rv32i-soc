`timescale 1ns / 1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_muldiv — RV32M 硬件乘除法单元独立单元测试
//
// 覆盖：
//   - 全部 8 条指令 (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU)
//   - 正负数、极值大数、截断
//   - RISC-V 官方边界：除以 0、有符号 -2^31 / -1 溢出
//   - 连续两条背靠背 (Back-to-Back) 乘除法指令无缝衔接
//   - 流水线冲刷 (flush) 中断正在进行的除法
// -----------------------------------------------------------------------------
module tb_muldiv;

    reg         clk;
    reg         rst_n;
    reg         valid_i;
    reg         flush_i;
    reg  [2:0]  funct3_i;
    reg  [31:0] op_a_i;
    reg  [31:0] op_b_i;
    wire        busy_o;
    wire        done_o;
    wire [31:0] result_o;

    // 实例化被测模块
    muldiv u_dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .valid_i (valid_i),
        .flush_i (flush_i),
        .funct3_i(funct3_i),
        .op_a_i  (op_a_i),
        .op_b_i  (op_b_i),
        .busy_o  (busy_o),
        .done_o  (done_o),
        .result_o(result_o)
    );

    // 100 MHz 时钟 (周期 10ns)
    always #5 clk = ~clk;

    // 任务：执行单条指令并校验结果与周期
    task automatic check_op(
        input [2:0]  f3,
        input [31:0] a,
        input [31:0] b,
        input [31:0] expected,
        input [255:0] name
    );
        integer cycles;
        begin
            @(negedge clk);
            valid_i  = 1'b1;
            flush_i  = 1'b0;
            funct3_i = f3;
            op_a_i   = a;
            op_b_i   = b;

            // 当拍组合 busy 必须置 1
            #1;
            if (!busy_o) begin
                $display("[FAIL] %0s: busy_o should be 1 combinationally on valid_i=1", name);
                $finish;
            end

            cycles = 0;
            @(posedge clk);
            while (!done_o) begin
                cycles = cycles + 1;
                if (cycles > 40) begin
                    $display("[FAIL] %0s: Timeout waiting for done_o!", name);
                    $finish;
                end
                @(posedge clk);
            end

            // 采样完成当拍结果与 busy_o 状态
            if (busy_o !== 1'b0) begin
                $display("[FAIL] %0s: busy_o must be 0 when done_o=1!", name);
                $finish;
            end

            if (result_o !== expected) begin
                $display("[FAIL] %0s: a=0x%08x, b=0x%08x -> got 0x%08x, expected 0x%08x",
                         name, a, b, result_o, expected);
                $finish;
            end

            $display("PASS [%0s] a=0x%08x b=0x%08x -> 0x%08x (%0d cycles)",
                     name, a, b, result_o, cycles);

            // 下一拍撤销 valid
            @(negedge clk);
            valid_i = 1'b0;
            @(posedge clk);
        end
    endtask

    initial begin
        clk      = 0;
        rst_n    = 0;
        valid_i  = 0;
        flush_i  = 0;
        funct3_i = 0;
        op_a_i   = 0;
        op_b_i   = 0;

        // 复位 3 拍
        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        $display("=== STARTING MULDIV UNIT TESTS ===");

        // ---------------------------------------------------------------------
        // 1. MUL 测试 (低 32 位积)
        // ---------------------------------------------------------------------
        check_op(3'b000, 32'd10, 32'd30, 32'd300, "MUL_POS_POS");
        check_op(3'b000, 32'd20, -32'd5, -32'd100, "MUL_POS_NEG");
        check_op(3'b000, -32'd15, -32'd4, 32'd60, "MUL_NEG_NEG");
        check_op(3'b000, 32'h12345678, 32'h00000010, 32'h23456780, "MUL_TRUNC");
        check_op(3'b000, 32'd0, 32'hdeadbeef, 32'd0, "MUL_ZERO");

        // ---------------------------------------------------------------------
        // 2. MULH 测试 (有符号 x 有符号高 32 位)
        // ---------------------------------------------------------------------
        check_op(3'b001, -32'd2, 32'd3, -32'd1, "MULH_NEG_POS"); // -6 -> high is -1 (0xFFFFFFFF)
        check_op(3'b001, 32'h7fffffff, 32'h7fffffff, 32'h3fffffff, "MULH_MAX_POS");
        check_op(3'b001, 32'h80000000, 32'h80000000, 32'h40000000, "MULH_MIN_NEG");
        check_op(3'b001, -32'd1, -32'd1, 32'd0, "MULH_NEG1_NEG1");

        // ---------------------------------------------------------------------
        // 3. MULHSU 测试 (有符号 x 无符号高 32 位)
        // ---------------------------------------------------------------------
        check_op(3'b010, -32'd1, 32'd2, -32'd1, "MULHSU_NEG1_2");
        check_op(3'b010, -32'd1, 32'h80000000, -32'd1, "MULHSU_NEG1_MAXU");
        check_op(3'b010, 32'd2, 32'h80000000, 32'd1, "MULHSU_2_2P31");
        check_op(3'b010, -32'd2, 32'hffffffff, -32'd2, "MULHSU_NEG2_MAXU"); // -2*(2^32-1) = -2^33 + 2 -> high 32 is -2 (0xFFFFFFFE)

        // ---------------------------------------------------------------------
        // 4. MULHU 测试 (无符号 x 无符号高 32 位)
        // ---------------------------------------------------------------------
        check_op(3'b011, 32'hffffffff, 32'hffffffff, 32'hfffffffe, "MULHU_MAXU_MAXU");
        check_op(3'b011, 32'h80000000, 32'h80000000, 32'h40000000, "MULHU_2P31_2P31");
        check_op(3'b011, 32'd100, 32'd200, 32'd0, "MULHU_SMALL");

        // ---------------------------------------------------------------------
        // 5. DIV 测试 (有符号商)
        // ---------------------------------------------------------------------
        check_op(3'b100, 32'd20, 32'd3, 32'd6, "DIV_POS_POS");
        check_op(3'b100, -32'd20, 32'd3, -32'd6, "DIV_NEG_POS");
        check_op(3'b100, 32'd20, -32'd3, -32'd6, "DIV_POS_NEG");
        check_op(3'b100, -32'd20, -32'd3, 32'd6, "DIV_NEG_NEG");
        check_op(3'b100, 32'd123, 32'd0, 32'hffffffff, "DIV_BY_ZERO");
        check_op(3'b100, 32'h80000000, 32'hffffffff, 32'h80000000, "DIV_OVERFLOW");

        // ---------------------------------------------------------------------
        // 6. DIVU 测试 (无符号商)
        // ---------------------------------------------------------------------
        check_op(3'b101, 32'd20, 32'd3, 32'd6, "DIVU_POS_POS");
        check_op(3'b101, 32'hffffffff, 32'd2, 32'h7fffffff, "DIVU_MAXU_2");
        check_op(3'b101, 32'h80000000, 32'hffffffff, 32'd0, "DIVU_2P31_MAXU");
        check_op(3'b101, 32'd123, 32'd0, 32'hffffffff, "DIVU_BY_ZERO");

        // ---------------------------------------------------------------------
        // 7. REM 测试 (有符号余数，符号与被除数一致)
        // ---------------------------------------------------------------------
        check_op(3'b110, 32'd20, 32'd3, 32'd2, "REM_POS_POS");
        check_op(3'b110, -32'd20, 32'd3, -32'd2, "REM_NEG_POS");
        check_op(3'b110, 32'd20, -32'd3, 32'd2, "REM_POS_NEG");
        check_op(3'b110, -32'd20, -32'd3, -32'd2, "REM_NEG_NEG");
        check_op(3'b110, 32'd123, 32'd0, 32'd123, "REM_BY_ZERO");
        check_op(3'b110, 32'h80000000, 32'hffffffff, 32'd0, "REM_OVERFLOW");

        // ---------------------------------------------------------------------
        // 8. REMU 测试 (无符号余数)
        // ---------------------------------------------------------------------
        check_op(3'b111, 32'd20, 32'd3, 32'd2, "REMU_POS_POS");
        check_op(3'b111, 32'hffffffff, 32'd10, 32'd5, "REMU_MAXU_10");
        check_op(3'b111, 32'h80000000, 32'hffffffff, 32'h80000000, "REMU_2P31_MAXU");
        check_op(3'b111, 32'd123, 32'd0, 32'd123, "REMU_BY_ZERO");

        // ---------------------------------------------------------------------
        // 9. 背靠背 (Back-to-Back) 连续乘除法测试 (无空闲拍)
        // ---------------------------------------------------------------------
        $display("--- Testing Back-to-Back Consecutive Operations ---");
        @(negedge clk);
        // 指令 1: MUL 7 * 8 = 56
        valid_i  = 1'b1;
        funct3_i = 3'b000;
        op_a_i   = 32'd7;
        op_b_i   = 32'd8;

        @(posedge clk);
        // 等待第 1 拍完成 (done_o = 1)
        while (!done_o) @(posedge clk);
        if (result_o !== 32'd56) begin
            $display("[FAIL] Back-to-back 1st MUL mismatch: got %0d, expected 56", result_o);
            $finish;
        end

        // 在 done_o 当拍的下降沿无缝送入指令 2: MUL 9 * 9 = 81
        @(negedge clk);
        valid_i  = 1'b1;
        funct3_i = 3'b000;
        op_a_i   = 32'd9;
        op_b_i   = 32'd9;

        @(posedge clk);
        // 指令 2 应该立即启动并在一拍后完成
        while (!done_o) @(posedge clk);
        if (result_o !== 32'd81) begin
            $display("[FAIL] Back-to-back 2nd MUL mismatch: got %0d, expected 81", result_o);
            $finish;
        end

        // 在 done_o 当拍的下降沿无缝送入指令 3: DIV 100 / 10 = 10
        @(negedge clk);
        valid_i  = 1'b1;
        funct3_i = 3'b100;
        op_a_i   = 32'd100;
        op_b_i   = 32'd10;

        @(posedge clk);
        while (!done_o) @(posedge clk);
        if (result_o !== 32'd10) begin
            $display("[FAIL] Back-to-back 3rd DIV mismatch: got %0d, expected 10", result_o);
            $finish;
        end

        @(negedge clk);
        valid_i = 1'b0;
        @(posedge clk);
        $display("PASS [BACK_TO_BACK_SUCCESS]");

        // ---------------------------------------------------------------------
        // 10. 流水线冲刷 (Flush) 中断测试
        // ---------------------------------------------------------------------
        $display("--- Testing Flush during Division ---");
        @(negedge clk);
        valid_i  = 1'b1;
        funct3_i = 3'b100;
        op_a_i   = 32'd1000000;
        op_b_i   = 32'd3;

        // 让除法运行 5 拍
        repeat (5) @(posedge clk);
        if (!busy_o) begin
            $display("[FAIL] Division should be busy!");
            $finish;
        end

        // 注入 flush
        @(negedge clk);
        flush_i = 1'b1;
        valid_i = 1'b0;
        #1;
        if (busy_o !== 1'b0) begin
            $display("[FAIL] busy_o must drop to 0 immediately on flush_i=1!");
            $finish;
        end

        @(posedge clk);
        @(negedge clk);
        flush_i = 1'b0;
        #1;
        if (busy_o !== 1'b0 || done_o !== 1'b0) begin
            $display("[FAIL] State must be IDLE and not done after flush!");
            $finish;
        end
        $display("PASS [FLUSH_SUCCESS]");

        repeat (2) @(posedge clk);
        $display("\n>>> ALL MULDIV TESTS PASSED <<<");
        $finish;
    end

endmodule
`default_nettype wire
