`timescale 1ns/1ps
`default_nettype none
`include "rtl/core/alu_ops.vh"

module tb_decoder;
    reg  [31:0] inst;

    wire [4:0]  rs1, rs2, rd;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [2:0]  imm_sel;
    wire [3:0]  alu_op;
    wire        alu_src_a;
    wire        alu_src_b;
    wire        mem_read;
    wire        mem_write;
    wire        reg_write;
    wire [1:0]  wb_src_sel;
    wire        branch;
    wire        jal;
    wire        jalr;
    wire        illegal_inst;
    wire        muldiv_en;

    decoder dut (
        .inst        (inst),
        .rs1         (rs1),
        .rs2         (rs2),
        .rd          (rd),
        .funct3      (funct3),
        .funct7      (funct7),
        .imm_sel     (imm_sel),
        .alu_op      (alu_op),
        .alu_src_a   (alu_src_a),
        .alu_src_b   (alu_src_b),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .reg_write   (reg_write),
        .wb_src_sel  (wb_src_sel),
        .branch      (branch),
        .jal         (jal),
        .jalr        (jalr),
        .illegal_inst(illegal_inst),
        .muldiv_en   (muldiv_en)
    );

    integer errors = 0;

    task check_ctrl(
        input [3:0] exp_alu_op,
        input       exp_src_a,
        input       exp_src_b,
        input       exp_mem_r,
        input       exp_mem_w,
        input       exp_reg_w,
        input [1:0] exp_wb_src,
        input [127:0] tag
    );
        begin
            #1;
            if (alu_op !== exp_alu_op || alu_src_a !== exp_src_a || alu_src_b !== exp_src_b ||
                mem_read !== exp_mem_r || mem_write !== exp_mem_w || reg_write !== exp_reg_w ||
                wb_src_sel !== exp_wb_src) begin
                $display("FAIL [%0s]: alu_op=%0d (exp %0d) reg_w=%b (exp %b) mem_r=%b (exp %b)",
                         tag, alu_op, exp_alu_op, reg_write, exp_reg_w, mem_read, exp_mem_r);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s]", tag);
            end
        end
    endtask

    initial begin
        // 1. ADD x1, x2, x3: 0000000_00011_00010_000_00001_0110011
        inst = {7'b0000000, 5'd3, 5'd2, 3'b000, 5'd1, 7'b0110011};
        check_ctrl(`ALU_ADD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'd0, "ADD");
        if (rs1 !== 5'd2 || rs2 !== 5'd3 || rd !== 5'd1) begin
            $display("FAIL [ADD registers]"); errors = errors + 1;
        end

        // 2. SUB x1, x2, x3: funct7[5]=1
        inst = {7'b0100000, 5'd3, 5'd2, 3'b000, 5'd1, 7'b0110011};
        check_ctrl(`ALU_SUB, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 2'd0, "SUB");

        // 3. ADDI x1, x2, 10
        inst = {12'd10, 5'd2, 3'b000, 5'd1, 7'b0010011};
        check_ctrl(`ALU_ADD, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 2'd0, "ADDI");

        // 4. LW x1, 4(x2)
        inst = {12'd4, 5'd2, 3'b010, 5'd1, 7'b0000011};
        check_ctrl(`ALU_ADD, 1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 2'd1, "LW");

        // 5. SW x3, 8(x4)
        inst = {7'b0000000, 5'd3, 5'd4, 3'b010, 5'd8, 7'b0100011};
        check_ctrl(`ALU_ADD, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 2'd0, "SW");

        // 6. BEQ x1, x2, offset
        inst = {7'b0000000, 5'd2, 5'd1, 3'b000, 5'd0, 7'b1100011};
        #1;
        if (branch !== 1'b1 || reg_write !== 1'b0) begin
            $display("FAIL [BEQ branch control]"); errors = errors + 1;
        end else begin
            $display("PASS [BEQ]");
        end

        // 7. JAL x1, offset
        inst = {25'd0, 7'b1101111};
        #1;
        if (jal !== 1'b1 || reg_write !== 1'b1 || wb_src_sel !== 2'd2) begin
            $display("FAIL [JAL control]"); errors = errors + 1;
        end else begin
            $display("PASS [JAL]");
        end

        // 8. LUI x1, 0x12345
        inst = {20'h12345, 5'd1, 7'b0110111};
        check_ctrl(`ALU_PASS_B, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 2'd0, "LUI");

        // 9. AUIPC x1, 0x12345
        inst = {20'h12345, 5'd1, 7'b0010111};
        check_ctrl(`ALU_ADD, 1'b1, 1'b1, 1'b0, 1'b0, 1'b1, 2'd0, "AUIPC");

        // 10. MUL x1, x2, x3: funct7=7'b0000001, funct3=3'b000
        inst = {7'b0000001, 5'd3, 5'd2, 3'b000, 5'd1, 7'b0110011};
        #1;
        if (muldiv_en !== 1'b1 || reg_write !== 1'b1 || wb_src_sel !== 2'd0) begin
            $display("FAIL [MUL decode]"); errors = errors + 1;
        end else begin
            $display("PASS [MUL]");
        end

        // 11. DIV x1, x2, x3: funct7=7'b0000001, funct3=3'b100
        inst = {7'b0000001, 5'd3, 5'd2, 3'b100, 5'd1, 7'b0110011};
        #1;
        if (muldiv_en !== 1'b1 || reg_write !== 1'b1 || wb_src_sel !== 2'd0) begin
            $display("FAIL [DIV decode]"); errors = errors + 1;
        end else begin
            $display("PASS [DIV]");
        end

        if (errors == 0) begin
            $display("\n>>> ALL DECODER TESTS PASSED <<<");
        end else begin
            $display("\n>>> %0d DECODER TESTS FAILED <<<", errors);
        end
        $finish;
    end

endmodule
`default_nettype wire
