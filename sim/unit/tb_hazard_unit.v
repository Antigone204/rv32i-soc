`timescale 1ns/1ps
`default_nettype none

module tb_hazard_unit;
    reg  [4:0] if_id_rs1;
    reg  [4:0] if_id_rs2;
    reg        id_ex_mem_read;
    reg  [4:0] id_ex_rd;
    reg        branch_taken;
    reg        jal;
    reg        jalr;

    wire stall_pc;
    wire stall_if_id;
    wire flush_if_id;
    wire flush_id_ex;

    hazard_unit dut (
        .if_id_rs1      (if_id_rs1),
        .if_id_rs2      (if_id_rs2),
        .id_ex_mem_read (id_ex_mem_read),
        .id_ex_rd       (id_ex_rd),
        .branch_taken   (branch_taken),
        .jal            (jal),
        .jalr           (jalr),
        .stall_pc       (stall_pc),
        .stall_if_id    (stall_if_id),
        .flush_if_id    (flush_if_id),
        .flush_id_ex    (flush_id_ex)
    );

    integer errors = 0;

    task check(
        input exp_stall_pc,
        input exp_stall_if_id,
        input exp_flush_if_id,
        input exp_flush_id_ex,
        input [127:0] tag
    );
        begin
            #1;
            if (stall_pc !== exp_stall_pc || stall_if_id !== exp_stall_if_id ||
                flush_if_id !== exp_flush_if_id || flush_id_ex !== exp_flush_id_ex) begin
                $display("FAIL [%0s]: got (stall_pc=%b stall_if_id=%b flush_if_id=%b flush_id_ex=%b), exp (%b %b %b %b)",
                         tag, stall_pc, stall_if_id, flush_if_id, flush_id_ex,
                         exp_stall_pc, exp_stall_if_id, exp_flush_if_id, exp_flush_id_ex);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s]", tag);
            end
        end
    endtask

    initial begin
        // 1. 无冲突
        if_id_rs1 = 5'd1; if_id_rs2 = 5'd2;
        id_ex_mem_read = 1'b0; id_ex_rd = 5'd3;
        branch_taken = 1'b0; jal = 1'b0; jalr = 1'b0;
        check(1'b0, 1'b0, 1'b0, 1'b0, "NORMAL_FLOW");

        // 2. Load-Use 冲突 (EX 级是 Load，读入 x1；ID 级要用 x1)
        id_ex_mem_read = 1'b1; id_ex_rd = 5'd1;
        check(1'b1, 1'b1, 1'b0, 1'b1, "LOAD_USE_RS1");

        // 3. Load 写入目标为 x0 (不触发停顿)
        id_ex_rd = 5'd0;
        check(1'b0, 1'b0, 1'b0, 1'b0, "LOAD_TO_X0_NO_STALL");

        // 4. 分支跳转成立 (控制冒险，冲刷流水线)
        id_ex_mem_read = 1'b0; id_ex_rd = 5'd5;
        branch_taken = 1'b1;
        check(1'b0, 1'b0, 1'b1, 1'b1, "BRANCH_TAKEN_FLUSH");

        // 5. JAL 跳转 (控制冒险，冲刷流水线)
        branch_taken = 1'b0; jal = 1'b1;
        check(1'b0, 1'b0, 1'b1, 1'b1, "JAL_FLUSH");

        if (errors == 0) begin
            $display("\n>>> ALL HAZARD UNIT TESTS PASSED <<<");
        end else begin
            $display("\n>>> %0d HAZARD UNIT TESTS FAILED <<<", errors);
        end
        $finish;
    end

endmodule
`default_nettype wire
