`default_nettype none
// -----------------------------------------------------------------------------
// wb_uart — Wishbone B4 UART 控制器 (包含 TX/RX FIFO)
//
// 特性：
//   - 封装已有 uart_tx.v 和 uart_rx.v 物理层模块；
//   - 内置 8 字节深度 TX FIFO 和 8 字节深度 RX FIFO；
//   - 寄存器映射对齐 SiFive FE310 规范 (基地址 0x1001_0000)：
//       0x00 TXDATA : 读 bit[31]=full; 写 [7:0]=tx_byte
//       0x04 RXDATA : 读 bit[31]=empty, [7:0]=rx_byte (读出自动出队)
//       0x08 TXCTRL : bit[0]=txen
//       0x0C RXCTRL : bit[0]=rxen
//       0x10 IE     : 中断使能 (预留)
//       0x14 IP     : 中断挂起 (只读 0)
//       0x18 DIV    : 分频寄存器
//   - 1 拍同步读出，单周期 ACK 响应。
// -----------------------------------------------------------------------------
module wb_uart #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Wishbone Slave 接口 ----
    input  wire        wbs_cyc_i,
    input  wire        wbs_stb_i,
    input  wire        wbs_we_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] wbs_adr_i,
    input  wire [3:0]  wbs_sel_i,
    input  wire [31:0] wbs_dat_i,
    /* verilator lint_on  UNUSEDSIGNAL */
    output reg  [31:0] wbs_dat_o,
    output reg         wbs_ack_o,

    // ---- 外部物理串口引脚 ----
    output wire        uart_txd,
    input  wire        uart_rxd
);
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

    // =========================================================================
    // 1. 控制寄存器定义
    // =========================================================================
    reg        reg_txctrl;
    reg        reg_rxctrl;
    reg [1:0]  reg_ie;
    reg [15:0] reg_div;

    // =========================================================================
    // 2. 8 字节 TX FIFO
    // =========================================================================
    reg  [7:0] tx_mem [0:7];
    reg  [2:0] tx_wptr;
    reg  [2:0] tx_rptr;
    reg  [3:0] tx_count;

    wire tx_fifo_full  = (tx_count == 4'd8);
    wire tx_fifo_empty = (tx_count == 4'd0);

    // CPU 写 TXDATA 产生 push
    wire reg_sel_txdata = (wbs_adr_i[7:0] == 8'h00);
    wire tx_push = wbs_cyc_i & wbs_stb_i & wbs_we_i & reg_sel_txdata & ~tx_fifo_full;

    // 发送器准备好时从 FIFO pop
    wire       tx_phy_ready;
    reg  [7:0] tx_phy_data;
    reg        tx_phy_valid;
    wire       tx_pop = ~tx_fifo_empty & tx_phy_ready & ~tx_phy_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_wptr      <= 3'd0;
            tx_rptr      <= 3'd0;
            tx_count     <= 4'd0;
            tx_phy_valid <= 1'b0;
            tx_phy_data  <= 8'h00;
        end else begin
            // 数据写入 FIFO
            if (tx_push) begin
                tx_mem[tx_wptr] <= wbs_dat_i[7:0];
                tx_wptr <= tx_wptr + 3'd1;
            end

            // 驱动 PHY 发送
            if (tx_pop) begin
                tx_phy_data  <= tx_mem[tx_rptr];
                tx_rptr      <= tx_rptr + 3'd1;
                tx_phy_valid <= 1'b1;
            end else begin
                tx_phy_valid <= 1'b0;
            end

            // 更新计数器
            case ({tx_push, tx_pop})
                2'b10: tx_count <= tx_count + 4'd1;
                2'b01: tx_count <= tx_count - 4'd1;
                default: ; // 2'b00 或 2'b11 保持不变
            endcase
        end
    end

    // 例化物理层发送器
    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_tx (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_data (tx_phy_data),
        .tx_valid(tx_phy_valid),
        .tx_ready(tx_phy_ready),
        .txd     (uart_txd)
    );

    // =========================================================================
    // 3. 8 字节 RX FIFO
    // =========================================================================
    reg  [7:0] rx_mem [0:7];
    reg  [2:0] rx_wptr;
    reg  [2:0] rx_rptr;
    reg  [3:0] rx_count;

    wire rx_fifo_full  = (rx_count == 4'd8);
    wire rx_fifo_empty = (rx_count == 4'd0);

    // PHY 收到新字节产生 push
    wire [7:0] rx_phy_data;
    wire       rx_phy_valid;
    wire       rx_push = rx_phy_valid & ~rx_fifo_full;

    // CPU 读 RXDATA 产生 pop
    wire reg_sel_rxdata = (wbs_adr_i[7:0] == 8'h04);
    wire rx_pop = wbs_cyc_i & wbs_stb_i & ~wbs_we_i & reg_sel_rxdata & ~rx_fifo_empty;

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_wptr  <= 3'd0;
            rx_rptr  <= 3'd0;
            rx_count <= 4'd0;
        end else begin
            if (rx_push) begin
                rx_mem[rx_wptr] <= rx_phy_data;
                rx_wptr <= rx_wptr + 3'd1;
            end

            if (rx_pop) begin
                rx_rptr <= rx_rptr + 3'd1;
            end

            case ({rx_push, rx_pop})
                2'b10: rx_count <= rx_count + 4'd1;
                2'b01: rx_count <= rx_count - 4'd1;
                default: ;
            endcase
        end
    end

    // 例化物理层接收器
    uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_rx (
        .clk     (clk),
        .rst_n   (rst_n),
        .rxd     (uart_rxd),
        .rx_data (rx_phy_data),
        .rx_valid(rx_phy_valid)
    );

    // =========================================================================
    // 4. Wishbone 寄存器读写与 ACK (1 拍同步读)
    // =========================================================================
    wire reg_sel_txctrl = (wbs_adr_i[7:0] == 8'h08);
    wire reg_sel_rxctrl = (wbs_adr_i[7:0] == 8'h0C);
    wire reg_sel_ie     = (wbs_adr_i[7:0] == 8'h10);
    wire reg_sel_div    = (wbs_adr_i[7:0] == 8'h18);

    always @(posedge clk) begin
        if (!rst_n) begin
            reg_txctrl <= 1'b1;
            reg_rxctrl <= 1'b1;
            reg_ie     <= 2'b00;
            reg_div    <= CLKS_PER_BIT[15:0] - 16'd1;
            wbs_dat_o  <= 32'd0;
            wbs_ack_o  <= 1'b0;
        end else begin
            // ACK 生成 (对齐 1 拍同步延迟)
            wbs_ack_o <= wbs_cyc_i & wbs_stb_i;

            // 寄存器写入
            if (wbs_cyc_i & wbs_stb_i & wbs_we_i) begin
                if (reg_sel_txctrl) reg_txctrl <= wbs_dat_i[0];
                if (reg_sel_rxctrl) reg_rxctrl <= wbs_dat_i[0];
                if (reg_sel_ie)     reg_ie     <= wbs_dat_i[1:0];
                if (reg_sel_div)    reg_div    <= wbs_dat_i[15:0];
            end

            // 寄存器读取 (1 拍同步返回)
            if (wbs_cyc_i & wbs_stb_i & ~wbs_we_i) begin
                case (wbs_adr_i[7:0])
                    8'h00:   wbs_dat_o <= {tx_fifo_full, 31'd0};
                    8'h04:   wbs_dat_o <= {rx_fifo_empty, 23'd0, rx_fifo_empty ? 8'h00 : rx_mem[rx_rptr]};
                    8'h08:   wbs_dat_o <= {31'd0, reg_txctrl};
                    8'h0C:   wbs_dat_o <= {31'd0, reg_rxctrl};
                    8'h10:   wbs_dat_o <= {30'd0, reg_ie};
                    8'h14:   wbs_dat_o <= 32'd0; // IP
                    8'h18:   wbs_dat_o <= {16'd0, reg_div};
                    default: wbs_dat_o <= 32'd0;
                endcase
            end
        end
    end

endmodule
`default_nettype wire
