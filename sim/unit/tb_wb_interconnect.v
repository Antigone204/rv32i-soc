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

    // Slave 3: MAC Accelerator
    wire        wbs3_cyc;
    wire        wbs3_stb;
    wire        wbs3_we;
    wire [31:0] wbs3_adr;
    wire [31:0] wbs3_dat_w;
    wire [3:0]  wbs3_sel;
    reg  [31:0] wbs3_dat_r = 32'hDDDD_0004;
    reg         wbs3_ack = 1'b0;

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
        .wbs2_ack_i(wbs2_ack),

        .wbs3_cyc_o(wbs3_cyc),
        .wbs3_stb_o(wbs3_stb),
        .wbs3_we_o (wbs3_we),
        .wbs3_adr_o(wbs3_adr),
        .wbs3_dat_o(wbs3_dat_w),
        .wbs3_sel_o(wbs3_sel),
        .wbs3_dat_i(wbs3_dat_r),
        .wbs3_ack_i(wbs3_ack)
    );

    // Mock slave ack generation (匹配真实从设备: ack <= cyc & stb)
    always @(posedge clk) begin
        if (!rst_n) begin
            wbs0_ack <= 1'b0;
            wbs1_ack <= 1'b0;
            wbs2_ack <= 1'b0;
            wbs3_ack <= 1'b0;
        end else begin
            wbs0_ack <= wbs0_cyc & wbs0_stb;
            wbs1_ack <= wbs1_cyc & wbs1_stb;
            wbs2_ack <= wbs2_cyc & wbs2_stb;
            wbs3_ack <= wbs3_cyc & wbs3_stb;
        end
    end

    // Slave side-effect tracking
    integer wbs0_we_cnt = 0;
    integer wbs1_we_cnt = 0;
    integer wbs2_we_cnt = 0;
    reg [31:0] wbs0_last_wdata = 0;
    reg [31:0] wbs1_last_wdata = 0;
    reg [31:0] wbs2_last_wdata = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (wbs0_cyc & wbs0_stb & wbs0_we) begin
                wbs0_we_cnt     <= wbs0_we_cnt + 1;
                wbs0_last_wdata <= wbs0_dat_w;
            end
            if (wbs1_cyc & wbs1_stb & wbs1_we) begin
                wbs1_we_cnt     <= wbs1_we_cnt + 1;
                wbs1_last_wdata <= wbs1_dat_w;
            end
            if (wbs2_cyc & wbs2_stb & wbs2_we) begin
                wbs2_we_cnt     <= wbs2_we_cnt + 1;
                wbs2_last_wdata <= wbs2_dat_w;
            end
        end
    end

    integer saved_wbs0_cnt;
    integer saved_wbs1_cnt;
    integer saved_wbs2_cnt;

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
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;
        #1;
        if (!wbm_ack || wbm_dat_r != 32'hAAAA_0001) begin
            $display("[FAIL] SRAM read/ack failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        @(posedge clk);

        // Test 2: Access UART (0x1001_0000)
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b1;
        wbm_adr <= 32'h1001_0000;
        wbm_dat <= 32'h0000_0041;
        @(posedge clk);
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;
        #1;
        if (!wbm_ack) begin
            $display("[FAIL] UART ack failed");
            $finish;
        end
        @(posedge clk);

        // Test 3: Access CLINT (0x0200_BFF8)
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b0;
        wbm_adr <= 32'h0200_BFF8;
        @(posedge clk);
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;
        #1;
        if (!wbm_ack || wbm_dat_r != 32'hCCCC_0003) begin
            $display("[FAIL] CLINT read/ack failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        @(posedge clk);

        // =====================================================================
        // 定向测试 1: 单个未映射读
        // =====================================================================
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b0;
        wbm_adr <= 32'h3000_0000;
        @(posedge clk);
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;
        #1;
        if (!wbm_ack || wbm_dat_r != 32'h0000_0000) begin
            $display("[FAIL] Test 4 Single unmapped read failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        if (wbs0_stb || wbs1_stb || wbs2_stb) begin
            $display("[FAIL] Test 4 Unmapped triggered slave strobe!");
            $finish;
        end
        @(posedge clk);
        #1;
        if (wbm_ack) begin
            $display("[FAIL] Test 4 Unmapped ACK persisted when bus idle!");
            $finish;
        end

        // =====================================================================
        // 定向测试 2: 单个未映射写
        // =====================================================================
        saved_wbs0_cnt = wbs0_we_cnt;
        saved_wbs1_cnt = wbs1_we_cnt;
        saved_wbs2_cnt = wbs2_we_cnt;
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b1;
        wbm_adr <= 32'h4000_0000;
        wbm_dat <= 32'hDEAD_BEEF;
        @(posedge clk);
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;
        #1;
        if (!wbm_ack) begin
            $display("[FAIL] Test 5 Single unmapped write failed: ack=%b", wbm_ack);
            $finish;
        end
        if (wbs0_we_cnt != saved_wbs0_cnt || wbs1_we_cnt != saved_wbs1_cnt || wbs2_we_cnt != saved_wbs2_cnt) begin
            $display("[FAIL] Test 5 Unmapped write caused slave side-effects!");
            $finish;
        end
        @(posedge clk);
        #1;
        if (wbm_ack) begin
            $display("[FAIL] Test 5 Unmapped write ACK persisted when bus idle!");
            $finish;
        end

        // =====================================================================
        // 定向测试 3: 连续三个未映射访问 (背靠背)
        // =====================================================================
        saved_wbs0_cnt = wbs0_we_cnt;
        saved_wbs1_cnt = wbs1_we_cnt;
        saved_wbs2_cnt = wbs2_we_cnt;
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b0;
        wbm_adr <= 32'h5000_0000; // Req 1
        @(posedge clk);
        wbm_we  <= 1'b1;
        wbm_adr <= 32'h6000_0000; // Req 2
        wbm_dat <= 32'h1111_2222;
        #1;
        if (!wbm_ack || wbm_dat_r != 32'h0) begin
            $display("[FAIL] Test 6 Req 1 unmapped response failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        @(posedge clk);
        wbm_we  <= 1'b0;
        wbm_adr <= 32'h7000_0000; // Req 3
        #1;
        if (!wbm_ack) begin
            $display("[FAIL] Test 6 Req 2 unmapped response failed: ack=%b", wbm_ack);
            $finish;
        end
        @(posedge clk);
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0; // Idle
        #1;
        if (!wbm_ack || wbm_dat_r != 32'h0) begin
            $display("[FAIL] Test 6 Req 3 unmapped response failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        @(posedge clk);
        #1;
        if (wbm_ack) begin
            $display("[FAIL] Test 6 ACK did not drop to 0 after 3 unmapped accesses!");
            $finish;
        end
        if (wbs0_we_cnt != saved_wbs0_cnt || wbs1_we_cnt != saved_wbs1_cnt || wbs2_we_cnt != saved_wbs2_cnt) begin
            $display("[FAIL] Test 6 Unmapped writes touched slaves!");
            $finish;
        end

        // =====================================================================
        // 定向测试 4: SRAM -> UART 连续背靠背访问
        // =====================================================================
        saved_wbs1_cnt = wbs1_we_cnt;
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b0;
        wbm_adr <= 32'h0000_1000; // SRAM read
        @(posedge clk);
        wbm_we  <= 1'b1;
        wbm_adr <= 32'h1001_0000; // UART write
        wbm_dat <= 32'h0000_0055;
        #1;
        if (!wbm_ack || wbm_dat_r != 32'hAAAA_0001) begin
            $display("[FAIL] Test 7 SRAM response failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        if (!wbs1_stb || !wbs1_we || wbs1_dat_w != 32'h55) begin
            $display("[FAIL] Test 7 UART write strobe failed!");
            $finish;
        end
        @(posedge clk);
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;
        #1;
        if (!wbm_ack) begin
            $display("[FAIL] Test 7 UART write response failed: ack=%b", wbm_ack);
            $finish;
        end
        if (wbs1_we_cnt != saved_wbs1_cnt + 1 || wbs1_last_wdata != 32'h55) begin
            $display("[FAIL] Test 7 UART write side-effect mismatch!");
            $finish;
        end
        @(posedge clk);
        #1;
        if (wbm_ack) begin
            $display("[FAIL] Test 7 ACK did not drop after SRAM->UART!");
            $finish;
        end

        // =====================================================================
        // 定向测试 5: UART -> CLINT 连续背靠背访问
        // =====================================================================
        saved_wbs1_cnt = wbs1_we_cnt;
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b1;
        wbm_adr <= 32'h1001_0000; // UART write
        wbm_dat <= 32'h0000_0056;
        @(posedge clk);
        wbm_we  <= 1'b0;
        wbm_adr <= 32'h0200_BFF8; // CLINT read
        #1;
        if (!wbm_ack) begin
            $display("[FAIL] Test 8 UART response failed: ack=%b", wbm_ack);
            $finish;
        end
        @(posedge clk);
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;
        #1;
        if (!wbm_ack || wbm_dat_r != 32'hCCCC_0003) begin
            $display("[FAIL] Test 8 CLINT response failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        if (wbs1_we_cnt != saved_wbs1_cnt + 1 || wbs1_last_wdata != 32'h56) begin
            $display("[FAIL] Test 8 UART write side-effect mismatch!");
            $finish;
        end
        @(posedge clk);
        #1;
        if (wbm_ack) begin
            $display("[FAIL] Test 8 ACK did not drop after UART->CLINT!");
            $finish;
        end

        // =====================================================================
        // 定向测试 6: CLINT -> Unmapped 连续背靠背访问
        // =====================================================================
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b0;
        wbm_adr <= 32'h0200_BFF8; // CLINT read
        @(posedge clk);
        wbm_adr <= 32'h3000_0000; // Unmapped read
        #1;
        if (!wbm_ack || wbm_dat_r != 32'hCCCC_0003) begin
            $display("[FAIL] Test 9 CLINT response failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        @(posedge clk);
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;
        #1;
        if (!wbm_ack || wbm_dat_r != 32'h0000_0000) begin
            $display("[FAIL] Test 9 Unmapped response failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        @(posedge clk);
        #1;
        if (wbm_ack) begin
            $display("[FAIL] Test 9 ACK did not drop after CLINT->Unmapped!");
            $finish;
        end

        // =====================================================================
        // 定向测试 7: Unmapped -> SRAM 连续背靠背访问
        // =====================================================================
        saved_wbs0_cnt = wbs0_we_cnt;
        saved_wbs1_cnt = wbs1_we_cnt;
        saved_wbs2_cnt = wbs2_we_cnt;
        @(posedge clk);
        wbm_cyc <= 1'b1;
        wbm_stb <= 1'b1;
        wbm_we  <= 1'b1;
        wbm_adr <= 32'h3000_0000; // Unmapped write
        wbm_dat <= 32'h9999_9999;
        @(posedge clk);
        wbm_we  <= 1'b0;
        wbm_adr <= 32'h0000_2000; // SRAM read
        #1;
        if (!wbm_ack) begin
            $display("[FAIL] Test 10 Unmapped write response failed: ack=%b", wbm_ack);
            $finish;
        end
        if (wbs0_we_cnt != saved_wbs0_cnt || wbs1_we_cnt != saved_wbs1_cnt || wbs2_we_cnt != saved_wbs2_cnt) begin
            $display("[FAIL] Test 10 Unmapped write touched slaves!");
            $finish;
        end
        @(posedge clk);
        wbm_cyc <= 1'b0;
        wbm_stb <= 1'b0;
        #1;
        if (!wbm_ack || wbm_dat_r != 32'hAAAA_0001) begin
            $display("[FAIL] Test 10 SRAM response failed: ack=%b, dat=%h", wbm_ack, wbm_dat_r);
            $finish;
        end
        @(posedge clk);
        #1;
        if (wbm_ack) begin
            $display("[FAIL] Test 10 ACK did not drop after Unmapped->SRAM!");
            $finish;
        end

        #20;
        $display("ALL WB_INTERCONNECT TESTS PASSED (INCLUDING DIRECTED UNMAPPED & BACK-TO-BACK)");
        $finish;
    end

endmodule
`default_nettype wire
