`timescale 1ns/1ps
`default_nettype none
`include "alu_ops.vh"

module tb_alu;
    reg  [3:0]  alu_op;
    reg  [31:0] op_a;
    reg  [31:0] op_b;
    wire [31:0] alu_out;
    wire        zero;

    alu dut (
        .alu_op (alu_op),
        .op_a   (op_a),
        .op_b   (op_b),
        .alu_out(alu_out),
        .zero   (zero)
    );

    integer errors = 0;

    task check(input [31:0] expected, input exp_zero, input [127:0] tag);
        begin
            #1;
            if (alu_out !== expected || zero !== exp_zero) begin
                $display("FAIL [%0s]: out=0x%08h (exp 0x%08h), zero=%b (exp %b)",
                         tag, alu_out, expected, zero, exp_zero);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s]: 0x%08h", tag, alu_out);
            end
        end
    endtask

    initial begin
        // 1. ADD
        alu_op = `ALU_ADD; op_a = 32'd15; op_b = 32'd27;
        check(32'd42, 1'b0, "ADD_POS");

        // 2. SUB & Zero flag
        alu_op = `ALU_SUB; op_a = 32'd100; op_b = 32'd100;
        check(32'd0, 1'b1, "SUB_ZERO");

        // 3. SLL (移位只取低 5 位)
        alu_op = `ALU_SLL; op_a = 32'h0000_0001; op_b = 32'd35; // 35 % 32 = 3
        check(32'h0000_0008, 1'b0, "SLL_SHAMT5");

        // 4. SLT (有符号比较: -5 < 2 应为 1)
        alu_op = `ALU_SLT; op_a = -32'd5; op_b = 32'd2;
        check(32'd1, 1'b0, "SLT_NEG_POS");

        // 5. SLTU (无符号比较: 0xFFFF_FFFB 作为无符号大数，不小于 2，应为 0)
        alu_op = `ALU_SLTU; op_a = -32'd5; op_b = 32'd2;
        check(32'd0, 1'b1, "SLTU_UNSIGNED");

        // 6. SRA (算术右移，符号位扩展)
        alu_op = `ALU_SRA; op_a = 32'h8000_0000; op_b = 32'd4;
        check(32'hF800_0000, 1'b0, "SRA_SIGN_EXT");

        // 7. SRL (逻辑右移，高位补 0)
        alu_op = `ALU_SRL; op_a = 32'h8000_0000; op_b = 32'd4;
        check(32'h0800_0000, 1'b0, "SRL_ZERO_EXT");

        // 8. XOR, OR, AND
        alu_op = `ALU_XOR; op_a = 32'hFF00_AA55; op_b = 32'h00FF_AA55;
        check(32'hFFFF_0000, 1'b0, "XOR");

        alu_op = `ALU_OR; op_a = 32'h1200_0000; op_b = 32'h0034_0000;
        check(32'h1234_0000, 1'b0, "OR");

        alu_op = `ALU_AND; op_a = 32'hFFFF_0000; op_b = 32'h00FF_FF00;
        check(32'h00FF_0000, 1'b0, "AND");

        // 9. PASS_B
        alu_op = `ALU_PASS_B; op_a = 32'h1111_2222; op_b = 32'hABCD_1234;
        check(32'hABCD_1234, 1'b0, "PASS_B");

        if (errors == 0) begin
            $display("\n>>> ALL ALU TESTS PASSED <<<");
        end else begin
            $display("\n>>> %0d ALU TESTS FAILED <<<", errors);
        end
        $finish;
    end

endmodule
`default_nettype wire
