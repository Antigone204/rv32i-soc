`ifndef ALU_OPS_VH
`define ALU_OPS_VH

// RV32I ALU 操作码定义 (4 位宽)
`define ALU_ADD    4'd0   // 加法
`define ALU_SUB    4'd1   // 减法
`define ALU_SLL    4'd2   // 逻辑左移 (Shift Left Logical)
`define ALU_SLT    4'd3   // 有符号小于比较 (Set Less Than)
`define ALU_SLTU   4'd4   // 无符号小于比较 (Set Less Than Unsigned)
`define ALU_XOR    4'd5   // 按位异或
`define ALU_SRL    4'd6   // 逻辑右移 (Shift Right Logical)
`define ALU_SRA    4'd7   // 算术右移 (Shift Right Arithmetic)
`define ALU_OR     4'd8   // 按位或
`define ALU_AND    4'd9   // 按位与
`define ALU_PASS_B 4'd10  // 直通操作数 B (例如 LUI)

`endif
