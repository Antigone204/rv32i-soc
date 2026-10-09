`default_nettype none
// -----------------------------------------------------------------------------
// uart_rx — 8N1 UART 接收器
//
// 接口：
//   rx_valid 是单周期脉冲，同一周期 rx_data 有效。
// 参数：
//   CLKS_PER_BIT = 时钟频率 / 波特率
// 时序：
//   rxd 先经过两级同步器（跨时钟域）；检测到下降沿后等待半个 bit 时间，
//   在起始位中点确认仍为 0，此后每隔一个 bit 时间在数据位中点采样。
//   停止位不为 1 时丢弃该字节（帧错误）。
// -----------------------------------------------------------------------------
module uart_rx #(
    parameter integer CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rxd,
    output reg  [7:0] rx_data,
    output reg        rx_valid
);
    localparam integer CW = $clog2(CLKS_PER_BIT);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg       rxd_s1, rxd_s2;   // 同步器
    reg [1:0] state;
    reg [CW-1:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] shreg;

    always @(posedge clk) begin
        if (!rst_n) begin
            rxd_s1 <= 1'b1;
            rxd_s2 <= 1'b1;
        end else begin
            rxd_s1 <= rxd;
            rxd_s2 <= rxd_s1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            clk_cnt  <= {CW{1'b0}};
            bit_idx  <= 3'd0;
            shreg    <= 8'h00;
            rx_data  <= 8'h00;
            rx_valid <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    clk_cnt <= {CW{1'b0}};
                    if (!rxd_s2) state <= S_START;
                end
                S_START: begin
                    if (clk_cnt == CLKS_PER_BIT[CW-1:0] / 2) begin
                        clk_cnt <= {CW{1'b0}};
                        if (!rxd_s2) begin
                            state   <= S_DATA;
                            bit_idx <= 3'd0;
                        end else begin
                            state <= S_IDLE;   // 毛刺，不是真正的起始位
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT[CW-1:0] - 1'b1) begin
                        clk_cnt <= {CW{1'b0}};
                        shreg   <= {rxd_s2, shreg[7:1]};
                        if (bit_idx == 3'd7) state <= S_STOP;
                        bit_idx <= bit_idx + 3'd1;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT[CW-1:0] - 1'b1) begin
                        clk_cnt <= {CW{1'b0}};
                        state   <= S_IDLE;
                        if (rxd_s2) begin
                            rx_data  <= shreg;
                            rx_valid <= 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire
