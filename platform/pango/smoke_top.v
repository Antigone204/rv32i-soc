`default_nettype none
// -----------------------------------------------------------------------------
// smoke_top — 平台冒烟测试顶层（W1）
//
// 目的：在写 CPU 之前，先跑通"PDS 综合 → 远程平台烧录 → 串口 / LED 观测"这条流程。
// 功能：
//   1. LED[0] 以约 1 Hz 闪烁（证明时钟和烧录正常）；
//   2. 上电后串口打印一行 banner（证明 UART TX 和波特率正确）；
//   3. 之后把收到的每个字节原样回显，并显示在 LED[7:1] 上（证明 UART RX 正常）。
// 参数：
//   CLK_HZ —— 板载晶振频率，**需要按平台文档确认**。
//             频率填错的典型现象：串口乱码，LED 闪烁快慢不对。
// 复位：内部上电复位计数器，不依赖外部按键。
// -----------------------------------------------------------------------------
module smoke_top #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD   = 115_200
) (
    input  wire       sys_clk,
    input  wire       uart_rxd,
    output wire       uart_txd,
    output wire [7:0] led
);
    localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

    // ---------------- 上电复位 ----------------
    // FPGA 上寄存器初值由 bitstream 加载，所以这里用初值实现上电复位是有意为之。
    /* verilator lint_off PROCASSINIT */
    reg [7:0] por_cnt = 8'd0;
    /* verilator lint_on PROCASSINIT */
    wire      rst_n   = &por_cnt;
    always @(posedge sys_clk) begin
        if (!rst_n) por_cnt <= por_cnt + 8'd1;
    end

    // ---------------- LED 心跳 ----------------
    localparam integer HALF_SEC = CLK_HZ / 2;
    localparam integer HB_W     = $clog2(HALF_SEC);
    localparam integer HB_MAX   = HALF_SEC - 1;
    reg [HB_W-1:0] hb_cnt;
    reg            hb;
    always @(posedge sys_clk) begin
        if (!rst_n) begin
            hb_cnt <= {HB_W{1'b0}};
            hb     <= 1'b0;
        end else if (hb_cnt == HB_MAX[HB_W-1:0]) begin
            hb_cnt <= {HB_W{1'b0}};
            hb     <= ~hb;
        end else begin
            hb_cnt <= hb_cnt + 1'b1;
        end
    end

    // ---------------- UART ----------------
    wire [7:0] rx_data;
    wire       rx_valid;
    reg  [7:0] tx_data;
    reg        tx_valid;
    wire       tx_ready;
    reg  [6:0] last_rx;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(sys_clk), .rst_n(rst_n), .rxd(uart_rxd),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(sys_clk), .rst_n(rst_n),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .txd(uart_txd)
    );

    // ---------------- 32 字节回显 FIFO ----------------
    reg [7:0] fifo_mem [0:31];
    reg [4:0] fifo_wptr;
    reg [4:0] fifo_rptr;
    reg [5:0] fifo_count;

    reg       banner_done;
    wire fifo_empty = (fifo_count == 6'd0);
    wire fifo_full  = (fifo_count == 6'd32);

    wire fifo_push = rx_valid && !fifo_full;
    wire fifo_pop  = banner_done && !fifo_empty && tx_ready && !tx_valid;

    always @(posedge sys_clk) begin
        if (!rst_n) begin
            fifo_wptr  <= 5'd0;
            fifo_rptr  <= 5'd0;
            fifo_count <= 6'd0;
        end else begin
            if (fifo_push) begin
                fifo_mem[fifo_wptr] <= rx_data;
                fifo_wptr           <= fifo_wptr + 5'd1;
            end
            if (fifo_pop) begin
                fifo_rptr <= fifo_rptr + 5'd1;
            end
            case ({fifo_push, fifo_pop})
                2'b10: fifo_count <= fifo_count + 6'd1;
                2'b01: fifo_count <= fifo_count - 6'd1;
                default: ;
            endcase
        end
    end

    // banner ROM
    localparam integer   BANNER_LEN  = 24;
    localparam integer   BANNER_LAST = BANNER_LEN - 1;
    function [7:0] banner_char(input [4:0] i);
        case (i)
            5'd0:  banner_char = "R";  5'd1:  banner_char = "V";
            5'd2:  banner_char = "3";  5'd3:  banner_char = "2";
            5'd4:  banner_char = " ";  5'd5:  banner_char = "s";
            5'd6:  banner_char = "m";  5'd7:  banner_char = "o";
            5'd8:  banner_char = "k";  5'd9:  banner_char = "e";
            5'd10: banner_char = " ";  5'd11: banner_char = "t";
            5'd12: banner_char = "e";  5'd13: banner_char = "s";
            5'd14: banner_char = "t";  5'd15: banner_char = " ";
            5'd16: banner_char = "O";  5'd17: banner_char = "K";
            5'd18: banner_char = "!";  5'd19: banner_char = " ";
            5'd20: banner_char = ">";  5'd21: banner_char = " ";
            5'd22: banner_char = 8'h0D; 5'd23: banner_char = 8'h0A;
            default: banner_char = 8'h00;
        endcase
    endfunction

    reg [4:0] banner_idx;

    always @(posedge sys_clk) begin
        if (!rst_n) begin
            banner_idx  <= 5'd0;
            banner_done <= 1'b0;
            tx_valid    <= 1'b0;
            tx_data     <= 8'h00;
            last_rx     <= 7'd0;
        end else begin
            tx_valid <= 1'b0;
            if (rx_valid) begin
                last_rx <= rx_data[6:0];
            end

            if (!banner_done) begin
                if (tx_ready && !tx_valid) begin
                    tx_data  <= banner_char(banner_idx);
                    tx_valid <= 1'b1;
                    if (banner_idx == BANNER_LAST[4:0]) banner_done <= 1'b1;
                    banner_idx <= banner_idx + 5'd1;
                end
            end else if (fifo_pop) begin
                tx_data  <= fifo_mem[fifo_rptr];
                tx_valid <= 1'b1;
            end
        end
    end

    assign led = {last_rx, hb};
endmodule
`default_nettype wire
