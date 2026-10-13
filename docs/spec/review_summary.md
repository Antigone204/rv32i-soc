# RV32I 5 级流水线 CPU 核心架构评审报告 (Review Summary)

> **文档目的**：供开发者归档、团队研讨及交付其他大模型（如 Claude 3.5 Sonnet / GPT-4o / DeepSeek 等）进行专业 Peer Review 与交叉核验。  
> **项目背景**：全国大学生嵌入式芯片与系统设计竞赛（紫光同创赛道）· RISC-V 并行加速系统。  
> **目标定位**：校招面试核心亮点项目 + 高可靠微架构基线。要求每一行 RTL 可解释、零锁存器、零 Lint 警告。

---

## 1. 架构总览与关键参数

| 维度 | 参数 / 设定 | 说明 |
| :--- | :--- | :--- |
| **指令集 (ISA)** | RV32I (Base Integer, 37条指令) | 32 位定长指令，字对齐访存 |
| **通用寄存器** | 32 × 32-bit (`x0` - `x31`) | `x0` 硬件恒为 0，支持写穿 (Write-First Internal Bypass) |
| **流水线结构** | 5 级经典流水线 (In-Order) | **IF** (取指) $\to$ **ID** (译码/读寄存器) $\to$ **EX** (执行/分支) $\to$ **MEM** (访存) $\to$ **WB** (写回) |
| **级间寄存器** | 4 组同步寄存器 | `IF/ID`, `ID/EX`, `EX/MEM`, `MEM/WB` |
| **复位与时钟** | 同步复位，低电平有效 (`rst_n`) | 单时钟域 `clk`，符合 FPGA 综合与时序收敛最佳实践 |
| **RTL 规范** | Verilog-2001, `` `default_nettype none `` | 纯 RTL，绝无厂商硬核原语，跨平台高可移植 |
| **代码规范与级别** | Tier C (流水线骨架/前推/冒险单元/译码/ALU) | AI 全力配合实现与硬件级讲解，预留 A 档手写模块接口 |

---

## 2. 模块级微架构与数据通路设计

### 2.1 取指级 (IF) 与分支重定向
- **PC 更新机制**：
  - 正常执行：`pc_next = pc + 4`；
  - 发生分支跳转 / JAL / JALR：`pc_next = ex_branch_target`；
  - 流水线停顿 (Stall)：PC 保持不变。
- **分支裁决位置**：位于 **EX 阶段**。
  - 分支预测机制：当前为静态预测“不跳转” (Predict Not-Taken)；
  - 跳转成立惩罚：**2 个时钟周期**，由 Hazard Unit 冲刷 `IF/ID` 和 `ID/EX` 级间寄存器。
  - 预留拓展：在 IF 阶段留有与 BTB / BHT（分支预测器，A 档手写）对接的重定向接口。

### 2.2 译码级 (ID)、寄存器堆与立即数生成
- **主译码器 (`decoder.v`)**：
  - 纯组合逻辑。在 `always @(*)` 开头赋全默认值（`alu_op = ALU_ADD`, 控制信号全 0），彻底杜绝推断锁存器 (Latch)；
  - 解出操作数来源选择：`alu_src_a_sel` (0: Reg, 1: PC), `alu_src_b_sel` (0: Reg, 1: Imm)；
  - 解出写回源选择：`wb_src_sel` (0: ALU 结果, 1: 内存读取数据, 2: PC + 4)；
  - 解出跳转使能：`branch`, `jal`, `jalr`。
- **寄存器堆 (`regfile.v`)**：
  - 采用 Distributed RAM / 寄存器阵列可推断语法（`reg [31:0] regs [0:31]`）；
  - `x0` 读出恒为 0，且写入端口对 `x0` 作屏蔽（`we && waddr != 0`）；
  - **内部写穿直通 (Write-First Internal Bypass)**：当同周期读写同一寄存器时，直接将写入数据前推到读出端口，消除同周期 RAW 冲突。
- **立即数生成器 (`imm_gen.v`)**：
  - 纯组合逻辑，严格遵循 RISC-V 手册重排位域，支持 I, S, B, U, J 五种立即数格式的符号位扩展。

### 2.3 执行级 (EX)、ALU 与前推网络
- **算术逻辑单元 (`alu.v`)**：
  - 支持 11 种操作（ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND, PASS_B）；
  - 移位器使用 `shamt = b[4:0]`，算术右移采用 Verilog `$signed(a) >>> b[4:0]` 语法；
  - SLT 有符号比较使用 `$signed(a) < $signed(b)`，SLTU 使用无符号比较。
- **数据前推单元 (`forwarding_unit.v`)**：
  - 解决 RAW（写后读）数据相关，将 ALU 结果或访存结果直接送入 EX 级的操作数多路器；
  - **EX-EX 前推**（距离为 1 的依赖）：`ex_mem_reg_write && (ex_mem_rd != 0) && (ex_mem_rd == id_ex_rs1)` $\to$ `forward_a = 2'b10`；
  - **MEM-EX 前推**（距离为 2 的依赖）：`mem_wb_reg_write && (mem_wb_rd != 0) && (mem_wb_rd == id_ex_rs1)` $\to$ `forward_a = 2'b01`；
  - **严格优先级防覆写规则**：当 EX/MEM 级与 MEM/WB 级同时对同一寄存器有效写回时（连续两条指令修改同一寄存器），**EX-EX 前推严格优先于 MEM-EX 前推**，确保读取到最新的架构状态。

