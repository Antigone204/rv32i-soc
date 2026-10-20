`default_nettype none
// -----------------------------------------------------------------------------
// wb_sram — 64KB 双端口同步 SRAM (Dual-Port Synchronous SRAM)
//
// 功能：
//   - Port A: CPU 指令取指专用端口 (直连 core.v 的 imem_*，不经过总线)，只读，1 拍延迟；
//   - Port B: Wishbone B4 数据读写从设备端口 (SRAM 区域 0x0000_0000 ~ 0x0000_FFFF)，
//             支持 4 字节按位使能写入，1 拍同步读延迟，单周期 ACK 响应；
//   - 可推断为 FPGA True Dual-Port Block RAM (DRM)。
//
// 参数：
//   WORDS         : 32 位字容量，默认 16384 (64 KB)
//   MEM_INIT_FILE : 初始固件十六进制字文件路径（FPGA 综合 BRAM 初始化）
// -----------------------------------------------------------------------------
module wb_sram #(
    parameter integer WORDS         = 16384,
    parameter         MEM_INIT_FILE = ""
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Port A: 指令取指 (直连 core.imem_*) ----
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] imem_addr,
    /* verilator lint_on  UNUSEDSIGNAL */
    output reg  [31:0] imem_rdata,

    // ---- Port B: Wishbone Slave (数据访问) ----
    input  wire        wbs_cyc_i,
    input  wire        wbs_stb_i,
    input  wire        wbs_we_i,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] wbs_adr_i,
    /* verilator lint_on  UNUSEDSIGNAL */
    input  wire [31:0] wbs_dat_i,
    input  wire [3:0]  wbs_sel_i,
    output reg  [31:0] wbs_dat_o,
    output reg         wbs_ack_o
);
    localparam integer AW = $clog2(WORDS);

    // 存储器阵列定义 (可综合推断为 BRAM)
    reg [31:0] mem [0:WORDS-1];

    // FPGA BRAM 初始镜像综合加载 (PDS 综合识别)
    initial begin
        if (MEM_INIT_FILE != "") begin
            $readmemh(MEM_INIT_FILE, mem);
        end
    end

    wire [AW-1:0] word_addr_a = imem_addr[AW+1:2];
    wire [AW-1:0] word_addr_b = wbs_adr_i[AW+1:2];

    // =========================================================================
    // Port A: 指令同步读取 (1 拍延迟)
    // =========================================================================
    always @(posedge clk) begin
        imem_rdata <= mem[word_addr_a];
    end

    // =========================================================================
    // Port B: 数据同步读写 (字节使能写 + 1 拍读)
    // =========================================================================
    always @(posedge clk) begin
        if (wbs_cyc_i & wbs_stb_i & wbs_we_i) begin
            if (wbs_sel_i[0]) mem[word_addr_b][ 7: 0] <= wbs_dat_i[ 7: 0];
            if (wbs_sel_i[1]) mem[word_addr_b][15: 8] <= wbs_dat_i[15: 8];
            if (wbs_sel_i[2]) mem[word_addr_b][23:16] <= wbs_dat_i[23:16];
            if (wbs_sel_i[3]) mem[word_addr_b][31:24] <= wbs_dat_i[31:24];
        end
        wbs_dat_o <= mem[word_addr_b];
    end

    // =========================================================================
    // Port B ACK 响应 (单周期脉冲)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            wbs_ack_o <= 1'b0;
        end else begin
            wbs_ack_o <= wbs_cyc_i & wbs_stb_i;
        end
    end

`ifdef SIM
    // 仿真时支持通过 +HEX=<file> 参数加载初始程序映像
    reg [1023:0] hex_file = 0;
    reg [7:0]    byte_mem [0:WORDS*4 - 1];
    integer      i_init;

    initial begin
        for (i_init = 0; i_init < WORDS; i_init = i_init + 1) begin
            mem[i_init] = 32'h0000_0013; // 默认初始化为 NOP
        end
        if ($value$plusargs("HEX=%s", hex_file)) begin
            $readmemh(hex_file, byte_mem);
            for (i_init = 0; i_init < WORDS; i_init = i_init + 1) begin
                mem[i_init] = {byte_mem[i_init*4+3], byte_mem[i_init*4+2],
                               byte_mem[i_init*4+1], byte_mem[i_init*4+0]};
            end
        end
    end
`endif

endmodule
`default_nettype wire
