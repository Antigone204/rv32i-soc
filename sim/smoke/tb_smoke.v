`timescale 1ns/1ps
`default_nettype none
// tb_smoke — smoke_top 自检 testbench
// 用很小的 CLK_HZ（每 bit 16 个时钟）加快仿真：
//   1. 解码 TX，检查 banner 是否为 "RV32 smoke test OK! > \r\n"
//   2. 向 RX 发送 "Hi"，检查回显，并检查 LED[7:1]
module tb_smoke;
    localparam integer CLK_HZ = 1_843_200;   // 1.8432 MHz / 115200 = 16 clk/bit
    localparam integer BAUD   = 115_200;
    localparam integer CPB    = CLK_HZ / BAUD;

    reg  clk = 1'b0;
    reg  rxd = 1'b1;
    wire txd;
    wire [7:0] led;

    always #5 clk = ~clk;

    smoke_top #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
        .sys_clk(clk), .uart_rxd(rxd), .uart_txd(txd), .led(led)
    );

    // ---------- TX 解码器：把收到的字符存到缓冲区 ----------
    reg [8*64-1:0] got;
    integer        n_got = 0;
    integer        i;
    reg [7:0]      ch;

    initial begin : tx_monitor
        forever begin
            @(negedge txd);
            repeat (CPB/2) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                repeat (CPB) @(posedge clk);
                ch[i] = txd;
            end
            repeat (CPB) @(posedge clk);
            got   = {got[8*63-1:0], ch};
            n_got = n_got + 1;
        end
    end

    task send_byte(input [7:0] b);
        integer k;
        begin
            rxd = 1'b0; repeat (CPB) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                rxd = b[k]; repeat (CPB) @(posedge clk);
            end
            rxd = 1'b1; repeat (CPB) @(posedge clk);
        end
    endtask

    localparam [8*24-1:0] BANNER = {"RV32 smoke test OK! > ", 8'h0D, 8'h0A};
    integer errors = 0;

    initial begin
        // 等待 banner 发完：24 字符 × 10 bit × CPB + 余量
        repeat (24*10*CPB + 2000) @(posedge clk);
        if (n_got != 24 || got[8*24-1:0] !== BANNER) begin
            $display("FAIL: banner mismatch, n_got=%0d got=\"%s\"", n_got, got[8*24-1:0]);
            errors = errors + 1;
        end else begin
            $display("PASS: banner = \"%s\"", got[8*24-1:16]);
        end

        send_byte("H");
        send_byte("i");
        repeat (25*CPB) @(posedge clk);
        if (n_got != 26 || got[15:0] !== "Hi") begin
            $display("FAIL: echo mismatch, n_got=%0d last=\"%s\"", n_got, got[15:0]);
            errors = errors + 1;
        end else begin
            $display("PASS: echo = \"%s\"", got[15:0]);
        end

        if (led[7:1] !== "i") begin
            $display("FAIL: led[7:1]=%h expected %h", led[7:1], "i");
            errors = errors + 1;
        end else begin
            $display("PASS: led[7:1] shows last rx byte");
        end

        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $finish;
    end
endmodule
`default_nettype wire
