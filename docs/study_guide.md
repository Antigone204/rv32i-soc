# RISC-V SoC 全系统精读与方案对比导学手册

> **定位**：面向系统架构与源码精读的软硬件协同导学手册。  
> **目标**：直击 RTL 源码、微架构逐拍时序与关键工程设计取舍（Trade-offs）。

---

## 目录
1. [一图看懂全系统：一条指令和一行 C 代码是怎么跑起来的？](#一图看懂全系统一条指令和一行-c-代码是怎么跑起来的)
2. [核心模块逐文件导读（读源码路线图）](#核心模块逐文件导读读源码路线图)
3. [本项目的 4 个微架构精髓](#本项目的-4-个微架构精髓)
4. [自检清单：看懂这 10 个问题就彻底掌握了基线系统](#自检清单看懂这-10-个问题就彻底掌握了基线系统)

---

## 一图看懂全系统：一条指令和一行 C 代码是怎么跑起来的？

### 1.1 系统全景拓扑图

整个系统的硬件架构可抽象为 **“经典 5 级流水线 CPU 核 + 专用指令直连通道 + Wishbone B4 共享总线矩阵 + 3 大片上外设”**：

```
+---------------------------------------------------------------------------------------------------------+
|                                              soc_top.v                                                  |
|                                                                                                         |
|  +--------------------------------------- core.v ----------------------------------------------------+  |
|  |  [IF]          [ID]                  [EX]                     [MEM]                [WB]           |  |
|  |  if_pc ------> if_id_inst ---------> ALU / BrComp ----------> dmem_addr ---------> RegFile       |  |
|  |  if_next_pc    u_decoder             Forwarding Unit          Byte Align / Ext     wb_valid/pc/rd |  |
|  |                u_regfile / imm_gen   Hazard Unit              (仲裁 Store/Load)                   |  |
|  +-----|-----------------------------------|--------------------------|------------------------------+  |
|        | imem_* (专用取指端口, 0等待)     |                          | dmem_* (原生访存端口)         |
|        |                                   |                          v                                 |
|        |                                   |                 +------------------+                       |
|        |                                   |                 | wb_core_bridge.v |                       |
|        |                                   |                 +--------|---------+                       |
|        |                                   |                          | Wishbone Master                 |
|        |                                   |                          v                                 |
|        |                         +---------v--------------------------+---------+                       |
|        |                         |            wb_interconnect.v                 |                       |
|        |                         |    (地址高16位组合译码 + 上一拍 sel_r 响应路由)     |                       |
|        |                         +---------+--------------+--------------+------+                       |
|        |                                   |              |              |                              |
|        |             Slave 0 (0x0000_xxxx) |        Slave 1 (0x1001_xxxx)| Slave 2 (0x0200_xxxx)        |
|        v                                   v              v              v                              |
|  +--------------------+             +-------------+ +-------------+ +-------------+                     |
|  |    Port A (取指)   |             |   Port B    | |  wb_uart.v  | |  wb_clint.v |                     |
|  |                    |             | (数据访存)  | | 8B TX/RX    | | 64位 mtime  |                     |
|  |      wb_sram.v (64KB 片上 BRAM)  |             | | FIFO + PHY  | | /mtimecmp   |                     |
|  +----------------------------------+-------------+ +-------------+ +-------------+                     |
+---------------------------------------------------------------------------------------------------------+
```

---

### 1.2 从上电复位到 C 代码运行

1. **上电复位瞬间**：
   - 外部同步复位信号 `rst_n` 低电平有效。
   - `core.v` 内部将 `if_pc` 复位为 `0x0000_0000`（[core.v#L75](../rtl/core/core.v#L75)），流水线全部级间寄存器清空（注入 NOP 指令 `0x0000_0013`）。
   - 复位释放的第 1 个时钟上升沿，CPU 从 `0x0000_0000` 开始取指。
2. **C 运行时的诞生 (`crt0.S`)**：
   - 第一步（清空通用寄存器）：`li x1, 0` ~ `li x31, 0`，防止仿真中产生未初始化的未知态 `'x` 信号扩散（[crt0.S#L18-L48](../sw/common/crt0.S#L18-L48)）。
   - 第二步（初始化堆栈）：`la sp, __stack_top`，栈顶指向 SRAM 高地址 `0x0001_0000`（64KB 边界），栈由高向低增长（[crt0.S#L55](../sw/common/crt0.S#L55)）。
   - 第三步（清零未初始化全局变量）：遍历 `[__bss_start, __bss_end)`，循环执行 `sw zero, 0(a0)`。
   - 第四步（跳入 main）：`call main`，进入 C 语言世界。
   - 第五步（退出与上报）：`main()` 返回后，将结果写入高地址邮箱 `0xFFFF_FFF0`（`SIM_CTRL`），仿真 Testbench 捕获后结束仿真（[crt0.S#L72-L88](../sw/common/crt0.S#L72-L88)）。

---

### 1.3 核心指令的全生命周期追踪

#### 追踪 A：一条算术指令 `add x3, x1, x2`
- **T1 拍 (IF - 取指)**：
  - 核心向 `wb_sram.v` Port A 发出地址 `imem_addr = if_next_pc`。
  - SRAM 的同步读逻辑在时钟沿采样地址，在下一个周期送出 32 位机器码 `0x002081B3`，装入 `if_id_inst`。
- **T2 拍 (ID - 译码与读寄存器)**：
  - `decoder.v` 将 `opcode=0110011` 解码为 R-type 指令，生成控制信号：`alu_op = ALU_ADD`, `alu_src_a = 0 (rs1)`, `alu_src_b = 0 (rs2)`, `reg_write = 1`, `wb_src_sel = WB_SRC_ALU`。
  - `regfile.v` 在该周期通过组合逻辑读出 `x1` 和 `x2` 的值，分别送至 `id_rs1_data` 和 `id_rs2_data`。
- **T3 拍 (EX - 执行)**：
  - `forwarding_unit.v` 检查前续流水级是否存在对 `x1/x2` 的未写回操作（无冲突时 `forward_a/b = 2'b00`）。
  - `alu.v` 计算 `ex_alu_out = ex_alu_op_a + ex_alu_op_b`。结果在时钟沿打入 `ex_mem_alu_out`。
- **T4 拍 (MEM - 访存空转)**：
  - 由于 `ex_mem_mem_read=0` 且 `ex_mem_mem_write=0`，本指令在 MEM 级不做总线操作，结果直接透传至 `mem_wb_alu_out`。
- **T5 拍 (WB - 写回与提交)**：
  - `wb_final_data` 选择 `mem_wb_alu_out`。
  - 在 T5 拍的时钟上升沿，`regfile.v` 捕捉到 `we=1`、`waddr=5'd3`，将运算结果正式写入寄存器 `x3`。
  - 顶层同时拉高 `wb_valid=1`、`wb_we=1`、`wb_pc`、`wb_rd=3`、`wb_wdata`，完成一条指令的退休提交，供 DiffTest 比对。

---

#### 追踪 B：一条内存读指令 `lw x4, 0(x1)`
- **IF 级与 ID 级**：同上。译码器置位 `mem_read = 1`，`imm_sel = IMM_I`，`wb_src_sel = WB_SRC_MEM`。
- **EX 级（关键：提前发读地址）**：
  - ALU 算出有效物理地址：`ex_alu_out = rs1_data + 0`。
  - **重要微架构行为**：为适配 FPGA BRAM 的 1 拍同步读延迟，`core.v` 在 EX 级就直接将组合逻辑结果 `ex_alu_out` 驱动到 `dmem_addr` 上（[core.v#L357](../rtl/core/core.v#L357)），并置位 `dmem_req = 1`！
  - 信号穿过 `wb_core_bridge` 和 `wb_interconnect` 到达 `wb_sram` Port B。Port B 在当前 EX 拍的时钟上升沿采样此读地址！
- **MEM 级（读数据就绪）**：
  - 在时钟沿过后，BRAM 立即吐出内存数据，通过总线返回给 `dmem_rdata`。
  - MEM 级根据 `ex_mem_funct3` 执行对齐与符号扩展逻辑（[core.v#L396-L431](../rtl/core/core.v#L396-L431)），将 32 位字锁入 `mem_wb_load_data`。
- **WB 级**：
  - 写回选择器选中 `mem_wb_load_data`，在时钟上升沿写入通用寄存器 `x4`。

---

#### 追踪 C：一行 C 代码串口打印 `UART_TXDATA_REG = 'H';` (`sw x1, 0(x2)`)
对应硬件底层的 Store 操作（其中 `x2 = 0x1001_0000`，`x1 = 0x0000_0048`）：
- **IF 级与 ID 级**：正常取指译码，`mem_write = 1`，`reg_write = 0`。
- **EX 级**：ALU 算出目标外设地址 `0x1001_0000`，准备写入的数据跟随进入 `ex_mem_rs2_data`。
- **MEM 级（总线交互核心）**：
  - `core.v` 发出 `dmem_addr = 0x1001_0000`，`dmem_wdata = 32'h0000_0048`，`dmem_byte_we = 4'b1111`，`dmem_req = 1`。
  - **Bridge**：`wb_core_bridge.v` 将其直通转换为 Wishbone Master 信号：`wbm_adr_o = 0x1001_0000`，`wbm_dat_o = 0x48`，`wbm_cyc_o = 1`，`wbm_stb_o = 1`，`wbm_we_o = 1`。
  - **Interconnect**：`wb_interconnect.v` 组合逻辑检测到 `wbm_adr_i[31:16] == 16'h1001`，选通 Slave 1 (`wb_uart`)，产生 `wbs1_stb_o = 1`，`wbs1_cyc_o = 1`。
  - **UART 控制器**：`wb_uart.v` 检测到写请求且地址偏移为 `0x00`（`TXDATA` 寄存器），在当前时钟上升沿将字符 `'H'`（`8'h48`）压入内部 8 字节深度 TX FIFO（[wb_uart.v#L81-L84](../rtl/soc/wb_uart.v#L81-L84)）。
  - **物理层串行化**：下一拍，`uart_tx.v` 状态机检测到 FIFO 非空，以 115200 波特率逐 bit（起始位 0 $\to$ 8位数据位 $\to$ 停止位 1）串行输出至 FPGA 外部引脚 `uart_txd`。
- **WB 级**：Store 指令不写回通用寄存器，但 `wb_valid=1` 正常提交，性能计数器 `perf_instret` 累加 1。

---

## 核心模块逐文件导读（读源码路线图）

建议按照 **“底层算子与译码 $\to$ 寄存器堆 $\to$ 冒险与前推 $\to$ 核顶层 $\to$ 总线与外设”** 的最佳逻辑路径精读源码：

```
alu.v ──────> imm_gen.v ──────> decoder.v ──────> regfile.v
                                                     │
                                                     v
core.v <─── hazard_unit.v <─── forwarding_unit.v ────┘
  │
  └──> wb_interconnect.v ──> wb_sram.v / wb_uart.v / wb_clint.v
```

---

### 1. `rtl/core/alu.v` — 算术逻辑单元
- **核心职责与关键信号**：
  纯组合逻辑。执行 RV32I 基础的 10 种算术/逻辑运算及 `PASS_B`。输入 `alu_op[3:0]`、`op_a[31:0]`、`op_b[31:0]`，输出 `alu_out[31:0]`、`zero`。
- **关键源码精读**：
  - [alu.v#L31](../rtl/core/alu.v#L31): `wire [4:0] shamt = op_b[4:0];`  
    **解释**：RISC-V 规定 32 位移位只取操作数低 5 位（范围 0~31），高位在硬件中直接截断。
  - [alu.v#L38-L42](../rtl/core/alu.v#L38-L42): 区分有符号运算与无符号运算：
    ```verilog
    `ALU_SLT: alu_out = ($signed(op_a) < $signed(op_b)) ? 32'd1 : 32'd0;
    `ALU_SRA: alu_out = $signed(op_a) >>> shamt;
    ```
    **解释**：在 Verilog 中算术右移（`>>>`）和有符号比较必须对**两个操作数**都施加 `$signed()` 强制修饰，否则一旦有未修饰变量，编译器会回退为无符号逻辑右移或无符号比较。
- **方案对比与取舍**：
  - *当前实现*：单周期纯组合逻辑 Case 结构。
  - *工业级/替代实现*：单周期移位器在位宽较大时扇出长、延迟大。高频核（如 500MHz+）通常采用多级桶形移位器（Barrel Shifter）打两拍，或者与乘法器硬件资源复用。乘除法（M 扩展）则必须设计为多周期独立功能单元。

---

### 2. `rtl/core/imm_gen.v` — 立即数生成器
- **核心职责与关键信号**：
  纯组合逻辑。根据 `imm_sel[2:0]` 提取指令字中分散的立即数字段，完成符号扩展后输出 32 位立即数 `imm_out`。
- **关键源码精读**：
  - [imm_gen.v#L49](../rtl/core/imm_gen.v#L49) (B-type) 与 [imm_gen.v#L60](../rtl/core/imm_gen.v#L60) (J-type)：
    ```verilog
    // B-type 分支立即数拼接：最高位符号位，最低位恒补 0
    imm_out = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    ```
    **解释**：RISC-V 分支跳转以 2 字节（半字）为最小粒度，因此指令编码中不保存 `imm[0]`，解码时硬件必须在末尾强行补 `1'b0`。
- **方案对比与取舍**：
  - *RISC-V 优雅设计*：所有类型的立即数符号位都被固定在 `inst[31]`。硬件中符号扩展器只需直接引出 `inst[31]` 复制扇出，无需在多个位之间做 MUX 选择，相比 MIPS/ARM 显著节约布线面积。

---

### 3. `rtl/core/decoder.v` — 主控制译码器
- **核心职责与关键信号**：
  纯组合逻辑。输入 32 位机器码 `inst`，解析生成驱动全流水线的控制总线（`alu_op`, `alu_src_a/b`, `mem_read/write`, `reg_write`, `wb_src_sel`, `branch/jal/jalr` 等）。
- **关键源码精读**：
  - [decoder.v#L88-L100](../rtl/core/decoder.v#L88-L100):
    ```verilog
    always @(*) begin
        imm_sel = IMM_I; alu_op = `ALU_ADD;
        mem_read = 1'b0; mem_write = 1'b0; reg_write = 1'b0; ...
    ```
    **解释（防锁存器铁律）**：在组合逻辑 `always @(*)` 的最开头无条件给**所有输出信号赋安全默认值**，杜绝分支未覆盖推断出危险锁存器（Latch）。
- **方案对比与取舍**：
  - *当前实现*：单级集中式大组合译码表。代码集中直观，单发射 5 级流水线首选。
  - *工业级超标量实现*：多发射超标量处理器通常将译码拆为“Pre-decode”（取指阶段标记指令长度、是否为跳转）和“Micro-op Decode”（ID 阶段发射微码），以打破译码阶段对时钟频率的拖累。

---

### 4. `rtl/core/regfile.v` — 通用寄存器堆
- **核心职责与关键信号**：
  维护 32 个 32 位通用寄存器。双异步读端口（`raddr1/2` $\to$ `rdata1/2`），单同步写端口（`waddr`, `wdata`, `we`）。
- **关键源码精读**：
  - [regfile.v#L28](../rtl/core/regfile.v#L28):
    ```verilog
    /* verilator lint_off UNUSEDSIGNAL */
    input wire rst_n, // 取消寄存器复位以推断 FPGA 分布式 RAM (LUTRAM)
    ```
    **解释**：故意不复位 `regs` 阵列！FPGA 的 SLICEM (LUTRAM) 原语物理上不支持异步复位，若写了 `if (!rst_n)` 复位，综合工具会被迫使用 1024 个普通触发器拼凑寄存器堆，耗尽资源。
  - [regfile.v#L54-L60](../rtl/core/regfile.v#L54-L60):
    ```verilog
    assign rdata1 = (raddr1 == 5'd0) ? 32'd0 :
                    (we && (waddr == raddr1)) ? wdata : regs[raddr1];
    ```
    **解释（内部写优先直通）**：当同一拍写和读同一个寄存器时，直接将即将写入的数据 `wdata` 旁路给读输出，解决 WB 级与 ID 级同周期读写 RAW 冲突。
- **方案对比与取舍**：
  - *当前实现*：取消复位换取 FPGA LUTRAM 高度紧凑推断；读端口做内部写直通。
  - *ASIC 做法*：ASIC 往往使用定制的专用双端口 Register File SRAM IP 或全复位标准单元，必须带 BIST 扫描链清零。

---

### 5. `rtl/core/forwarding_unit.v` — 数据前推单元
- **核心职责与关键信号**：
  纯组合逻辑。对比 `id_ex_rs1/2` 与 `ex_mem_rd`、`mem_wb_rd`，输出 `forward_a/b[1:0]` 控制 EX 级 ALU 输入端多路选择器。
- **关键源码精读**：
  - [forwarding_unit.v#L45-L52](../rtl/core/forwarding_unit.v#L45-L52):
    ```verilog
    if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) begin
        forward_a = 2'b10; // EX-EX 前推 (前一条指令)
    end else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1)) begin
        forward_a = 2'b01; // MEM-EX 前推 (前前条指令)
    end
    ```
    **解释（优先级与 x0 防护）**：EX-EX 前推必须优先于 MEM-EX（最新值覆盖老值）；必须显式检查 `rd != 0`，否则写 `x0` 的指令（如 `addi x0, x1, 1`）会把垃圾数值误前推给后面的指令！
- **方案对比与取舍**：
  - *当前实现*：全旁路前推网络。将连续算术计算间的 RAW 停顿降为 0 周期。
  - *极低成本嵌入式（如 Cortex-M0）*：直接取消硬件前推网络，遇到冲突硬插入 2 拍停顿，牺牲 IPC 换取极致芯片面积。

---

### 6. `rtl/core/hazard_unit.v` — 冒险检测单元
- **核心职责与关键信号**：
  纯组合逻辑。输出流水线停顿信号（`stall_pc`, `stall_if_id`, `stall_id_ex`）与冲刷信号（`flush_if_id`, `flush_id_ex`, `flush_ex_mem`）。
- **关键源码精读**：
  - [hazard_unit.v#L58-L63](../rtl/core/hazard_unit.v#L58-L63):
    ```verilog
    assign structural_hazard = ex_mem_mem_write & id_ex_mem_read; // SW紧跟LW
    wire load_use_hazard = id_ex_mem_read & (id_ex_rd != 5'd0) &
                           ((id_ex_rd == if_id_rs1) | (id_ex_rd == if_id_rs2));
    ```
    **解释**：捕获两大类数据/结构冒险。Load-Use 是因为读出数据在 MEM 级才产生，前推无法逆转时钟，必须停顿 1 拍并向 ID/EX 注入气泡。
  - [hazard_unit.v#L75-L92](../rtl/core/hazard_unit.v#L75-L92):
    **解释（优先级机制）**：跳转冲刷（分支跳错）优先级最高，其次是 SW$\to$LW 结构冒险停顿，最后是 Load-Use 停顿。严防控制冒险与停顿并发时的死锁。
- **方案对比与取舍**：
  - *当前实现*：集中式冒险仲裁控制器。输入清晰、状态正交，Bug 极易排查。
  - *分布式方案*：每级流水线自行产生分布式握手信号（Valid-Ready 级联反压），虽然模块解耦好，但在复杂异常和回滚处理时极易发生微架构死锁。

---

### 7. `rtl/core/core.v` — 5 级流水线顶层核心
- **核心职责与关键信号**：
  将 IF、ID、EX、MEM、WB 五大阶段连接成整体，例化各子模块并引出 I-Bus、D-Bus 及提交追踪接口（`wb_valid`, `wb_pc`, `wb_rd`, `wb_wdata`）。
- **关键源码精读**：
  - [core.v#L82-L85](../rtl/core/core.v#L82-L85):
    ```verilog
    assign imem_addr = (!rst_n)   ? 32'h0000_0000 :
                       (stall_pc) ? if_pc : if_next_pc;
    ```
    **解释**：提前 1 拍向 BRAM 发出取指地址，流水线全速运行时取指零等待。
  - [core.v#L224-L228](../rtl/core/core.v#L224-L228)（BUG-003 修复核心）：
    ```verilog
    end else if (stall_id_ex) begin
        id_ex_rs1_data <= ex_fwd_val_a;
        id_ex_rs2_data <= ex_fwd_val_b;
    end
    ```
    **解释**：EX 级停顿期间锁存前推数据，防止生产者指令在下一拍写回退休后前推数据消失。
  - [core.v#L357](../rtl/core/core.v#L357)（BUG-002 修复核心）：
    ```verilog
    assign dmem_addr = (ex_mem_valid & ex_mem_mem_write) ? ex_mem_alu_out : ex_alu_out;
    ```
    **解释**：内存端口所有权仲裁。若 MEM 级是有效 Store，端口归 Store 独占；否则才给 EX 级的 Load 发出读地址。

---

### 8. `rtl/soc/wb_interconnect.v` — Wishbone 共享总线互连矩阵
- **核心职责与关键信号**：
  1-Master 到 4-Slave 的地址译码路由与数据/ACK 聚合。
- **关键源码精读**：
  - [wb_interconnect.v#L61-L64](../rtl/soc/wb_interconnect.v#L61-L64):
    ```verilog
    wire sel_sram  = (wbm_adr_i[31:16] == 16'h0000);
    wire sel_uart  = (wbm_adr_i[31:16] == 16'h1001);
    wire sel_clint = (wbm_adr_i[31:16] == 16'h0200);
    ```
    **解释**：基于高 16 位地址的纯组合译码，当拍即时门控对应从设备的 `cyc` 和 `stb`。
  - [wb_interconnect.v#L97-L113](../rtl/soc/wb_interconnect.v#L97-L113):
    ```verilog
    reg [1:0] sel_r;
    always @(posedge clk) if (wbm_stb_i) sel_r <= ...;
    ```
    **解释（时序对齐神来之笔）**：从设备的读数据和 ACK 是在请求后的**下一拍**才返回的。CPU 发出地址后该地址只维持一拍，因此互连必须用寄存器 `sel_r` 记住上一拍到底访问了哪个从设备，下一拍才能将正确的返回值路由给 CPU！
- **方案对比与取舍**：
  - *当前实现*：固定单周期响应的多路选择器互联。
  - *工业级 AXI/Wishbone Crossbar*：支持可变等待周期（Slave 未就绪时拉低 ACK 反压）、支持多个 Master 之间按轮询（Round-Robin）仲裁并发访问不同从设备。

---

### 9. `rtl/soc/wb_sram.v` — 64KB 双端口片上存储器
- **核心职责与关键信号**：
  集成紫光 Logos-2 原生推断的双端口 BRAM。Port A 直连 CPU 取指，Port B 挂载在 Wishbone 总线上执行数据读写。
- **关键源码精读**：
  - [wb_sram.v#L58-L60](../rtl/soc/wb_sram.v#L58-L60) 与 [wb_sram.v#L65-L73](../rtl/soc/wb_sram.v#L65-L73)：
    ```verilog
    always @(posedge clk) imem_rdata <= mem[word_addr_a]; // Port A 同步读
    always @(posedge clk) begin                           // Port B 字节使能写+同步读
        if (wbs_cyc_i & wbs_stb_i & wbs_we_i) begin
            if (wbs_sel_i[0]) mem[word_addr_b][ 7: 0] <= wbs_dat_i[ 7: 0];
            ...
        end
        wbs_dat_o <= mem[word_addr_b];
    end
    ```
    **解释**：经典的 FPGA 双端口 Block RAM 推断模板，支持 4 字节掩码写入（用于 `SB`, `SH`, `SW`）。
- **方案对比与取舍**：
  - *双端口物理隔离*：取指走 Port A，数据访问走 Port B。两通道零竞争、零仲裁等待。
  - *单端口方案对比*：若使用单端口 RAM，每次发生 Load/Store 访存，CPU 必须强制停顿取指一拍，CPI 将恶化 20%~30%。

---

### 10. `rtl/soc/wb_uart.v` — 串口控制器
- **核心职责与关键信号**：
  封装物理层收发器，对齐 SiFive FE310 寄存器规范，内置收发双 8 字节 FIFO。
- **关键源码精读**：
  - [wb_uart.v#L87-L93](../rtl/soc/wb_uart.v#L87-L93)（BUG-005 修复）：
    ```verilog
    if (tx_pop) begin
        tx_phy_data  <= tx_mem[tx_rptr];
        tx_rptr      <= tx_rptr + 3'd1;
        tx_phy_valid <= 1'b1;
    end else begin
        tx_phy_valid <= 1'b0;
    end
    ```
    **解释**：在从 FIFO 弹出数据给物理层发送时，必须将当前条目打一拍锁存到 `tx_phy_data`，彻底避免组合逻辑直读导致读指针递增瞬间数据撕裂发送出垃圾字符。
- **方案对比与取舍**：
  - *硬件 FIFO*：以极小的 LUT 资源实现 8 字节缓冲，使 CPU 打印字符无需死等串口波特率序列化（115200 波特率下每个字符耗时 86.8 微秒），大幅释放 CPU 算力。

---

### 11. `rtl/soc/wb_clint.v` — Core-Local Interruptor 定时器
- **核心职责与关键信号**：
  实现 RISC-V 标准的 64 位单调递增计数器 `mtime` 和比较寄存器 `mtimecmp`。
- **关键源码精读**：
  - [wb_clint.v#L37](../rtl/soc/wb_clint.v#L37):
    ```verilog
    assign timer_irq = (mtime >= mtimecmp);
    ```
    **解释**：硬件纯组合逻辑无符号 64 位比较，产生标准定时器中断。
  - [wb_clint.v#L48-L58](../rtl/soc/wb_clint.v#L48-L58):
    **解释**：每个时钟上升沿 `mtime` 自动 +1。软件可通过 32 位分次读写维护高低 32 位。
- **方案对比与取舍**：
  - *标准 64 位 CLINT*：在 50MHz 时钟下，64 位计数器需要连续运行 11,000 年才会溢出回绕！相比普通 32 位定时器（约 85 秒就溢出），极大简化了 CoreMark 性能评测与 RTOS 的 Tick 计时逻辑。

---

## 本项目的 4 个微架构精髓

### 故事 1：FPGA BRAM 的 1 拍同步读延迟，是如何被巧妙“藏”起来的？
- **背景痛点**：  
  在经典教科书流水线中，通常假设存储器是“异步组合读”（Asynchronous Read）：当前周期在 IF 级给出 PC，当拍数据立刻返回给译码级；在 MEM 级给出访存地址，当拍立刻拿到数据。  
  **但是真实 FPGA 物理芯片完全不是这样！** 无论紫光同创（Logos-2）还是 Xilinx，片上 Block RAM 内部输出端口均带有强制时钟触发器，具有固定的 **1 拍同步读延迟（Synchronous Read Latency = 1 Cycle）**：T 拍采样的地址，数据必须在 T+1 拍上升沿才出现在总线上。如果直接套用教科书设计，取指需要等 1 拍，Load 访存又需要等 1 拍，整个流水线 CPI 直接从 1.0 崩塌到 2.0 以上！
- **我们的微架构破局解法**：
  1. **取指延迟折叠（`if_next_pc` 提早一拍发）**：  
     我们绝不等到 T 拍时钟沿把 PC 存入 `if_pc` 寄存器后再发给 BRAM。在 [core.v#L82-L85](../rtl/core/core.v#L82-L85) 中，我们直接把组合逻辑算出的 **“下一拍 PC”**（`if_next_pc = branch_taken ? branch_target : if_pc + 4`）提前送往 SRAM Port A。在 T 拍时钟上升沿，BRAM 刚好采样了下一拍的地址；在 T+1 拍，指令数据与 `if_pc` 严格同步进入 IF/ID 寄存器！1 拍硬件延迟被无形化解，取指达到 **零等待状态（Zero Wait-State）**。
  2. **Load 读延迟折叠（`ex_alu_out` 提早一拍发）**：  
     同理，传统流水线在 MEM 级才向数据总线发地址。我们在 EX 级算完 `ex_alu_out` 后，在时钟前半周期直接将该组合逻辑结果透传给 `dmem_addr`（[core.v#L357](../rtl/core/core.v#L357)）。BRAM 在 EX 级末的时钟上升沿采样读地址，在 MEM 级一开始数据就已经稳稳出现在总线上，供 MEM 级进行对齐与扩展。因此，**在真实 FPGA 同步 BRAM 下，我们的 Load-Use 冒险只需要停顿 1 拍**（与教科书异步 RAM 性能完全持平），彻底打消了硬件延迟惩罚。

---

### 故事 2：提前发 Load 地址引发的“SW 紧跟 LW 结构冒险”（BUG-002）与架构演进
- **踩坑现象**：  
  在运行定向测试时发现：当指令序列为 `sw x3, 0(x0)` 紧跟 `lw x4, 4(x0)`（访问不同地址）时，`x3` 的数值错误地被写入了 `0x04` 地址，而 `0x00` 地址完全没有被写入！
- **时序根因剖析**：  
  由于我们在故事 1 中把 Load 的读地址提前到 EX 级发出，当 `SW` 处于 MEM 级准备写内存、`LW` 处于 EX 级准备发读地址时，两指处于**同一个时钟周期**！  
  原设计中 `dmem_addr` 选择器盲目偏袒了 EX 级发出的读地址 `0x04`。结果在当前时钟上升沿，`SW` 的写使能有效，但地址总线却挂着 `LW` 的读地址 `0x04`，酿成“内存错写”灾难！
- **为什么早期测试没发现？（深刻教训）**：  
  早期集成测试中，SW 与 LW 恰好访问了同一个地址 `0x00`（看不出地址漂移）；且初版 Testbench 内存模型写了一条“当拍有写请求时直接无条件直通读数据”的迁就旁路。**测试环境绝不能迁就硬件设计缺陷！** 规范的验证必须建立在精准反映 FPGA 物理规范的基础之上。
- **当前解法与进阶方案对比**：
  - **当前低开销解法（停顿 1 拍）**：  
    在 `hazard_unit.v` 增加判定 `structural_hazard = ex_mem_mem_write & id_ex_mem_read`。发生冲突时暂停流水线 1 拍（冻结 PC、IF/ID、ID/EX，向 EX/MEM 注入气泡），本拍内存端口让给 Store；下一拍 Store 移入 WB，Load 正常发读地址。
  - **进阶硬件方案 1：双端口数据 RAM（True Dual-Port D-SRAM）**：  
    一个端口专用于 Store 写，另一个端口专用于 Load 读。优点是完全消除停顿；缺点是 FPGA 的 Block RAM 物理上只有两个端口，若数据端占满两端口，指令取指端就必须另外消耗一套 BRAM 产生内存镜像复制，BRAM 消耗量翻倍。
  - **进阶硬件方案 2：写缓冲器（Store Buffer）**：  
    Store 指令在 MEM 级不直接写内存，而是将 `{addr, data, mask}` 压入一个 2~4 项的轻量 FIFO（Store Buffer）并立即退休。总线空闲时后台静默写入 BRAM；若后续紧跟 Load 读取同一地址，直接从 Store Buffer 前推（Store-to-Load Forwarding）。此方案不仅消灭了结构冒险，也是现代高性能处理器和 Cache 架构的基石。

---

### 故事 3：EX 级停顿时，前推来的操作数为什么会“逃逸丢失”？（BUG-003）
- **踩坑现象**：  
  测试序列：`addi x1, x0, 8` $\to$ `sw x3, 4(x0)` $\to$ `lw x4, 0(x1)`。  
  `lw` 的基址依赖 `addi` 生成的 `x1=8`。但在执行过程中，`lw` 发出的基址竟然是未知态 `'x`，读回了脏数据！
- **时序根因剖析**：  
  - **第 T 拍**：`addi` 位于 WB 级，`sw` 位于 MEM 级，`lw` 位于 EX 级。由于故事 2 中的结构冒险，`lw` 在 EX 级被触发停顿（`stall_id_ex = 1`）。在这一拍，`forwarding_unit` 正确工作，MEM-EX 前推网络将 WB 级的 `8` 实时送到了 EX 级 ALU 输入端。
  - **第 T+1 拍（致命时刻）**：`addi` 完成写回，**退休移出流水线**！而 `lw` 依然停留在 EX 级。此时 WB 级变成了 `sw`，前推使能撤销（`forward_a` 归零），前推多路器切换回读取 `id_ex_rs1_data`。  
    **致命漏洞爆发**：因为上一拍处于停顿状态，`id_ex_rs1_data` 寄存器被冻结，里面仍然存着多拍前在 ID 级读出的旧值（未就绪的旧值或仿真未复位的未知态）！原本在第 T 拍送到门口的正确前推值，随着生产者指令的退休，彻底“蒸发逃逸”了！
- **前推值锁存定律与修复**：  
  流水线前推网络是**无状态的纯组合逻辑**。当某一级被停顿、而更老的指令继续退休流动时，必须在停顿拍**把当前有效的前推数据强制采样锁入本级寄存器**！  
  在 [core.v#L224-L228](../rtl/core/core.v#L224-L228) 写入：
  ```verilog
  end else if (stall_id_ex) begin
      id_ex_rs1_data <= ex_fwd_val_a;
      id_ex_rs2_data <= ex_fwd_val_b;
  end
  ```
  这样，前推数据在第 T 拍上升沿被牢固锁在 `id_ex` 寄存器中；第 T+1 拍哪怕生产者退休离场，本级依然持有正确数值，系统坚如磐石。

---

### 故事 4：总线为什么选 Wishbone B4 固定一拍子集？各大总线对比取舍
- **为什么选 Wishbone B4？**：  
  本项目采用 Wishbone B4 Classic 单拍子集协议（OpenCores 维护的国际开源标准）。  
  **取舍之道在于“极简正交与物理时序匹配”**：
  1. 信号线极简：仅需 `cyc`, `stb`, `we`, `adr`, `dat_o/i`, `sel`, `ack`，没有通道级握手反压的死锁包袱；
  2. 1 拍同步延迟：从设备在 `cyc & stb` 断言后的下一个时钟上升沿返回 `ack` 和数据，这与 FPGA 片上 BRAM、单拍外设寄存器的物理节拍完全重合，无需在核内引入复杂的可变等待状态机，代码量控制在 150 行以内，极易精读掌控；
  3. 平滑演进：未来接入慢速设备或外部 DDR3 时，只需在 `wb_core_bridge.v` 接入 `ack` 产生流水线等待停顿，即可自然升级为全功能握手总线。

#### 常见片上总线横向对比表
| 总线协议 | 拓扑与通道结构 | 握手机制 | 优缺点与适用场景 |
|---|---|---|---|
| **Wishbone B4 Classic (本项目采用)** | 共享总线，单组读写复合通道 | `cyc & stb` 发起，从机 `ack` 确认 | **优点**：极简、开源无授权限制、与片上 RAM 1 拍延迟天然匹配、资源极省。<br>**缺点**：单通道读写无法同时全双工，吞吐率适中。 |
| **AXI4-Lite** | 读写分离，共 5 个独立通道 (AR, R, AW, W, B) | 双向 `VALID / READY` 异步握手 | **优点**：读写完全解耦、支持复杂跨时钟域与多级缓冲。<br>**缺点**：线网极其庞大繁复，握手反压极易产生死锁，对小核过于笨重。 |
| **AHB-Lite** | 共享总线，两相流水线 (地址相与数据相重叠) | `HREADY` 全局广播门控 | **优点**：两级流水吞吐高，ARM Cortex-M 广泛采用。<br>**缺点**：从机拉低 `HREADY` 会强制挂起整条总线所有设备，存在多周期错误响应复杂逻辑。 |

---

## 自检清单：看懂这 10 个问题就彻底掌握了基线系统

> 对照本清单自测，能够讲清每一题的微架构细节与代码对应行号，即可证明彻底掌握了基线系统。

### Q1：为什么数据前推解决不了 Load-Use 冒险？硬件具体怎么暂停流水线并注入气泡？
**标准答案**：  
Load 指令要访问内存，数据最早只能在 **MEM 级** 从存储器读出；而紧随其后的运算指令在 **EX 级** 就要使用该操作数。在时间箭头上，数据生成的时间比需要使用的时间晚了整整 1 拍，硬件无法实现“逆向时空前推”。  
硬件在 [hazard_unit.v#L62-L63](../rtl/core/hazard_unit.v#L62-L63) 检测到 `id_ex_mem_read && (id_ex_rd == if_id_rs1 || id_ex_rd == if_id_rs2)` 时断言：
1. `stall_pc = 1`：冻结 PC 寄存器；
2. `stall_if_id = 1`：保持 IF/ID 寄存器内容不变，让被依赖的指令在 ID 级重试一拍；
3. `flush_id_ex = 1`：向 ID/EX 寄存器注入控制信号全 0 的气泡（Bubble/NOP）。  
1 拍过后，Load 指令到达 MEM 级，数据通过 MEM-EX 前推网络成功送入 ALU。

---

### Q2：既然流水线已经有了 EX-EX 和 MEM-EX 前推，通用寄存器堆内部为什么还要做“写优先直通 (Write-First Bypass)”？
**标准答案**：  
为了解决相距 2 条指令的 RAW 冲突（例如：`inst 1: add x1...` $\to$ `inst 2: nop` $\to$ `inst 3: nop` $\to$ `inst 4: add ..., x1`）。  
在第 4 周期，inst 1 恰好处在 **WB 级**（正在写入寄存器堆），而 inst 4 恰好处在 **ID 级**（正在通过组合逻辑读取寄存器堆）。如果寄存器堆内部没有写直通，inst 4 在当前拍只能读到更新前的陈旧数值。虽然可以通过额外拉一套 WB-ID 外部前推网络解决，但在 [regfile.v#L54-L60](../rtl/core/regfile.v#L54-L60) 内部用一行多路选择器 `(we && waddr == raddr) ? wdata : regs[raddr]` 进行内部直通，是最经济优雅的做法。

---

### Q3：写 `x0` 的指令（如 `addi x0, x1, 5`）会不会把错误的值前推给后面的指令？硬件在哪里做了防护？
**标准答案**：  
绝不会。硬件在两道关卡做了双保险拦截：
1. **第一道防线（前推单元）**：在 [forwarding_unit.v#L45-L50](../rtl/core/forwarding_unit.v#L45-L50) 中，前推触发条件必须严格满足 `ex_mem_rd != 5'd0` 和 `mem_wb_rd != 5'd0`，目标为 `x0` 的指令永远不可能激活前推 MUX；
2. **第二道防线（寄存器堆）**：在 [regfile.v#L48-L56](../rtl/core/regfile.v#L48-L56) 中，同步写端口判断 `if (we && waddr != 0)`，`x0` 物理上不可写；读端口强制 `raddr == 0 ? 0 : ...`，读恒为 0。

---

### Q4：分支跳转是在哪一级裁决的？跳错时流水线惩罚是几拍？冲刷了哪些流水级？
**标准答案**：  
在 **EX 级** 裁决。由 [core.v#L294-L308](../rtl/core/core.v#L294-L308) 的专用分支比较器（Branch Comparator）结合前推后的最新数据计算 `ex_br_cond`，得出 `branch_taken`。  
跳错时流水线惩罚固定为 **2 拍**（损失 2 个时钟周期）。  
`hazard_unit.v` 会拉高 `flush_if_id` 和 `flush_id_ex`，将已经取入流水线但属于错误执行路径的 **IF 级和 ID 级指令同时冲刷清零**，下一拍 PC 直接载入正确的跳转目标地址 `branch_target`。

---

### Q5：`regfile.v` 为什么故意不复位 32 个通用寄存器？加不加复位对 FPGA 综合结果有什么决定性影响？
**标准答案**：  
为了推断 FPGA 的 **分布式 RAM（LUTRAM / SLICEM）**。  
紫光同创与主流 FPGA 的 LUTRAM 原语硬件上只有写时钟和同步写使能，不具备异步/同步全局复位端口。如果在 Verilog 里写了 `if (!rst_n)` 循环清零 32 个寄存器，综合工具将无法使用紧凑的 LUTRAM，而被迫动用 **1024 个普通触发器 (DFF)** 与数十个庞大的多路选择器去搭建，消耗巨大逻辑面积并恶化布线延迟。RISC-V 规范亦不要求硬件上电复位通用寄存器（软件在 `crt0.S` 中用循环指令清零即可）。

---

### Q6：紫光 FPGA 的片上 Block RAM 读操作有 1 拍固定时钟延迟，本项目是如何做到取指“零等待周期 (Zero Wait-State)”的？
**标准答案**：  
核心在于 **“取指地址提前一拍发出”**。在 [core.v#L82-L85](../rtl/core/core.v#L82-L85) 中，送往 SRAM 取指端口 A 的地址不是经过寄存的 `if_pc`，而是直接连接组合逻辑算出的 **“下一拍 PC”**（`if_next_pc = branch ? target : pc + 4`）。BRAM 在当拍时钟沿采样该地址，在下一拍初数据刚好伴随 `if_pc` 同步进入 IF/ID 寄存器，从而将 1 拍硬件物理读延迟完全折叠掩盖在流水线流动中。

---

### Q7：为什么 `SW` 紧跟 `LW` 会抢占内存端口（BUG-002）？如果不暂停 1 拍，还有什么物理硬件解决方案？
**标准答案**：  
因为 Load 的读地址为了藏住 BRAM 延迟被提前到 **EX 级** 发出，而 Store 的写操作在 **MEM 级** 执行。当 SW 在 MEM 级写、LW 在 EX 级读时，两条指令在同一拍抢占同一个单端口数据总线 `dmem_addr`。  
除了当前的停顿 1 拍仲裁让给 Store 外，进阶硬件方案包括：  
1. **双端口数据 BRAM**：开辟独立的读、写双端口；  
2. **Store Buffer（写缓冲队列）**：Store 指令在 MEM 级直接将写地址与写数据丢入 Store Buffer 即完成指令退休，由总线在后台空闲拍写回 BRAM，后续 Load 发生冲突时直接从 Buffer 旁路前推数据。

---

### Q8：在流水线 EX 级发生停顿（Stall）时，为什么必须将当拍的前推值锁存入 ID/EX 寄存器（BUG-003）？
**标准答案**：  
前推网络是纯组合逻辑，前推数据有效的前提是“前推源指令必须停留在对应的流水级”。当 EX 级停顿而后续 WB 级指令正常写回退休时，前推源在下一拍彻底离开流水线，前推使能撤销。如果不在停顿拍将前推计算得到的数值采样锁存入 `id_ex_rs1/2_data`，下一拍操作数就会回退为过时的旧值或未知态，导致数据逃逸丢失。

---

### Q9：在 `wb_interconnect.v` 中，为什么请求信号（stb/cyc）用当拍地址译码，而返回信号（ack/dat）必须用上一拍寄存的译码结果（`sel_r`）？
**标准答案**：  
因为 CPU 的核侧访存接口是“单拍即发即过（Fire-and-forget）”，地址在 EX 级发出后只维持一拍，下一拍地址就切换了；但是挂在总线上的外设（SRAM、UART 等）具有 1 拍同步读延迟，其数据与 ACK 在请求后 **第二拍** 才能准备好。因此互连矩阵必须用触发器 `sel_r` 锁存上一拍发起请求的目标从机编号，第二拍才能将返回的数据正确引向 CPU。

---

### Q10：验证时导出的提交追踪信号（Commit Trace）为什么必须带 `wb_valid` 且只在写通用寄存器时断言 `wb_we`？只看寄存器写使能有什么漏洞？
**标准答案**：  
如果只看寄存器写使能：  
1. **漏检大量指令**：所有不写寄存器的指令（条件分支 `BEQ/BNE`、无链接跳转、所有的 `SW/SH/SB` 存储指令）将完全不会被 DiffTest 捕捉，导致控制流错误或写内存错误成为验证盲区；  
2. **气泡误判**：流水线冲刷产生的气泡指令如果没有 `wb_valid` 门控，容易被误当成合法退休指令。  
因此必须以 `wb_valid = mem_wb_valid` 作为指令真正提交的最高权威凭证。
