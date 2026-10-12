`timescale 1ns/1ps
`default_nettype none

module tb_imm_gen;
    reg  [31:0] inst;
    reg  [2:0]  imm_sel;
    wire [31:0] imm_out;

    imm_gen dut (
        .inst   (inst),
        .imm_sel(imm_sel),
        .imm_out(imm_out)
    );

    localparam [2:0] IMM_I = 3'd0,
                     IMM_S = 3'd1,
                     IMM_B = 3'd2,
                     IMM_U = 3'd3,
                     IMM_J = 3'd4;

    integer errors = 0;

    task check(input [31:0] expected, input [127:0] tag);
        begin
            #1;
            if (imm_out !== expected) begin
                $display("FAIL [%0s]: got 0x%08h, exp 0x%08h", tag, imm_out, expected);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s]: 0x%08h", tag, imm_out);
            end
        end
    endtask

    initial begin
        // 1. I-type: addi x1, x2, -5 (0xFFB10093) -> imm = -5 = 0xFFFF_FFFB
        imm_sel = IMM_I;
        inst = 32'hFFB10093; // imm[11:0] = 12'b1111_1111_1011 (-5)
        check(32'hFFFF_FFFB, "I_TYPE_NEG");

        // I-type 正数: addi x1, x0, 10 -> imm = 10
        inst = {12'd10, 5'd0, 3'b000, 5'd1, 7'b0010011};
        check(32'd10, "I_TYPE_POS");

        // 2. S-type: sw x1, -4(x2) -> imm = -4 (12'b1111_1111_1100)
        // inst[31:25] = 7'b1111111, inst[11:7] = 5'b11100
        imm_sel = IMM_S;
        inst = {7'b1111111, 5'd1, 5'd2, 3'b010, 5'b11100, 7'b0100011};
        check(32'hFFFF_FFFC, "S_TYPE_NEG");

        // 3. B-type: beq x1, x2, 16 -> 偏移量 16 (13 位: 0_0000_0001_0000)
        // imm[12]=0, imm[11]=0, imm[10:5]=0, imm[4:1]=4'b1000, imm[0]=0
        // inst[31]=0, inst[7]=0, inst[30:25]=6'b000000, inst[11:8]=4'b1000
        imm_sel = IMM_B;
        inst = {1'b0, 6'b000000, 5'd2, 5'd1, 3'b000, 4'b1000, 1'b0, 7'b1100011};
        check(32'd16, "B_TYPE_POS");

        // B-type 负偏移量: -8 -> 13'b1_1111_1111_1000
        // inst[31]=1, inst[7]=1, inst[30:25]=6'b111111, inst[11:8]=4'b1100
        inst = {1'b1, 6'b111111, 5'd2, 5'd1, 3'b000, 4'b1100, 1'b1, 7'b1100011};
        check(-32'd8, "B_TYPE_NEG");

        // 4. U-type: lui x1, 0x12345 -> imm = 0x12345000
        imm_sel = IMM_U;
        inst = {20'h12345, 5'd1, 7'b0110111};
        check(32'h1234_5000, "U_TYPE");

        // 5. J-type:
        // Case A: 偏移量 2048 (2^11) -> imm[11]=1 对应 inst[20]=1
        imm_sel = IMM_J;
        inst = {1'b0, 10'b0, 1'b1, 8'b0, 5'd1, 7'b1101111};
        check(32'd2048, "J_TYPE_2048");

        // Case B: 偏移量 4096 (2^12) -> imm[12]=1 对应 inst[12]=1 (inst[19:12]=8'b00000001)
        inst = {1'b0, 10'b0, 1'b0, 8'b00000001, 5'd1, 7'b1101111};
        check(32'd4096, "J_TYPE_4096");

        // Case C: 负偏移量 -2 -> 21'b1_1111_1111_1111_1111_1110
        inst = {1'b1, 10'h3FF, 1'b1, 8'hFF, 5'd1, 7'b1101111};
        check(-32'd2, "J_TYPE_NEG2");

        if (errors == 0) begin
            $display("\n>>> ALL IMM_GEN TESTS PASSED <<<");
        end else begin
            $display("\n>>> %0d IMM_GEN TESTS FAILED <<<", errors);
        end
        $finish;
    end

endmodule
`default_nettype wire
