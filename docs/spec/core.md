# RV32I 处理器核心规格说明书 (Core Spec)

本文档定义 `radiant-heisenberg` 项目所采用的 RV32I 5 级流水线处理器微架构规格。在编写对应 RTL 前必须先完成并评审本 Spec。

---

## 1. 体系结构与指令集支持

- **架构标准**：RISC-V 32 位基础整数指令集（RV32I User-Level ISA v2.2）。
- **寄存器组**：
  - 32 个 32 位通用整数寄存器 `x0` - `x31`，其中 `x0` 硬连线为零。
- **支持指令子集**（37 条核心指令）：
  - **算术/逻辑计算 (R-type)**: `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`
  - **立即数计算 (I-type)**: `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI`
  - **访存加载 (I-type Load)**: `LB`, `LH`, `LW`, `LBU`, `LHU`
  - **访存存储 (S-type Store)**: `SB`, `SH`, `SW`
  - **条件分支 (B-type Branch)**: `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`
  - **无条件跳转 (J-type / I-type)**: `JAL`, `JALR`
  - **长立即数构建 (U-type)**: `LUI`, `AUIPC`
  - **系统与控制 (SYSTEM)**: `ECALL`, `EBREAK`, `FENCE` (当做 NOP), 以及核心 CSR 读写 (`CSRRW`, `CSRRS`, `CSRRC`) 【待实现：Tier B 任务】

---

## 2. 流水线阶段划分与职责

采用经典的 Patterson & Hennessy 5 级静态流水线结构：

```
+----+     +----+     +----+     +----+     +----+
| IF | --> | ID | --> | EX | --> | MEM| --> | WB |
+----+     +----+     +----+     +----+     +----+
```

### 2.1 IF (Instruction Fetch - 取指级)
- **输入**：`clk`, `rst_n`, `stall_pc`, `flush_if_id`, 跳转/分支目标 `branch_target`
- **逻辑**：
  - PC 生成：当流水线正常前进时，`if_pc_plus_4 = if_pc + 4`；发生分支跳转时，`if_next_pc = branch_target`；
  - 存储器时序适配（BRAM 1 拍读延迟）：取指地址改用 `if_next_pc` 提前一拍发出；停顿时保持 `if_pc` 地址不变；
- **流水线寄存器 (IF/ID)**：保存 `if_id_pc`, `if_id_inst`, `if_id_valid`。支持写使能 `!stall_if_id` 与同步清零 `flush_if_id`。

### 2.2 ID (Instruction Decode - 译码与读寄存器)
- **输入**：`if_id_pc`, `if_id_inst`, `if_id_valid`, 写回端口（`wb_reg_write`, `wb_rd`, `wb_wdata`）
- **逻辑**：
  - 译码器：解析 opcode, funct3, funct7，生成 ALU 运算类型、立即数字段类型、访存控制掩码；
  - 寄存器堆读：读出 `rs1_data` 和 `rs2_data`（内部支持内部直通；为推断 FPGA 分布式 RAM 取消通用寄存器复位循环，仅 x0 保持硬件恒零）；
  - 立即数生成（Immediate Generator）：按照 RV32I 标准提取 I/S/B/U/J 类型的符号扩展立即数；
- **流水线寄存器 (ID/EX)**：传递 PC、操作数、立即数、寄存器索引（rs1, rs2, rd）、各控制信号以及 `id_ex_valid`。

### 2.3 EX (Execute - 执行级)
- **输入**：ID/EX 寄存器内容、来自 MEM 级与 WB 级的前推数据
- **逻辑**：
  - 前推选择多路器：根据 `Forwarding Unit` 的控制信号，将操作数源选择为寄存器原始值、MEM 级运算结果或 WB 级写回结果；
  - ALU 运算：执行加减、移位、逻辑、比较等操作；
  - 分支计算与裁决：计算跳转目标地址 `pc + imm` / `rs1 + imm`，并比较操作数得出分支跳转是否发生（`branch_taken`，受 `id_ex_valid` 门控）；
  - 控制信号：若分支判定成功或执行无条件跳转，向 Hazard Unit 发送冲刷信号。
- **流水线寄存器 (EX/MEM)**：保存 PC、ALU 结果、写内存数据、rd、控制信号以及 `ex_mem_valid`。

### 2.4 MEM (Memory Access - 访存级)
- **输入**：EX/MEM 寄存器内容
- **逻辑**：
  - 数据存储器接口：读地址在 EX 级提前发出 (`ex_alu_out`) 以适配 BRAM 同步读延迟；写地址与数据在 MEM 级维持 (`ex_mem_alu_out`)；
  - Store 信号处理：将 `rs2` 写入数据按字节偏移生成掩码 `dmem_byte_we[3:0]` 与对齐数据（受 `ex_mem_valid` 保护，防止气泡误写）；
  - Load 符号扩展：从 `dmem_rdata` 中按 funct3 对齐并执行字节/半字符号或零扩展（LB/LH/LBU/LHU）。
