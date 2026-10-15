`default_nettype none
// -----------------------------------------------------------------------------
// wb_core_bridge — CPU dmem 端口 → Wishbone B4 Master 桥
//
// 功能：将 core.v 的原生 dmem 接口（BRAM 风格）转换为 Wishbone B4 Master 信号。
// 时序：S1 阶段为纯组合直通，不检查 ack，不生成流水线停顿。
// 所在层级：soc_top 内，core 与 wb_interconnect 之间。
// 升级路径 (S3)：增加 dmem_stall 输出至 hazard_unit，ack 未返回时冻结流水线。
// -----------------------------------------------------------------------------
module wb_core_bridge (
    /* verilator lint_off UNUSED */
    input  wire        clk,           // 预留 S3
    input  wire        rst_n,         // 预留 S3
    /* verilator lint_on  UNUSED */

    // ---- CPU 侧 (来自 core.v dmem 端口) ----
    input  wire [31:0] dmem_addr,
    input  wire [31:0] dmem_wdata,
    input  wire [3:0]  dmem_byte_we,  // 非零 = 写操作
    input  wire        dmem_req,
    output wire [31:0] dmem_rdata,

    // ---- Wishbone B4 Master 侧 ----
    output wire        wbm_cyc_o,
    output wire        wbm_stb_o,
    output wire        wbm_we_o,
    output wire [31:0] wbm_adr_o,
    output wire [31:0] wbm_dat_o,
    output wire [3:0]  wbm_sel_o,
    input  wire [31:0] wbm_dat_i,
    /* verilator lint_off UNUSED */
    input  wire        wbm_ack_i      // S1 不检查；S3 用于产生停顿
    /* verilator lint_on  UNUSED */
);

    // 总线周期与选通同时断言
    assign wbm_cyc_o = dmem_req;
    assign wbm_stb_o = dmem_req;

    // 写使能：任意字节写使能有效 → 写操作
    assign wbm_we_o  = |dmem_byte_we;

    // 地址与写数据直通
    assign wbm_adr_o = dmem_addr;
    assign wbm_dat_o = dmem_wdata;

    // 字节选择：写操作用 byte_we，读操作选全字
    assign wbm_sel_o = (|dmem_byte_we) ? dmem_byte_we : 4'b1111;

    // 读数据直通
    assign dmem_rdata = wbm_dat_i;

endmodule
`default_nettype wire
