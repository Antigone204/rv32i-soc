`default_nettype none
// -----------------------------------------------------------------------------
// uart_tx — 8N1 UART 发送器
//
// 接口：
//   tx_valid/tx_ready 握手：tx_valid && tx_ready 的那个周期锁存 tx_data 并开始发送。
//   发送期间 tx_ready = 0。
// 参数：
//   CLKS_PER_BIT = 时钟频率 / 波特率（例如 50 MHz / 115200 ≈ 434）
// 时序：
//   帧格式：起始位(0) + 8 数据位(LSB 先发) + 停止位(1)，空闲时 txd = 1。
// -----------------------------------------------------------------------------
module uart_tx #(
    parameter integer CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready,
    output reg        txd
);
    localparam integer CW = $clog2(CLKS_PER_BIT);
    /* verilator lint_off WIDTHTRUNC */
    localparam [CW-1:0] CNT_MAX = (CLKS_PER_BIT - 1);
    /* verilator lint_on  WIDTHTRUNC */

    reg [CW-1:0] clk_cnt;
    reg [3:0]    bit_idx;     // 0 = 起始位, 1..8 = 数据位, 9 = 停止位
    reg [7:0]    shreg;
    reg          busy;

    assign tx_ready = ~busy;

    always @(posedge clk) begin
        if (!rst_n) begin
            busy    <= 1'b0;
            txd     <= 1'b1;
            clk_cnt <= {CW{1'b0}};
            bit_idx <= 4'd0;
            shreg   <= 8'h00;
        end else if (!busy) begin
            txd <= 1'b1;
            if (tx_valid) begin
                busy    <= 1'b1;
                shreg   <= tx_data;
                bit_idx <= 4'd0;
                clk_cnt <= {CW{1'b0}};
                txd     <= 1'b0;          // 起始位
            end
        end else begin
            if (clk_cnt == CNT_MAX) begin
                clk_cnt <= {CW{1'b0}};
                if (bit_idx == 4'd9) begin
                    busy <= 1'b0;         // 停止位发送完毕
                    txd  <= 1'b1;
                end else begin
                    bit_idx <= bit_idx + 4'd1;
                    if (bit_idx == 4'd8) begin
                        txd <= 1'b1;      // 停止位
                    end else begin
                        txd   <= shreg[0];
                        shreg <= {1'b0, shreg[7:1]};
                    end
                end
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