- **流水线寄存器 (MEM/WB)**：保存 PC、ALU 结果、访存读出数据、rd、写回源选择以及 `mem_wb_valid`。

### 2.5 WB (Write Back - 写回级)
- **输入**：MEM/WB 寄存器内容
- **逻辑**：
  - 多路选择写回数据：ALU 计算结果、Load 读出数据、或跳转链接地址 `pc + 4`；
  - 驱动通用寄存器堆的写入端口（`mem_wb_valid && mem_wb_reg_write && rd != 0` 时有效）；
  - 导出 `wb_valid = mem_wb_valid` 追踪提交，不论该指令是否写回寄存器。

---

## 3. 冲突与冒险处理 (Hazard & Forwarding)

### 3.1 数据前推单元 (Forwarding Unit)
用于解决 RAW (Read-After-Write) 数据依赖，消灭计算指令间的所有气泡：
- **EX-EX 前推**：当 `ex_mem_valid && ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1)` 时，ALU 操作数 A 直接来自 `ex_mem_alu_result`（操作数 B 同理）；
- **MEM-EX 前推**：当 `mem_wb_valid && mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs1)` 且未被 EX-EX 覆盖时，操作数来自 WB 阶段数据。

### 3.2 停顿机制 (Load-Use Hazard Stall)
当 EX 级为有效 Load 指令（`id_ex_valid && id_ex_mem_read == 1`），且其写入目标寄存器与 ID 级源寄存器匹配时（`id_ex_rd == id_rs1 || id_ex_rd == id_rs2`，且 `id_ex_rd != 0`）：
- `stall_pc = 1`：冻结 PC；
- `stall_if_id = 1`：冻结 IF/ID 流水线寄存器；
- `flush_id_ex = 1`：向 ID/EX 寄存器注入全零控制信号（NOP 气泡，`id_ex_valid <= 0`）；
- 停顿 1 个时钟周期后，Load 数据到达 MEM 级，通过 MEM-EX 前推继续执行，流水线恢复。

### 3.3 控制冒险 (Control Hazard)
- **分支裁决在 EX 级**（基线版本）：
  - 当分支跳转成立或遇到 `JAL` / `JALR` 时：
  - `flush_if_id = 1`, `flush_id_ex = 1`：冲刷被错误取出的 2 条后续指令；
  - PC 加载跳转目标地址；
  - 惩罚周期为 2 拍。
- **未来升级路径**：在 IF 级引入 Branch Target Buffer (BTB) + 2-bit 饱和计数器【待实现：Tier A 手写】，预测失败时仅冲刷，预测成功时无惩罚。

---

## 4. 存储器总线与接口规范

CPU 核心对外提供分离的指令端口（I-Bus）与数据端口（D-Bus）：

### 4.1 指令端口 (Instruction Bus)
```verilog
output wire [31:0] imem_addr,    // 指令地址（提前一拍发出以适配 BRAM 同步读）
output wire        imem_req,     // 取指请求
input  wire [31:0] imem_rdata    // 读回的 32 位指令
```

### 4.2 数据端口 (Data Bus)
```verilog
output wire [31:0] dmem_addr,    // 访存物理地址 (读在 EX 级提前发出，写在 MEM 级保持)
output wire [31:0] dmem_wdata,   // 写入数据
output wire [3:0]  dmem_byte_we, // 字节使能 (例如 4'b0001 为写低字节)
output wire        dmem_req,     // 访存使能 (Load 或 Store)
input  wire [31:0] dmem_rdata    // 读出数据 (同步 1 拍延迟返回)
```

---

## 5. 性能计数器 (Perf Counter) 接口

用于 CoreMark / 性能评测与调试：
- `perf_cycle`: 累计时钟周期数；【已实现】
- `perf_instret`: 累计提交指令数（WB 级提交一条非气泡有效指令时累加）；【已实现】
- `perf_load_stall`: Load-Use 停顿周期数；【待实现】
- `perf_branch_flush`: 分支预测失败/跳转冲刷次数。【待实现】

---

## 6. 验证与验收准则

1. 单指令与组合逻辑单元级仿真通过 (`make unit-test`)；✅ 6/6 PASS
2. 5 级流水线集成自检测试通过 (`make test-core`，覆盖 RAW 前推、Load-Use 停顿、分支冲刷、访存，提交指令数=10)；✅ 3/3 PASS
3. 运行官方 `riscv-tests` (rv32ui-p-*) 全部 38 项单元测试，全部 PASS；✅ 38/38 PASS（`make isa-test`，CPI 1.07~1.28）
4. 基于 Spike 的 DiffTest 差分验证：在每条指令写回阶段打印 PC、目标寄存器及写回数据，与 Spike 单步执行严格一致。✅ 38/38 MATCH（`make difftest`，0 Mismatch）
