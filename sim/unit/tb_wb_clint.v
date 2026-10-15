`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_wb_clint — Wishbone CLINT 定时器单元测试
// -----------------------------------------------------------------------------
module tb_wb_clint;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;

    reg         wbs_cyc   = 1'b0;
    reg         wbs_stb   = 1'b0;
    reg         wbs_we    = 1'b0;
    reg  [31:0] wbs_adr   = 32'd0;
    reg  [31:0] wbs_dat_w = 32'd0;
    reg  [3:0]  wbs_sel   = 4'hF;
    wire [31:0] wbs_dat_r;
    wire        wbs_ack;
    wire        timer_irq;

    wb_clint u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .wbs_cyc_i(wbs_cyc),
        .wbs_stb_i(wbs_stb),
        .wbs_we_i (wbs_we),
        .wbs_adr_i(wbs_adr),
        .wbs_sel_i(wbs_sel),
        .wbs_dat_i(wbs_dat_w),
        .wbs_dat_o(wbs_dat_r),
        .wbs_ack_o(wbs_ack),
        .timer_irq(timer_irq)
    );

    task wb_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            wbs_cyc <= 1'b1;
            wbs_stb <= 1'b1;
            wbs_we  <= 1'b0;
            wbs_adr <= addr;
            @(posedge clk);
            while (!wbs_ack) @(posedge clk);
            #1;
            data = wbs_dat_r;
            wbs_cyc <= 1'b0;
            wbs_stb <= 1'b0;
        end
    endtask

    task wb_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            wbs_cyc   <= 1'b1;
            wbs_stb   <= 1'b1;
            wbs_we    <= 1'b1;
            wbs_adr   <= addr;
            wbs_dat_w <= data;
            @(posedge clk);
            while (!wbs_ack) @(posedge clk);
            wbs_cyc <= 1'b0;
            wbs_stb <= 1'b0;
        end
    endtask

    reg [31:0] rdata1, rdata2;

    initial begin
        #20;
        rst_n = 1'b1;
        #20;

        // 1. 测试 mtime 自增特性：读两次 MTIME_LO，第二次必须大于第一次
        wb_read(32'h0200_BFF8, rdata1);
        repeat (10) @(posedge clk);
        wb_read(32'h0200_BFF8, rdata2);

        if (rdata2 <= rdata1) begin
            $display("[FAIL] mtime did not increment: rdata1=%d, rdata2=%d", rdata1, rdata2);
            $finish;
        end

        // 2. 初始状态下 timer_irq 必须为 0 (mtimecmp 默认为全 1)
        if (timer_irq !== 1'b0) begin
            $display("[FAIL] timer_irq initially asserted!");
            $finish;
        end

        // 3. 配置 mtimecmp 为一个已知值 (例如 50)，测试中断触发
        wb_write(32'h0200_4004, 32'h0000_0000); // MTIMECMP_HI = 0
        wb_write(32'h0200_4000, 32'd50);        // MTIMECMP_LO = 50

        // 等待 mtime 计数超过 50
        while (u_dut.mtime < 64'd50) @(posedge clk);
        @(posedge clk);
        #1;

        if (timer_irq !== 1'b1) begin
            $display("[FAIL] timer_irq not asserted when mtime >= mtimecmp: mtime=%d", u_dut.mtime);
            $finish;
        end

        // 4. 重设 mtimecmp 为极大值，验证中断清除
        wb_write(32'h0200_4000, 32'hFFFF_FFFF);
        wb_write(32'h0200_4004, 32'hFFFF_FFFF);
        @(posedge clk);
        #1;

        if (timer_irq !== 1'b0) begin
            $display("[FAIL] timer_irq did not clear after increasing mtimecmp!");
            $finish;
        end

        #20;
        $display("ALL WB_CLINT TESTS PASSED");
        $finish;
    end

endmodule
`default_nettype wire
