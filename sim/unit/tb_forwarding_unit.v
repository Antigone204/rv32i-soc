`timescale 1ns/1ps
`default_nettype none

module tb_forwarding_unit;
    reg  [4:0] id_ex_rs1;
    reg  [4:0] id_ex_rs2;
    reg  [4:0] ex_mem_rd;
    reg        ex_mem_reg_write;
    reg  [4:0] mem_wb_rd;
    reg        mem_wb_reg_write;

    wire [1:0] forward_a;
    wire [1:0] forward_b;

    forwarding_unit dut (
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .ex_mem_rd       (ex_mem_rd),
        .ex_mem_reg_write(ex_mem_reg_write),
        .mem_wb_rd       (mem_wb_rd),
        .mem_wb_reg_write(mem_wb_reg_write),
        .forward_a       (forward_a),
        .forward_b       (forward_b)
    );

    integer errors = 0;

    task check(input [1:0] exp_a, input [1:0] exp_b, input [127:0] tag);
        begin
            #1;
            if (forward_a !== exp_a || forward_b !== exp_b) begin
                $display("FAIL [%0s]: fwd_a=%b (exp %b), fwd_b=%b (exp %b)",
                         tag, forward_a, exp_a, forward_b, exp_b);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s]", tag);
            end
        end
    endtask

    initial begin
        // 1. 无任何数据冲突
        id_ex_rs1 = 5'd1; id_ex_rs2 = 5'd2;
        ex_mem_rd = 5'd3; ex_mem_reg_write = 1'b1;
        mem_wb_rd = 5'd4; mem_wb_reg_write = 1'b1;
        check(2'b00, 2'b00, "NO_HAZARD");

        // 2. EX-EX 前推 (前一条写 x1，当前读 x1)
        ex_mem_rd = 5'd1; ex_mem_reg_write = 1'b1;
        check(2'b10, 2'b00, "EX_EX_A");

        // 3. MEM-EX 前推 (前前条写 x2，当前读 x2)
        ex_mem_rd = 5'd3; ex_mem_reg_write = 1'b1;
        mem_wb_rd = 5'd2; mem_wb_reg_write = 1'b1;
        check(2'b00, 2'b01, "MEM_EX_B");

        // 4. 写 x0 不触发前推 (x0 永远不应被前推)
        id_ex_rs1 = 5'd0;
        ex_mem_rd = 5'd0; ex_mem_reg_write = 1'b1;
        mem_wb_rd = 5'd0; mem_wb_reg_write = 1'b1;
        check(2'b00, 2'b00, "IGNORE_X0");

        // 5. 优先级陷阱：前一条与前前条都写 x1，当前指令读 x1
        // 此时必须选最新的前一条 (EX-EX: 2'b10)，绝不能选 2'b01
        id_ex_rs1 = 5'd1;
        ex_mem_rd = 5'd1; ex_mem_reg_write = 1'b1;
        mem_wb_rd = 5'd1; mem_wb_reg_write = 1'b1;
        check(2'b10, 2'b00, "PRIORITY_EX_OVER_MEM");

        if (errors == 0) begin
            $display("\n>>> ALL FORWARDING UNIT TESTS PASSED <<<");
        end else begin
            $display("\n>>> %0d FORWARDING UNIT TESTS FAILED <<<", errors);
        end
        $finish;
    end

endmodule
`default_nettype wire
