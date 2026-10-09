`timescale 1ns/1ps
`default_nettype none

module tb_regfile;
    reg         clk = 1'b0;
    reg         rst_n = 1'b0;

    reg  [4:0]  raddr1 = 5'd0;
    wire [31:0] rdata1;

    reg  [4:0]  raddr2 = 5'd0;
    wire [31:0] rdata2;

    reg         we = 1'b0;
    reg  [4:0]  waddr = 5'd0;
    reg  [31:0] wdata = 32'd0;

    always #5 clk = ~clk;

    regfile dut (
        .clk   (clk),
        .rst_n (rst_n),
        .raddr1(raddr1),
        .rdata1(rdata1),
        .raddr2(raddr2),
        .rdata2(rdata2),
        .we    (we),
        .waddr (waddr),
        .wdata (wdata)
    );

    integer errors = 0;

    initial begin
        // 复位
        #12 rst_n = 1'b1;
        #10;

        // 1. 尝试写 x0，验证 x0 读出恒为 0
        @(negedge clk);
        we = 1'b1; waddr = 5'd0; wdata = 32'hDEAD_BEEF;
        @(negedge clk);
        we = 1'b0;
        raddr1 = 5'd0;
        #1;
        if (rdata1 !== 32'd0) begin
            $display("FAIL [X0_HARDWIRED]: expected 0, got 0x%08h", rdata1);
            errors = errors + 1;
        end else begin
            $display("PASS [X0_HARDWIRED]: x0 stays 0");
        end

        // 2. 正常写 x1 和 x2
        @(negedge clk);
        we = 1'b1; waddr = 5'd1; wdata = 32'h1234_5678;
        @(negedge clk);
        we = 1'b1; waddr = 5'd2; wdata = 32'h8765_4321;
        @(negedge clk);
        we = 1'b0;

        raddr1 = 5'd1;
        raddr2 = 5'd2;
        #1;
        if (rdata1 !== 32'h1234_5678 || rdata2 !== 32'h8765_4321) begin
            $display("FAIL [READ_WRITE]: rdata1=%h rdata2=%h", rdata1, rdata2);
            errors = errors + 1;
        end else begin
            $display("PASS [READ_WRITE]: normal registers read/write ok");
        end

        // 3. 内部写直通 (Write-First Bypass)
        // 在同一个时钟周期准备写入 x3 = 0xAAAA_BBBB，并在同一时刻读 raddr1 = x3
        @(negedge clk);
        we = 1'b1; waddr = 5'd3; wdata = 32'hAAAA_BBBB;
        raddr1 = 5'd3;
        #1; // 内部写直通是纯组合逻辑，立即读出
        if (rdata1 !== 32'hAAAA_BBBB) begin
            $display("FAIL [INTERNAL_BYPASS]: expected 0x%08h, got 0x%08h", 32'hAAAA_BBBB, rdata1);
            errors = errors + 1;
        end else begin
            $display("PASS [INTERNAL_BYPASS]: write-first bypass works");
        end

        @(posedge clk);
        we = 1'b0;

        #20;
        if (errors == 0) begin
            $display("\n>>> ALL REGFILE TESTS PASSED <<<");
        end else begin
            $display("\n>>> %0d REGFILE TESTS FAILED <<<", errors);
        end
        $finish;
    end

endmodule
`default_nettype wire
