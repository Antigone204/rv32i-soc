`default_nettype none

// -----------------------------------------------------------------------------
// regfile — RV32I 32x32 位通用寄存器堆 (Register File)
//
// 功能：
//   - 维护 32 个 32 位通用寄存器 (x0 ~ x31)；
//   - x0 寄存器硬连线为零 (读恒为 0，写操作自动忽略)；
//   - 支持双异步/组合读端口 (rs1, rs2)；
//   - 支持单同步写端口 (rd, clk 上升沿写入)；
//   - 内置“写优先直通 (Internal Forwarding / Write-First Bypass)”：
//     当同一周期内写地址与读地址相同且写使能有效时，读端口直接读出即将写入的新数据，
//     防止 WB 级与 ID 级访问同一寄存器时读出脏旧数据。
//
// 接口：
//   raddr1, raddr2 : 读寄存器索引 (5 位，范围 0..31)
//   rdata1, rdata2 : 读出数据 (32 位)
//   waddr          : 写寄存器索引 (5 位)
//   wdata          : 写入数据 (32 位)
//   we             : 写使能 (1 = 允许写入)
//
// 时序：读操作纯组合逻辑；写操作 clk 上升沿同步写入。
// 所在流水级：ID 级读，WB 级写。
// -----------------------------------------------------------------------------
module regfile (
    input  wire        clk,
    input  wire        rst_n,

    // 读端口 1 (rs1)
    input  wire [4:0]  raddr1,
    output wire [31:0] rdata1,

    // 读端口 2 (rs2)
    input  wire [4:0]  raddr2,
    output wire [31:0] rdata2,

    // 写端口 (rd)
    input  wire        we,
    input  wire [4:0]  waddr,
    input  wire [31:0] wdata
);
    reg [31:0] regs [0:31];
    integer i;

    // 同步写操作 (x0 永远不写)
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'd0;
            end
        end else if (we && (waddr != 5'd0)) begin
            regs[waddr] <= wdata;
        end
    end

    // 组合读操作 + 内部写直通 (x0 读恒为 0)
    assign rdata1 = (raddr1 == 5'd0) ? 32'd0 :
                    (we && (waddr == raddr1)) ? wdata :
                    regs[raddr1];

    assign rdata2 = (raddr2 == 5'd0) ? 32'd0 :
                    (we && (waddr == raddr2)) ? wdata :
                    regs[raddr2];

endmodule
`default_nettype wire
