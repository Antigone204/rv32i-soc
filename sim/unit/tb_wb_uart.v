`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_wb_uart — Wishbone UART 控制器单元测试
// -----------------------------------------------------------------------------
module tb_wb_uart;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;

    reg         wbs_cyc = 1'b0;
    reg         wbs_stb = 1'b0;
    reg         wbs_we  = 1'b0;
    reg  [31:0] wbs_adr = 32'd0;
    reg  [31:0] wbs_dat_w = 32'd0;
    reg  [3:0]  wbs_sel = 4'hF;
    wire [31:0] wbs_dat_r;
    wire        wbs_ack;

    wire uart_txd;
    reg  uart_rxd = 1'b1;

    // 使用 CPB = 16 时钟/bit 加快仿真
    localparam TEST_CLK_HZ = 1_843_200;
    localparam TEST_BAUD   = 115_200;
    localparam CPB          = TEST_CLK_HZ / TEST_BAUD; // 16

    wb_uart #(
        .CLK_HZ(TEST_CLK_HZ),
        .BAUD  (TEST_BAUD)
    ) u_dut (
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
        .uart_txd (uart_txd),
        .uart_rxd (uart_rxd)
    );

    // Wishbone 单次读任务 (1 拍选通)
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

    // Wishbone 单次写任务 (1 拍选通)
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
        end
    endtask

    // 辅助任务：通过 rxd 模拟外部串口发送 1 字节
    task send_uart_byte(input [7:0] byte_val);
        integer b;
        begin
            // 起始位 (0)
            uart_rxd <= 1'b0;
            repeat (CPB) @(posedge clk);

            // 8 数据位 (LSB 先发)
            for (b = 0; b < 8; b = b + 1) begin
                uart_rxd <= byte_val[b];
                repeat (CPB) @(posedge clk);
            end

            // 停止位 (1)
            uart_rxd <= 1'b1;
            repeat (CPB) @(posedge clk);
        end
    endtask

    reg [31:0] rdata;

    initial begin
        #20;
        rst_n = 1'b1;
        #20;

        // 1. 检查初始状态：TXDATA 读 bit[31] 应为 0 (非满)
        wb_read(32'h1001_0000, rdata);
        if (rdata[31] !== 1'b0) begin
            $display("[FAIL] TX FIFO initially reported full: %h", rdata);
            $finish;
        end

        // 2. 检查初始状态：RXDATA 读 bit[31] 应为 1 (空)
        wb_read(32'h1001_0004, rdata);
        if (rdata[31] !== 1'b1) begin
            $display("[FAIL] RX FIFO initially reported not empty: %h", rdata);
            $finish;
        end

        // 3. 向 TXDATA 写入 0x55 ('U')
        wb_write(32'h1001_0000, 32'h0000_0055);

        // 等待物理发送完成 (10 bit * CPB + 余量)
        repeat (12 * CPB) @(posedge clk);

        // 4. 模拟外部输入发送 0xA5 给 RX
        send_uart_byte(8'hA5);

        // 5. 读取 RXDATA，检查是否读出 0xA5 且 bit[31] == 0
        wb_read(32'h1001_0004, rdata);
        if (rdata[31] !== 1'b0 || rdata[7:0] !== 8'hA5) begin
            $display("[FAIL] RXDATA read mismatch: %h (expected 0x000000A5)", rdata);
            $finish;
        end

        // 6. 再次读取 RXDATA，检查是否已出队 (bit[31] == 1 表示已空)
        wb_read(32'h1001_0004, rdata);
        if (rdata[31] !== 1'b1) begin
            $display("[FAIL] RXDATA did not pop: %h (expected bit[31]=1)", rdata);
            $finish;
        end

        #20;
        $display("ALL WB_UART TESTS PASSED");
        $finish;
    end

endmodule
`default_nettype wire
