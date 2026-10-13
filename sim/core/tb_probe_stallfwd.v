`timescale 1ns/1ps
`default_nettype none

// -----------------------------------------------------------------------------
// tb_probe_stallfwd — 定向测试：EX 级停顿期间前推操作数锁存核验 (BUG-003 回归测试)
//
// 覆盖场景：
//   1. Case 1 (rs1 前推锁存)：
//      addi x3, 77
//      addi x1, 8
//      sw   x3, 4(x0)
//      lw   x4, 0(x1)  <- LW 在 EX 级触发 SW->LW 结构冒险停顿 1 拍。
//                        当拍 addi x1 在 WB 级前推 x1=8 给 rs1。
//                        下一拍 addi x1 退休离开流水线，LW 必须仍使用正确的基地址 8，
//                        成功读出 dmem[2]=55 到 x4，且 dmem[1]=77。
//
//   2. Case 2 (rs2 前推锁存)：
//      addi x8, 99     <- 产生 rs2 对应寄存器 x8 的值 99
//      sw   x3, 8(x0)  <- SW 在 MEM 级写 dmem[2]=77
//      lw   x9, 8(x0)  <- LW 在 EX 级触发停顿。指令偏移 offset=8 使得 inst[24:20]=8 (rs2=x8)。
//                        当拍 addi x8 在 WB 级前推 99 给 rs2。
//                        停顿使能 stall_id_ex 锁存 id_ex_rs2_data <= 99。
//                        下一拍 addi x8 退休离开流水线，验证 id_ex_rs2_data 稳定保持 99 且无 x 值。
//      addi x10, x8, 1 <- 验证 x8 架构寄存器最终正确写入 99，x10 得到 100。
//
// 验收要求：
//   - x4 = 55, dmem[1] = 77
//   - x8 = 99, x9 = 77, x10 = 100
//   - 仿真全程无未知态 'x'
// -----------------------------------------------------------------------------
module tb_probe_stallfwd;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    wire [31:0] imem_addr, dmem_addr, dmem_wdata, wb_pc, wb_wdata, pc_cyc, pc_ret;
    wire imem_req, dmem_req, wb_valid, wb_we;
    wire [3:0] dmem_byte_we;
    wire [4:0] wb_rd;
    reg  [31:0] imem_rdata, dmem_rdata;

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
        .perf_cycle  (pc_cyc),
        .perf_instret(pc_ret)
    );

    reg [31:0] imem [0:63];
    reg [31:0] dmem [0:63];
    integer k;

    // 存储器模型：真实 FPGA BRAM 行为 (时钟上升沿同步读出)
    always @(posedge clk) imem_rdata <= imem[imem_addr[7:2]];
    always @(posedge clk) dmem_rdata <= dmem[dmem_addr[7:2]];

    always @(posedge clk) begin
        if (dmem_req && |dmem_byte_we) begin
            if (dmem_byte_we[0]) dmem[dmem_addr[7:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_byte_we[1]) dmem[dmem_addr[7:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_byte_we[2]) dmem[dmem_addr[7:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_byte_we[3]) dmem[dmem_addr[7:2]][31:24] <= dmem_wdata[31:24];
        end
    end

    // 全局未知态检测器：严格检查总线接口、ALU 计算结果、写回提交以及停顿后的操作数是否含有未知态 'x'
    reg has_unknown = 0;
    always @(posedge clk) begin
        if (rst_n) begin
            // 1. 指令与数据总线请求地址与写入数据
            if (imem_req && $isunknown(imem_addr)) begin
                $display("  [ERROR-X] imem_addr 含有未知态 'x'! t=%0t imem_addr=%h", $time, imem_addr);
                has_unknown <= 1;
            end
            if (dmem_req && $isunknown(dmem_addr)) begin
                $display("  [ERROR-X] dmem_addr 含有未知态 'x'! t=%0t dmem_addr=%h", $time, dmem_addr);
                has_unknown <= 1;
            end
            if (dmem_req && |dmem_byte_we && $isunknown(dmem_wdata)) begin
                $display("  [ERROR-X] dmem_wdata 含有未知态 'x'! t=%0t dmem_wdata=%h", $time, dmem_wdata);
                has_unknown <= 1;
            end

            // 2. 指令执行与提交
            if (u_core.id_ex_valid) begin
                if ($isunknown(u_core.id_ex_pc) || $isunknown(u_core.ex_alu_out)) begin
                    $display("  [ERROR-X] EX 执行结果含有未知态 'x'! t=%0t pc=%h alu_out=%h",
                             $time, u_core.id_ex_pc, u_core.ex_alu_out);
                    has_unknown <= 1;
                end
                // 当处于 Load 访存时，基地址绝不能为 'x'
                if (u_core.id_ex_mem_read && $isunknown(u_core.ex_fwd_val_a)) begin
                    $display("  [ERROR-X] Load 基地址前推值含有未知态 'x'! t=%0t pc=%h fwd_a=%h",
                             $time, u_core.id_ex_pc, u_core.ex_fwd_val_a);
                    has_unknown <= 1;
                end
            end

            // 3. 提交级
            if (wb_valid) begin
                if ($isunknown(wb_pc) || $isunknown(wb_rd) || (wb_we && $isunknown(wb_wdata))) begin
                    $display("  [ERROR-X] 提交数据含有未知态 'x'! t=%0t pc=%h rd=%0d wdata=%h",
                             $time, wb_pc, wb_rd, wb_wdata);
                    has_unknown <= 1;
                end
            end
        end
    end

    // 提交日志跟踪
    always @(posedge clk) begin
        if (rst_n && wb_valid) begin
            if (wb_we)
                $display("  [COMMIT] t=%0t PC=0x%08x W_REG=x%-2d W_DATA=0x%08x (%0d)",
                         $time, wb_pc, wb_rd, wb_wdata, $signed(wb_wdata));
            else
                $display("  [COMMIT] t=%0t PC=0x%08x (无寄存器写入)", $time, wb_pc);
        end
    end

    // 监测 Case 2 中在停顿后（生产者已离开 WB）id_ex_rs2_data 是否保持为 99
    reg case2_rs2_latched_ok = 0;
    always @(posedge clk) begin
        if (rst_n) begin
            // 当 LW (PC=0x18) 处于 EX 级，且 forward_b 已经回到 2'b00 (前推源已退休)，检查 id_ex_rs2_data
            if (u_core.id_ex_pc == 32'h0000_0018 && u_core.forward_b == 2'b00 && u_core.id_ex_valid) begin
                if (u_core.id_ex_rs2_data === 32'd99) begin
                    case2_rs2_latched_ok <= 1;
                end
            end
        end
    end

    initial begin
        for (k = 0; k < 64; k = k + 1) begin
            imem[k] = 32'h0000_0013; // NOP
            dmem[k] = 32'd0;
        end

        // 初始内存数据
        dmem[0] = 32'd11;
        dmem[2] = 32'd55;

        // 指令序列
        // ------------------ Case 1: rs1 停顿前推 ------------------
        imem[0] = 32'h04D00193; // 0x00: addi x3, x0, 77
        imem[1] = 32'h00800093; // 0x04: addi x1, x0, 8
        imem[2] = 32'h00302223; // 0x08: sw   x3, 4(x0)  -> dmem[1] = 77
        imem[3] = 32'h0000A203; // 0x0C: lw   x4, 0(x1)  -> 期待读取 dmem[2]=55 到 x4

        // ------------------ Case 2: rs2 停顿前推 ------------------
        imem[4] = 32'h06300413; // 0x10: addi x8, x0, 99
        imem[5] = 32'h00302423; // 0x14: sw   x3, 8(x0)  -> dmem[2] = 77
        imem[6] = 32'h00802483; // 0x18: lw   x9, 8(x0)  -> inst[24:20]=8 (rs2=x8), 读取 dmem[2]=77 到 x9
        imem[7] = 32'h00140513; // 0x1C: addi x10, x8, 1 -> x10 = 100

        #15;
        rst_n = 1;

        #400;

        $display("\n================ BUG-003 EX 停顿前推锁存核验 ================");
        $display("Case 1 (rs1 前推锁存):");
        $display("  x1 = %0d (基地址)", u_core.u_regfile.regs[1]);
        $display("  dmem[1] = %0d (SW 目标内存)", dmem[1]);
        $display("  x4 = %0d (LW 读出数据，期待 55)", u_core.u_regfile.regs[4]);

        $display("Case 2 (rs2 前推锁存):");
        $display("  x8 = %0d (前推源操作数，期待 99)", u_core.u_regfile.regs[8]);
        $display("  dmem[2] = %0d (SW 目标内存，期待 77)", dmem[2]);
        $display("  x9 = %0d (LW 读出数据，期待 77)", u_core.u_regfile.regs[9]);
        $display("  x10 = %0d (使用 x8 运算，期待 100)", u_core.u_regfile.regs[10]);
        $display("  case2_rs2_latched_ok = %b (前推源退休后 rs2_data 成功维持 99)", case2_rs2_latched_ok);
        $display("  has_unknown = %b (全程无 'x' 信号)", has_unknown);
        $display("-------------------------------------------------------------");

        if (u_core.u_regfile.regs[4] == 32'd55 &&
            dmem[1] == 32'd77 &&
            u_core.u_regfile.regs[8] == 32'd99 &&
            u_core.u_regfile.regs[9] == 32'd77 &&
            u_core.u_regfile.regs[10] == 32'd100 &&
            case2_rs2_latched_ok == 1'b1 &&
            has_unknown == 1'b0) begin
            $display(">>> BUG-003 DIRECTED TEST PASSED <<<\n");
        end else begin
            $display(">>> BUG-003 DIRECTED TEST FAILED <<<\n");
            $fatal(1);
        end

        $finish;
    end
endmodule
`default_nettype wire