### 2.4 访存级 (MEM) 与字节对齐处理
- **Store 字节使能生成器**：
  - 根据 `ex_mem_alu_result[1:0]` 地址低 2 位与 `funct3` 动态生成 4-bit 写掩码 `dmem_byte_we`：
    - `SB`: 依据偏移生成 `4'b0001`, `4'b0010`, `4'b0100`, `4'b1000`，并将数据复制到对应字节槽；
    - `SH`: 依据偏移生成 `4'b0011` 或 `4'b1100`；
    - `SW`: 全字写入 `4'b1111`。
- **Load 符号扩展与对齐处理**：
  - 依据地址低 2 位从 `dmem_rdata` 切片目标字节/半字：
    - `LB` / `LBU`: 取 8 位，分别做 32 位符号扩展与零扩展；
    - `LH` / `LHU`: 取 16 位，分别做 32 位符号扩展与零扩展；
    - `LW`: 32 位直通。

### 2.5 冒险控制单元 (`hazard_unit.v`)
- **Load-Use 冒险处理**：
  - 条件：EX 级为 Load（`id_ex_mem_read == 1`）且其目的寄存器与 ID 级源寄存器重合（`id_ex_rd == if_id_rs1 || id_ex_rd == if_id_rs2`），且目标寄存器不为 `x0`；
  - 动作：
    1. `stall_if = 1`: 冻结 PC，阻止取新指令；
    2. `stall_id = 1`: 冻结 `IF/ID` 级间寄存器，保持当前译码指令不变；
    3. `flush_ex = 1`: 清空 `ID/EX` 级间寄存器控制信号，向 EX 级注入一个时钟周期的 NOP 气泡。
  - 代价：停顿 1 拍。下一周期 Load 数据到达 MEM 级，通过 MEM-EX 前推回路直接送入 ALU。
- **控制冒险处理**：
  - 条件：EX 级裁决分支跳转成功（`ex_branch_taken`）或无条件跳转（`ex_jal || ex_jalr`）；
  - 动作：`flush_if = 1` 且 `flush_id = 1`，将已经在 IF 和 ID 级被错误投机取出的两条无效指令冲刷为 NOP。

---

## 3. 当前测试与验证证据 (Verification Evidence)

所有代码均已配置自动化 Makefile，并在本地仿真环境中通过全套测试：

1. **静态语法与代码规范检查 (Lint)**：
   - 工具：Verilator 5.052 (`verilator --lint-only -Wall`)
   - 结果：**0 Error, 0 Warning**（烟囱外设模块及 5 级流水线顶层 core 均实现零警告编译）。
2. **模块级单元回归测试 (`make unit-test`)**：
   - `tb_alu.v`: 覆盖算术右移符号位保留、负数比大小、溢出环绕等 11 项运算 $\to$ **PASS**
   - `tb_regfile.v`: 覆盖 x0 恒零写入丢弃、普通读写、同周期 Write-First 旁路 $\to$ **PASS**
   - `tb_imm_gen.v`: 覆盖 I/S/B/U/J 各类立即数负数符号扩展 $\to$ **PASS**
   - `tb_decoder.v`: 覆盖主要 R/I/S/B/U/J 指令译码控制总线 $\to$ **PASS**
   - `tb_forwarding_unit.v`: 覆盖无冒险、EX-EX 单路/双路、MEM-EX 单路、x0 保护、连续写同寄存器优先级 $\to$ **PASS**
   - `tb_hazard_unit.v`: 覆盖正常流、Load-Use 停顿与气泡注入、x0 免停顿、Branch/JAL 双级冲刷 $\to$ **PASS**
