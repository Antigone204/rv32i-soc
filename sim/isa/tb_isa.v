`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_isa — RISC-V 官方/通用 ISA 测试台 (RV32I Automation Testbench)
//
// 特性：
//   1. 仿真 64KB 双端口同步 RAM (对齐 FPGA BRAM 1 拍读延迟)；
//   2. 支持通过 +HEX=<file.hex> 动态加载 Hex 程序文件；
//   3. 监控 Mailbox (0x0000_1000) 写入：
//        - 写 1: PASS
//        - 写非 1: FAIL (test_num = 写值)
//   4. 具备可配超时保护 (默认 20000 周期，可通过 +TIMEOUT=<cycles> 调整)；
//   5. 支持通过 +TRACE=<log_file> 导出精准提交追踪 (wb_valid, wb_pc, wb_rd, wb_wdata)。
// -----------------------------------------------------------------------------
module tb_isa;
    reg clk = 1'b0;
    reg rst_n = 1'b0;

    always #5 clk = ~clk;

    // 总线接口
    wire [31:0] imem_addr;
    wire        imem_req;
    reg  [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_byte_we;
    wire        dmem_req;
    reg  [31:0] dmem_rdata;

    // 提交追踪接口
    wire        wb_valid;
    wire        wb_we;
    wire [31:0] wb_pc;
    wire [4:0]  wb_rd;
    wire [31:0] wb_wdata;
    wire [31:0] perf_cycle;
    wire [31:0] perf_instret;

    // 例化 RV32I 5 级流水线核
    core u_core (
        .clk         (clk),
        .rst_n       (rst_n),
        .imem_addr   (imem_addr),
        .imem_req    (imem_req),
        .imem_rdata  (imem_rdata),
        .dmem_addr   (dmem_addr),
        .dmem_wdata  (dmem_wdata),
        .dmem_byte_we(dmem_byte_we),
        .dmem_req    (dmem_req),
        .dmem_rdata  (dmem_rdata),
        .wb_valid    (wb_valid),
        .wb_we       (wb_we),
        .wb_pc       (wb_pc),
        .wb_rd       (wb_rd),
        .wb_wdata    (wb_wdata),
        .perf_cycle  (perf_cycle),
        .perf_instret(perf_instret)
    );

    // ---------------- 64KB 同步双端口 RAM (16384 个 32 位字) ----------------
    localparam RAM_WORDS = 16384;
    reg [7:0]  byte_mem [0:RAM_WORDS*4 - 1];
    reg [31:0] mem      [0:RAM_WORDS - 1];

    // 指令读口 (同步读出，1 拍延迟)
    always @(posedge clk) begin
        if (imem_addr[15:2] < RAM_WORDS)
            imem_rdata <= mem[imem_addr[15:2]];
        else
            imem_rdata <= 32'h0000_0013; // 超出范围注入 NOP
    end

    // 数据写口 (按字节使能)
    always @(posedge clk) begin
        if (dmem_req && (|dmem_byte_we) && (dmem_addr[15:2] < RAM_WORDS)) begin
            if (dmem_byte_we[0]) mem[dmem_addr[15:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_byte_we[1]) mem[dmem_addr[15:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_byte_we[2]) mem[dmem_addr[15:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_byte_we[3]) mem[dmem_addr[15:2]][31:24] <= dmem_wdata[31:24];
        end
    end

    // 数据读口 (同步读出)
    always @(posedge clk) begin
        if (dmem_addr[15:2] < RAM_WORDS)
            dmem_rdata <= mem[dmem_addr[15:2]];
        else
            dmem_rdata <= 32'd0;
    end

    // ---------------- 参数解析与内存初始化 ----------------
    reg [1023:0] hex_file = 0;
    reg [1023:0] trace_file = 0;
    integer trace_fd = 0;
    integer timeout_cycles = 20000;
    integer i;

    initial begin
        // 默认初始化全内存为 NOP
        for (i = 0; i < RAM_WORDS*4; i = i + 1) byte_mem[i] = 8'h0;
        for (i = 0; i < RAM_WORDS; i = i + 1) mem[i] = 32'h0000_0013;

        // 获取传参
        if (!$value$plusargs("HEX=%s", hex_file)) begin
            $display("[ERROR] No +HEX=<file> specified!");
            $finish;
        end

        void'($value$plusargs("TIMEOUT=%d", timeout_cycles));

        if ($value$plusargs("TRACE=%s", trace_file)) begin
            trace_fd = $fopen(trace_file, "w");
            if (trace_fd == 0) begin
                $display("[WARNING] Failed to open trace file %0s", trace_file);
            end
        end

        // 读入 hex 文件到字节数组，再组包到 32-bit 字内存
        $readmemh(hex_file, byte_mem);
        for (i = 0; i < RAM_WORDS; i = i + 1) begin
            mem[i] = {byte_mem[i*4+3], byte_mem[i*4+2], byte_mem[i*4+1], byte_mem[i*4+0]};
        end

        // 复位序列
        #20 rst_n = 1'b1;
    end

    // ---------------- 提交日志记录 ----------------
    always @(posedge clk) begin
        if (rst_n && wb_valid && trace_fd != 0) begin
            if (wb_we) begin
                $fdisplay(trace_fd, "core: pc=[0x%08h] rd=x%-2d val=0x%08h", wb_pc, wb_rd, wb_wdata);
            end else begin
                $fdisplay(trace_fd, "core: pc=[0x%08h]", wb_pc);
            end
        end
    end

    // ---------------- 退出判定 (Mailbox 与超时) ----------------
    always @(posedge clk) begin
        if (rst_n) begin
            // 监控对 0x0000_1000 的 Store 写入
            if (dmem_req && (|dmem_byte_we) && (dmem_addr == 32'h0000_1000)) begin
                if (dmem_wdata == 32'd1) begin
                    $display("[ISA-PASS] cycles=%0d instret=%0d", perf_cycle, perf_instret);
                end else begin
                    $display("[ISA-FAIL] test_num=%0d cycles=%0d pc=0x%08h", dmem_wdata, perf_cycle, wb_pc);
                end
                if (trace_fd != 0) begin
                    i = trace_fd;
                    trace_fd = 0;
                    $fclose(i);
                end
                $finish;
            end

            // 超时保护
            if (perf_cycle >= timeout_cycles) begin
                $display("[ISA-TIMEOUT] Exceeded %0d cycles at pc=0x%08h", timeout_cycles, wb_pc);
                if (trace_fd != 0) begin
                    i = trace_fd;
                    trace_fd = 0;
                    $fclose(i);
                end
                $finish;
            end
        end
    end

endmodule
`default_nettype wire
