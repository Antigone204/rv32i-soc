`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_soc — SoC 顶层综合集成验证平台 (SoC Top Integration Testbench)
//
// 验证特性：
//   1. 例化 soc_top 顶层；
//   2. 支持通过 +HEX=<file.hex> 动态加载裸机固件；
//   3. 实时解码 uart_txd 物理串口引脚，打印字符输出流；
//   4. 监控 0x0000_1000 Mailbox 写入，自动化判决测试通过或失败；
//   5. 统计周期数、指令数与 CPI。
// -----------------------------------------------------------------------------
module tb_soc;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;

    localparam integer CLK_HZ     = 50_000_000;
    localparam integer BAUD       = 1_000_000; // 仿真加速：50 clks/bit
    localparam integer SRAM_WORDS = 16384;      // 64 KB
    localparam integer CPB        = CLK_HZ / BAUD;

    wire        uart_txd;
    reg         uart_rxd = 1'b1;
    wire [7:0]  led;

    wire        wb_valid;
    wire        wb_we;
    wire [31:0] wb_pc;
    wire [4:0]  wb_rd;
    wire [31:0] wb_wdata;

    wire [31:0] perf_cycle;
    wire [31:0] perf_instret;

    // 例化 SoC 顶层
    soc_top #(
        .CLK_HZ    (CLK_HZ),
        .BAUD      (BAUD),
        .SRAM_WORDS(SRAM_WORDS)
    ) u_soc (
        .clk         (clk),
        .rst_n       (rst_n),
        .uart_txd    (uart_txd),
        .uart_rxd    (uart_rxd),
        .led         (led),
        .wb_valid    (wb_valid),
        .wb_we       (wb_we),
        .wb_pc       (wb_pc),
        .wb_rd       (wb_rd),
        .wb_wdata    (wb_wdata),
        .perf_cycle  (perf_cycle),
        .perf_instret(perf_instret)
    );

    // =========================================================================
    // UART 物理发送输出监听与终端打印
    // =========================================================================
    reg [7:0] rx_byte;
    integer b;
    initial begin : uart_monitor
        @(posedge rst_n);
        forever begin
            @(negedge uart_txd);
            repeat (CPB / 2) @(posedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                repeat (CPB) @(posedge clk);
                rx_byte[b] = uart_txd;
            end
            repeat (CPB) @(posedge clk);
            $write("%c", rx_byte);
            $fflush();
        end
    end

    // =========================================================================
    // 固件装载与测试监控流程
    // =========================================================================
    reg [1023:0] hex_file = 0;
    reg [7:0]    byte_mem [0:SRAM_WORDS*4 - 1];
    integer      i;
    integer      timeout_cycles = 100000;
    integer      cycles = 0;

    initial begin
        // 初始化内存为 NOP
        for (i = 0; i < SRAM_WORDS*4; i = i + 1) byte_mem[i] = 8'h0;
        for (i = 0; i < SRAM_WORDS; i = i + 1)   u_soc.u_sram.mem[i] = 32'h0000_0013;

        if (!$value$plusargs("HEX=%s", hex_file)) begin
            $display("[ERROR] No +HEX=<file> specified!");
            $finish;
        end

        void'($value$plusargs("TIMEOUT=%d", timeout_cycles));

        // 装载 Hex
        $readmemh(hex_file, byte_mem);
        for (i = 0; i < SRAM_WORDS; i = i + 1) begin
            u_soc.u_sram.mem[i] = {byte_mem[i*4+3], byte_mem[i*4+2],
                                   byte_mem[i*4+1], byte_mem[i*4+0]};
        end

        // 复位释放
        #20;
        rst_n = 1'b1;
    end

    // Mailbox 监控
    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;

            // 检查 CPU 对 0x0000_1000 的写操作
            if (u_soc.u_core.dmem_req && (|u_soc.u_core.dmem_byte_we) &&
                (u_soc.u_core.dmem_addr == 32'h0000_1000)) begin
                $display("\n[MAILBOX] CPU wrote 0x%08x to 0x00001000", u_soc.u_core.dmem_wdata);
                if (u_soc.u_core.dmem_wdata == 32'h0000_0001) begin
                    // 等待物理串口将 TX FIFO 中的字符全部序列化发送完毕
                    repeat (2500) @(posedge clk);
                    $display("\n==============================================");
                    $display("SOC VERIFICATION PASSED");
                    $display("Cycles: %0d, Instructions: %0d, CPI: %0.2f",
                             cycles, perf_instret, $itor(cycles) / $itor(perf_instret));
                    $display("==============================================");
                    $finish;
                end else begin
                    $display("\n[FAIL] SoC test reported failure code: 0x%08x", u_soc.u_core.dmem_wdata);
                    $finish;
                end
            end

            if (cycles > timeout_cycles) begin
                $display("\n[TIMEOUT] Simulation reached %0d cycles without mailbox report", cycles);
                $finish;
            end
        end
    end

endmodule
`default_nettype wire
