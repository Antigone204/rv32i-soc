`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_wb_mac_acc — Wishbone B4 4 路 SIMD INT8 乘累加硬件加速器独立单元测试
//
// 验证覆盖：
//   1. 寄存器复位默认值检查；
//   2. ACC_CTRL 清零累加器与计数器功能；
//   3. ACC_RESULT 直接预置偏置 (Bias) 及 ACC_RELU 负数截断验证；
//   4. 连续有符号 INT8 乘累加极限边界计算 (-128 * -128, -128 * 127 等)；
//   5. 固定 ACC_OPA 连续写入 ACC_OPB_TRIG (权重复用 / 广播模式)；
//   6. ACC_COUNT 计数准确性与 ACC_RELU 零延迟激活读出校验。
// -----------------------------------------------------------------------------
module tb_wb_mac_acc;

    reg clk = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk; // 100 MHz 仿真时钟

    // Wishbone Master 驱动信号
    reg         wbs_cyc   = 1'b0;
    reg         wbs_stb   = 1'b0;
    reg         wbs_we    = 1'b0;
    reg  [31:0] wbs_adr   = 32'd0;
    reg  [31:0] wbs_dat_w = 32'd0;
    reg  [3:0]  wbs_sel   = 4'hF;
    wire [31:0] wbs_dat_r;
    wire        wbs_ack;

    // 例化 DUT
    wb_mac_acc u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .wbs_cyc_i(wbs_cyc),
        .wbs_stb_i(wbs_stb),
        .wbs_we_i (wbs_we),
        .wbs_adr_i(wbs_adr),
        .wbs_sel_i(wbs_sel),
        .wbs_dat_i(wbs_dat_w),
        .wbs_dat_o(wbs_dat_r),
        .wbs_ack_o(wbs_ack)
    );

    // 地址映射常量 (基地址 0x2000_0000)
    localparam [31:0] ACC_CTRL     = 32'h2000_0000;
    localparam [31:0] ACC_OPA      = 32'h2000_0004;
    localparam [31:0] ACC_OPB_TRIG = 32'h2000_0008;
    localparam [31:0] ACC_RESULT   = 32'h2000_000C;
    localparam [31:0] ACC_RELU     = 32'h2000_0010;
    localparam [31:0] ACC_COUNT    = 32'h2000_0014;

    // Wishbone 单次同步读 (1 拍选通，与 tb_wb_uart 对齐)
    task wb_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            wbs_cyc <= 1'b1;
            wbs_stb <= 1'b1;
            wbs_we  <= 1'b0;
            wbs_adr <= addr;
            @(posedge clk);
            wbs_cyc <= 1'b0;
            wbs_stb <= 1'b0;
            #1;
            data = wbs_dat_r;
        end
    endtask

    // Wishbone 单次同步写 (1 拍选通，与 tb_wb_uart 对齐)
    task wb_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            wbs_cyc   <= 1'b1;
            wbs_stb   <= 1'b1;
            wbs_we    <= 1'b1;
            wbs_adr   <= addr;
            wbs_dat_w <= data;
            @(posedge clk);
            wbs_cyc   <= 1'b0;
            wbs_stb   <= 1'b0;
            wbs_we    <= 1'b0;
        end
    endtask

    reg [31:0] rdata;
    integer pass_count = 0;

    initial begin
        $display("[INFO] Starting tb_wb_mac_acc verification...");
        #20;
        rst_n = 1'b1;
        #20;

        // =====================================================================
        // Test 1: 复位默认值与 ACC_CTRL 清零验证
        // =====================================================================
        $display("[TEST 1] Reset default values & ACC_CTRL clear...");
        wb_read(ACC_CTRL, rdata);
        if (rdata !== 32'd0) begin
            $display("[FAIL] ACC_CTRL after reset != 0, got 0x%08x", rdata);
            $finish;
        end
        wb_read(ACC_RESULT, rdata);
        if (rdata !== 32'd0) begin
            $display("[FAIL] ACC_RESULT after reset != 0, got 0x%08x", rdata);
            $finish;
        end
        wb_read(ACC_COUNT, rdata);
        if (rdata !== 32'd0) begin
            $display("[FAIL] ACC_COUNT after reset != 0, got 0x%08x", rdata);
            $finish;
        end

        // 写入一次算子计算使累加器非零
        wb_write(ACC_OPA, 32'h02020202);
        wb_write(ACC_OPB_TRIG, 32'h03030303); // dot4 = 4 * (2 * 3) = 24
        wb_read(ACC_RESULT, rdata);
        if (rdata !== 32'd24) begin
            $display("[FAIL] Expected ACC_RESULT=24, got %0d", rdata);
            $finish;
        end
        wb_read(ACC_COUNT, rdata);
        if (rdata !== 32'd1) begin
            $display("[FAIL] Expected ACC_COUNT=1, got %0d", rdata);
            $finish;
        end

        // 写入 ACC_CTRL = 1 清零
        wb_write(ACC_CTRL, 32'd1);
        wb_read(ACC_RESULT, rdata);
        if (rdata !== 32'd0) begin
            $display("[FAIL] ACC_RESULT not cleared by ACC_CTRL=1, got %0d", rdata);
            $finish;
        end
        wb_read(ACC_COUNT, rdata);
        if (rdata !== 32'd0) begin
            $display("[FAIL] ACC_COUNT not cleared by ACC_CTRL=1, got %0d", rdata);
            $finish;
        end
        $display("[PASS] Test 1: Reset & Clear OK");
        pass_count = pass_count + 1;

        // =====================================================================
        // Test 2: ACC_RESULT 预置负数偏置 (Bias = -100) 与 ReLU 激活验证
        // =====================================================================
        $display("[TEST 2] Bias preset (-100) & ReLU negative truncation...");
        // -100 (32'hFFFF_FF9C)
        wb_write(ACC_RESULT, 32'hFFFF_FF9C);
        wb_read(ACC_RESULT, rdata);
        if (rdata !== 32'hFFFF_FF9C) begin
            $display("[FAIL] ACC_RESULT bias write mismatch: got 0x%08x", rdata);
            $finish;
        end
        // 当累加器为负数时，ACC_RELU 必须被硬件截断输出 0
        wb_read(ACC_RELU, rdata);
        if (rdata !== 32'd0) begin
            $display("[FAIL] ACC_RELU should be 0 for negative acc, got 0x%08x", rdata);
            $finish;
        end
        $display("[PASS] Test 2: Bias Preset & ReLU Truncation OK");
        pass_count = pass_count + 1;

        // =====================================================================
        // Test 3: 有符号 INT8 极限边界与溢出累加验证
        // =====================================================================
        $display("[TEST 3] Signed INT8 extreme boundary cases...");
        // 3a. 在当前 acc_reg = -100 基础上累加 4 路 (-128 * -128)
        // a = {-128, -128, -128, -128} = 0x80808080
        // b = {-128, -128, -128, -128} = 0x80808080
        // prod = +16384 * 4 = +65536
        // new acc = -100 + 65536 = 65436 (0x0000_FFA4)
        wb_write(ACC_OPA, 32'h80808080);
        wb_write(ACC_OPB_TRIG, 32'h80808080);
        wb_read(ACC_RESULT, rdata);
        if (rdata !== 32'd65436) begin
            $display("[FAIL] 3a: Expected ACC_RESULT=65436, got %0d (0x%08x)", $signed(rdata), rdata);
            $finish;
        end
        // 正数时 ACC_RELU 原样输出
        wb_read(ACC_RELU, rdata);
        if (rdata !== 32'd65436) begin
            $display("[FAIL] 3a: Expected ACC_RELU=65436, got %0d", rdata);
            $finish;
        end
        wb_read(ACC_COUNT, rdata);
        if (rdata !== 32'd1) begin
            $display("[FAIL] 3a: Expected ACC_COUNT=1, got %0d", rdata);
            $finish;
        end

        // 3b. 极限负乘积: 4 路 (-128 * 127)
        // a = 0x80808080 (-128)
        // b = 0x7F7F7F7F (+127)
        // prod = -16256 * 4 = -65024
        // 清零后再计算
        wb_write(ACC_CTRL, 32'd1);
        wb_write(ACC_OPA, 32'h80808080);
        wb_write(ACC_OPB_TRIG, 32'h7F7F7F7F);
        wb_read(ACC_RESULT, rdata);
        if (rdata !== 32'hFFFF_0200) begin // -65024 in two's complement
            $display("[FAIL] 3b: Expected ACC_RESULT=-65024 (0xFFFF0200), got 0x%08x (%0d)", rdata, $signed(rdata));
            $finish;
        end
        wb_read(ACC_RELU, rdata);
        if (rdata !== 32'd0) begin
            $display("[FAIL] 3b: Expected ACC_RELU=0 for negative result, got 0x%08x", rdata);
            $finish;
        end

        // 3c. 正负混合向量点积验证
        // OPA: a3=10 (0x0A), a2=-20 (0xEC), a1=30 (0x1E), a0=-40 (0xD8) -> 0x0AEC1ED8
        // OPB: b3=-5 (0xFB), b2=-3 (0xFD), b1=2 (0x02), b0=4 (0x04) -> 0xFBFD0204
        // dot4 = (10*-5) + (-20*-3) + (30*2) + (-40*4) = -50 + 60 + 60 - 160 = -90
        // 当前 acc = -65024, new acc = -65024 + (-90) = -65114 (0xFFFF_01A6)
        wb_write(ACC_OPA, 32'h0AEC1ED8);
        wb_write(ACC_OPB_TRIG, 32'hFBFD0204);
        wb_read(ACC_RESULT, rdata);
        if (rdata !== 32'hFFFF_01A6) begin
            $display("[FAIL] 3c: Expected ACC_RESULT=-65114 (0xFFFF01A6), got 0x%08x (%0d)", rdata, $signed(rdata));
            $finish;
        end
        wb_read(ACC_COUNT, rdata);
        if (rdata !== 32'd2) begin
            $display("[FAIL] 3c: Expected ACC_COUNT=2, got %0d", rdata);
            $finish;
        end
        $display("[PASS] Test 3: Signed Boundaries & Mixed Arithmetic OK");
        pass_count = pass_count + 1;

        // =====================================================================
        // Test 4: 固定 ACC_OPA 权重复用 / 连续流式触发测试
        // =====================================================================
        $display("[TEST 4] Weight reuse (fixed ACC_OPA) & stream trigger...");
        // 清零并设置初始偏置 500
        wb_write(ACC_CTRL, 32'd1);
        wb_write(ACC_RESULT, 32'd500);

        // 设置权重 OPA: {1, 2, 3, 4} -> 0x01020304
        wb_write(ACC_OPA, 32'h01020304);

        // 触发第 1 批输入 OPB: {1, 1, 1, 1} -> 0x01010101
        // dot4 = 1*1 + 2*1 + 3*1 + 4*1 = 10 -> acc = 500 + 10 = 510
        wb_write(ACC_OPB_TRIG, 32'h01010101);

        // 触发第 2 批输入 OPB: {2, 2, 2, 2} -> 0x02020202 (OPA 保持不变!)
        // dot4 = 1*2 + 2*2 + 3*2 + 4*2 = 20 -> acc = 510 + 20 = 530
        wb_write(ACC_OPB_TRIG, 32'h02020202);

        // 触发第 3 批输入 OPB: {-1, -1, -1, 0} -> 0xFFFFFF00
        // dot4 = 1*(-1) + 2*(-1) + 3*(-1) + 4*0 = -6 -> acc = 530 - 6 = 524
        wb_write(ACC_OPB_TRIG, 32'hFFFFFF00);

        wb_read(ACC_COUNT, rdata);
        if (rdata !== 32'd3) begin
            $display("[FAIL] Test 4: Expected ACC_COUNT=3, got %0d", rdata);
            $finish;
        end
        wb_read(ACC_RESULT, rdata);
        if (rdata !== 32'd524) begin
            $display("[FAIL] Test 4: Expected ACC_RESULT=524, got %0d", rdata);
            $finish;
        end
        wb_read(ACC_RELU, rdata);
        if (rdata !== 32'd524) begin
            $display("[FAIL] Test 4: Expected ACC_RELU=524, got %0d", rdata);
            $finish;
        end
        $display("[PASS] Test 4: Weight Reuse & Stream Trigger OK");
        pass_count = pass_count + 1;

        #20;
        $display("------------------------------------------------------------");
        $display(">>> ALL WB_MAC_ACC TESTS PASSED <<< (%0d/4 checks passed)", pass_count);
        $display("------------------------------------------------------------");
        $finish;
    end

endmodule
`default_nettype wire
