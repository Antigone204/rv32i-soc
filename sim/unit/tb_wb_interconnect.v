`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_wb_interconnect — Wishbone 互连模块单元测试
// -----------------------------------------------------------------------------
module tb_wb_interconnect;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;

    // Master signals
    reg         wbm_cyc = 1'b0;
    reg         wbm_stb = 1'b0;
    reg         wbm_we  = 1'b0;
    reg  [31:0] wbm_adr = 32'd0;
    reg  [31:0] wbm_dat = 32'd0;
    reg  [3:0]  wbm_sel = 4'hF;
    wire [31:0] wbm_dat_r;
    wire        wbm_ack;

    // Slave 0: SRAM
    wire        wbs0_cyc;
    wire        wbs0_stb;
    wire        wbs0_we;
    wire [31:0] wbs0_adr;
    wire [31:0] wbs0_dat_w;
    wire [3:0]  wbs0_sel;
    reg  [31:0] wbs0_dat_r = 32'hAAAA_0001;
    reg         wbs0_ack = 1'b0;

    // Slave 1: UART
    wire        wbs1_cyc;
    wire        wbs1_stb;
    wire        wbs1_we;
    wire [31:0] wbs1_adr;
    wire [31:0] wbs1_dat_w;
    wire [3:0]  wbs1_sel;
    reg  [31:0] wbs1_dat_r = 32'hBBBB_0002;
    reg         wbs1_ack = 1'b0;

    // Slave 2: CLINT
    wire        wbs2_cyc;
    wire        wbs2_stb;
    wire        wbs2_we;
    wire [31:0] wbs2_adr;
    wire [31:0] wbs2_dat_w;
    wire [3:0]  wbs2_sel;
    reg  [31:0] wbs2_dat_r = 32'hCCCC_0003;
    reg         wbs2_ack = 1'b0;

    wb_interconnect u_dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .wbm_cyc_i (wbm_cyc),
        .wbm_stb_i (wbm_stb),
        .wbm_we_i  (wbm_we),
        .wbm_adr_i (wbm_adr),
        .wbm_dat_i (wbm_dat),
        .wbm_sel_i (wbm_sel),
        .wbm_dat_o (wbm_dat_r),
        .wbm_ack_o (wbm_ack),

        .wbs0_cyc_o(wbs0_cyc),
        .wbs0_stb_o(wbs0_stb),
        .wbs0_we_o (wbs0_we),
        .wbs0_adr_o(wbs0_adr),
        .wbs0_dat_o(wbs0_dat_w),
        .wbs0_sel_o(wbs0_sel),
        .wbs0_dat_i(wbs0_dat_r),
        .wbs0_ack_i(wbs0_ack),

        .wbs1_cyc_o(wbs1_cyc),
        .wbs1_stb_o(wbs1_stb),
        .wbs1_we_o (wbs1_we),
        .wbs1_adr_o(wbs1_adr),
        .wbs1_dat_o(wbs1_dat_w),
        .wbs1_sel_o(wbs1_sel),
        .wbs1_dat_i(wbs1_dat_r),
        .wbs1_ack_i(wbs1_ack),

        .wbs2_cyc_o(wbs2_cyc),
        .wbs2_stb_o(wbs2_stb),
        .wbs2_we_o (wbs2_we),
        .wbs2_adr_o(wbs2_adr),
        .wbs2_dat_o(wbs2_dat_w),
        .wbs2_sel_o(wbs2_sel),
        .wbs2_dat_i(wbs2_dat_r),
        .wbs2_ack_i(wbs2_ack)
    );

    // Mock slave ack generation
    always @(posedge clk) begin
        wbs0_ack <= wbs0_cyc & wbs0_stb & ~wbs0_ack;
        wbs1_ack <= wbs1_cyc & wbs1_stb & ~wbs1_ack;
        wbs2_ack <= wbs2_cyc & wbs2_stb & ~wbs2_ack;
    end

    initial begin
        #20;
        rst_n = 1'b1;
        #10;

        // Test 1: Access SRAM (0x0000_1000)
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b0;
        wbm_adr <= 32'h0000_1000;
        @(posedge clk);
        #1;
        if (!wbs0_stb || wbs1_stb || wbs2_stb) begin
            $display("[FAIL] SRAM address decoding failed!");
            $finish;
        end
        if (!wbm_ack || wbm_dat_r != 32'hAAAA_0001) begin
            $display("[FAIL] SRAM read/ack failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;

        // Test 2: Access UART (0x1001_0000)
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b1;
        wbm_adr <= 32'h1001_0000;
        wbm_dat <= 32'h0000_0041;
        @(posedge clk);
        #1;
        if (wbs0_stb || !wbs1_stb || wbs2_stb) begin
            $display("[FAIL] UART address decoding failed!");
            $finish;
        end
        if (!wbm_ack) begin
            $display("[FAIL] UART ack failed");
            $finish;
        end
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;

        // Test 3: Access CLINT (0x0200_BFF8)
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b0;
        wbm_adr <= 32'h0200_BFF8;
        @(posedge clk);
        #1;
        if (wbs0_stb || wbs1_stb || !wbs2_stb) begin
            $display("[FAIL] CLINT address decoding failed!");
            $finish;
        end
        if (!wbm_ack || wbm_dat_r != 32'hCCCC_0003) begin
            $display("[FAIL] CLINT read/ack failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;

        #20;
        $display("ALL WB_INTERCONNECT TESTS PASSED");
        $finish;
    end

endmodule
`default_nettype wire