3. **集成级流水线回归测试 (`make test-core`)**：
   - 测试激励：包含一段包含 RAW 密集计算、Load-Use 气泡注入、分支跳转冲刷废弃指令、访存读写的综合汇编机器码；
   - 结果：
     - 正确触发 EX-EX 前推（`addi x1, x0, 10` $\to$ `add x2, x1, x1` $\to$ `x2 = 30` 验证成功）；
     - 正确触发双路前推（`add x3, x1, x2` $\to$ `x3 = 40` 验证成功）；
     - 正确触发 SW / LW 访存；
     - 正确插入 1 拍 Load-Use 气泡（`lw x4, 0(x0)` 紧随 `add x5, x4, x1`，`x5 = 45` 验证成功）；
     - 正确冲刷分支跳转后废弃的指令（`beq x1, x1, +8` 跳过破坏指令，`x6 = 100` 验证成功）；
     - 累计提交有效指令数 7 条，运行周期数 40 拍，波形与寄存器核验全部 **PASS**。

---

## 4. 提供给同行大模型的评审清单 (10 个核验与挑战问题)

请将本章节提供给其他 LLM，请其从**体系结构严谨性、边界条件、硬件电路物理实现及 FPGA 综合时序**四个维度进行审查：

1. **Load-Store 内存相关 (Memory RAW)**：  
   当前设计在 Load-Use 时检测到 `id_ex_rd == if_id_rs1 || id_ex_rd == if_id_rs2` 会暂停 1 拍。但是如果是 `SW` 指令依赖上一条刚计算出的寄存器（即 `SW rs2` 作为写入数据），或者 `SW` 紧跟在 `LW` 之后，当前的 forwarding 与 hazard 是否有漏检？是否需要专门的 MEM-MEM 存储数据前推？
2. **JALR 的基地址冒险**：  
   `JALR` 跳转地址计算方式为 `(rs1 + imm) & ~1`。如果 `rs1` 的值刚好由前一条或前两条指令生成，当前的 ALU 前推网络是否能够保证在 EX 级计算 `next_pc` 时拿到最新的 `rs1` 前推值？
3. **分支裁决在 EX 级的关键路径时序瓶颈**：  
   在当前 5 级流水线中，EX 级的组合逻辑路径为：`ID/EX 寄存器 -> 前推 MUX -> ALU 减法比较 -> 分支成立判定 -> 跳转目标地址 MUX -> IF 级 PC 选择 MUX -> PC 寄存器建立时间`。在紫光同创 Logos-2 FPGA 上，该路径是否容易成为主频（如 50MHz ~ 100MHz）的致命关键路径？工业界通常如何通过分支预测或提早分支比较（在 ID 级）优化该路径？
4. **RegFile 内部旁路与级间前推的必要性冗余**：  
   在流水线已有 `Forwarding Unit`（具备 EX-EX 和 MEM-EX 前推）的前提下，`regfile.v` 内部实现的同周期写穿（Write-First Bypass）在什么指令序列下会真正发挥作用？它与 WB-EX 前推是否存在功能重复？
5. **非对齐访存 (Misaligned Memory Access) 行为定义**：  
   当前 `dmem_addr[1:0]` 支持对齐的字节和半字读写。如果软件发起了非对齐的 `LW`（例如地址低两位为 `2'b01`），当前硬件会发生什么？RISC-V 规范对于不支持非对齐访存的处理器推荐采取什么行为（Trap 异常 vs 截断）？
6. **x0 寄存器前推保护机制**：  
   检查 `forwarding_unit.v`：如果前一条指令是 `addi x0, x0, 10`（试图写 `x0`），而当前指令读取 `x0`，是否会被错误前推 10？当前代码如何确保前推网络始终尊重 `x0 == 0`？
7. **综合锁存器 (Inferred Latches) 审查**：  
   检查 `decoder.v` 和 `alu.v` 中的 `case` 语句与条件分支，是否存在某些未覆盖的分支条件或在部分分支未赋满全部输出信号，从而可能在综合工具（如 PDS / Vivado）中生成不期望的非时钟透明锁存器？
8. **停顿与冲刷并发时的冲突仲裁**：  
   在某种极端异常或中断边界情况下，若同时产生 `Stall`（停顿）与 `Flush`（冲刷），例如一条指令既处于 Load-Use 停顿期，此时发生异步中断或分支冲刷，`hazard_unit` 的控制信号优先级是否可能出现逻辑死锁或流水线寄存器状态不同步？
9. **未来接入 CSR 与异常处理 (Trap) 架构的侵入性**：  
   后续要引入 CSR、`ECALL` / `EBREAK` 以及定时器中断（Tier B 任务），在当前 5 级流水线上，异常触发与捕获点放在哪一级最合适？精确异常（Precise Exception）冲刷流水线需要对现有的 `hazard_unit` 增设哪些信号？
10. **FPGA 片上资源推断友好度**：  
   `regfile.v`（32×32b，2 读 1 写端口）在紫光同创 Logos-2（PG2L200H）的架构下，会被推断为纯 LUT 逻辑（分布式寄存器）还是专用双端口 Block RAM (DRM)？这种推断对芯片的资源开销与布线拥塞度有何影响？
