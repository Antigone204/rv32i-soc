# 开发日志 / Bug 记录

> 这是面试素材库。每条记录：**现象 → 定位过程 → 根因 → 修复 → 教训**。

---

## 2026-10-09 项目启动

- 确定定位：简历项目 + 个人训练，尽量使用 AI；比赛提交 11/4 18:00。
- 确定档位：分支预测、加速器数据通路、乘除法单元、Cache 手写（A 档）；CSR/trap 共写（B 档）；其余交给 AI。
- 确定 ISA 路线：先用纯 RV32I 跑 CoreMark 基线，再加 M 扩展做对比。
- 搭建本地工具链：Verilator、Icarus、Spike、xPack RISC-V GCC 15.2。

### BUG-001: 串口冒烟测试快速输入丢字与仿真过早采样

- **现象**：在 `tb_smoke` 快速连续发送 `"Hi"` 两个字符时，仿真回显报错 `FAIL: echo mismatch, n_got=25 last="\nH"`，只收到了 25 个字符（24 字符 banner + 'H'），'i' 丢失。
- **定位过程**：
  1. 检查时序波形与 `smoke_top` 逻辑，发现原设计为直通无缓冲结构：`if (tx_ready) tx_data <= rx_data`；
  2. 发送 `"H"` 需 10 个 bit 周期，在 TX 忙碌期间 `"i"` 已经通过 RX 到达，`tx_ready` 为低，导致 `"i"` 被直接丢弃；
  3. 同时 `tb_smoke` 在发送完第二个字符后仅等待 12 个 bit 周期，在实际发完两个字符所需的 20+ 个周期前便提前触发了结果判断。
- **根因**：
  1. 硬件无接收缓冲（FIFO），无法吸收突发吞吐与发送器序列化速度之间的速率差；
  2. Testbench 等待时间未充分考虑序列化累积时延。
- **修复**：
  1. 在 `smoke_top` 中实现 32 字节回显同步 FIFO，解耦 RX 接收与 TX 串行发送；
  2. `tb_smoke` 中将检查等待时间调整为充裕的 25 个 bit 周期。
- **教训**：流式通信外设即便在最简单的 demo 中，只要涉及输入突发或速率失配，就必须设计 FIFO 缓冲；自动化 testbench 需精确计算处理链路各级流水与传输周期的下界。

---

## 2026-10-13 流水线核心迭代

### BUG-002: SW 紧跟 LW 时写内存地址被覆盖与测试环境掩盖设计缺陷

- **现象**：当指令序列中 `SW` 紧跟 `LW` 且两指令访问不同内存地址时（如 `sw x3, 0(x0)` 紧跟 `lw x4, 4(x0)`），Store 的数据错误地被写入了 Load 的目标地址（导致 `dmem[0]` 未被写入，而 `dmem[1]` 被写入 40，`x4` 读回脏数据 40）。
- **定位过程**：
  1. 将集成测试程序中的 `lw x4, 0(x0)` 改为访问不同地址 `lw x4, 4(x0)` 进行定向边界复现；
  2. 观察流水线波形：当 `SW` 进入 MEM 级准备写内存、`LW` 进入 EX 级准备提前发出读地址时，两者处于同一时钟周期；
  3. 检查 `core.v` 发现 `dmem_addr` 多路选择器在 `id_ex_mem_read` 有效时强制选择了 EX 级的 `ex_alu_out`（即 Load 的地址 `0x04`），导致 MEM 级的 Store 写入使能有效时把数据写入了 `0x04` 而非 `0x00`。
- **根因**：
  1. **硬件设计根因**：Load 读地址提前在 EX 级发出、而 Store 写地址在 MEM 级维持，两者共享单内存总线 `dmem_addr`，在没有多端口 BRAM 或总线仲裁的情况下构成了未捕获的“结构冒险 (Structural Hazard)”；
  2. **测试验证根因（严重流程违规）**：原测试中 SW 与 LW 恰好访问相同地址 `0x00`，且 testbench 中的存储器模型错误地增加了一条“若本周期有写请求，读端口直接无条件返回写入数据”的旁路逻辑，把硬件结构冒险完全掩盖了。
- **修复**：
  1. **RTL 级修复**：在 `hazard_unit` 中增加对 SW 紧跟 LW 的结构冒险检测（MEM 级为有效 Store、EX 级为有效 Load 时触发）。发生冲突时硬件暂停 1 拍（冻结 `PC`、`IF/ID`、`ID/EX`，向 `EX/MEM` 注入气泡），本拍内存端口与写使能完全让给 Store；下一拍 Store 移入 WB，Load 正常使用端口发出读地址；
  2. **Testbench 规范化**：彻底删除 testbench 中迁就设计的“写时直接返回写入数据”旁路，恢复为完全模拟真实 FPGA BRAM 行为的标准同步时钟读写；
  3. **定向测试覆盖**：编写定向测试台 `tb_core_hazard_mem.v`，覆盖 SW$\to$LW 地址不同与地址相同两种工况。
- **教训（铁律）**：
  1. **测试环境绝不能迁就或掩盖硬件设计缺陷**。Testbench 的外设/存储器行为模型必须严格反映物理芯片规范（如标准 BRAM 的读写时序），绝不能通过魔改验证环境使 Bug 被动“通过”；
  2. **流水线跨级复用共享硬件资源时必须分析并发冲突**：一旦将某个操作的生效级提前（如读地址提早一拍在 EX 级发出），必须同步审查前序指令在后级（MEM 级）占用同类资源的冲突情景并设计结构停顿仲裁。

---

### BUG-003: EX 级停顿期间前推操作数丢失与前推源退休逃逸

- **现象**：当某条指令在 EX 级被流水线停顿冻结（例如前述 SW 紧跟 LW 引发的结构冒险），且该指令的操作数依赖于当前处于 WB 级的前序指令前推提供时（例如 `addi x1, x0, 8` $\to$ `sw x3, 4(x0)` $\to$ `lw x4, 0(x1)`）：在停顿第 1 拍，WB 级成功前推正确的 `x1=8` 给 LW；但在下一拍，`addi` 顺利写回并退出流水线，前推网络撤销前推使能，EX 级操作数选择器回退至读取 `id_ex_rs1_data`。由于停顿信号未更新 `id_ex_rs1_data`，其仍然保留 ID 级译码时读到的未就绪旧值（仿真中未复位的通用寄存器表现为 `xxxxxxxx`），导致 Load 指令发出错误/未知内存地址，`x4` 读回脏数据。
- **定位过程**：
  1. 运行最小复现探针测试 `tb_probe_stallfwd.v`，观察流水线逐拍波形；
  2. 捕获停顿第 1 拍：LW 在 EX，SW 在 MEM，addi 在 WB，`forward_a` 为 `2'b01`，前推值 `ex_fwd_val_a = 8` 生效，但由于 `stall_id_ex` 有效，流水线寄存器整体保持；
  3. 捕获停顿第 2 拍：addi 完成写回移出流水线，`forward_a` 归 `2'b00`，`ex_fwd_val_a` 瞬间跌回 `id_ex_rs1_data`（旧值/`'x`），导致 Load 地址计算失真；
  4. 确认根因是纯组合前推输出随前推源退休而“瞬态消失”，未在停顿时钟沿被本级寄存器同步锁存。
- **根因**：
  流水线前推网络是无状态的纯组合逻辑，前推数据仅在生产者指令停留在对应流水级时有效。当本级流水线寄存器被冻结（`stall_id_ex = 1`），而后级流水线正常前移（退休）时，原本生效的前推通路在下一周期会因生产者退出流水线而断开。若停顿逻辑仅仅冻结寄存器而不锁存当拍的前推值，前推来的最新数据就会因“前推源逃逸”而永久丢失。这是所有带前推与停顿流水线的经典通用缺陷，在后续总线握手、Cache Miss 等多周期停顿机制中同样是致命隐患。
- **修复**：
  1. **RTL 级前推值锁存**：修改 `core.v` 中 ID/EX 级间寄存器的同步时序逻辑。当 `stall_id_ex` 有效且未被冲刷时，保持其他所有控制信号与立即数不变，但将 `id_ex_rs1_data` 与 `id_ex_rs2_data` 实时更新为当拍前推多路选择器的输出值（`ex_fwd_val_a` 与 `ex_fwd_val_b`）：
     ```verilog
     end else if (stall_id_ex) begin
         id_ex_rs1_data <= ex_fwd_val_a;
         id_ex_rs2_data <= ex_fwd_val_b;
     end
     ```
     确保当拍有效的前推结果在时钟上升沿被锁入本级寄存器，后续周期即使前推源退休离开，本级寄存器依然持有正确数值；
  2. **双操作数回归与定向验证**：将复现测试 `tb_probe_stallfwd.v` 收录进 `sim/core/` 并集成至 `make test-core`。测试同时覆盖：
     - Case 1 (`rs1` 停顿前推)：Load 基址前推锁存，验证 `x4 = 55`，`dmem[1] = 77`；
     - Case 2 (`rs2` 停顿前推)：被停顿指令的 `rs2` 字段前推锁存，验证生产者退休后 `rs2_data` 稳定保持 99，后续运算得到 100；
     - 全程无 `'x'` 未知态信号监测。
- **教训**：
  1. **流水线停顿的前推值锁存定律**：当流水线某一级停顿而更老的流水级继续流动时，所有来自后级的前推操作数必须在停顿拍被本级寄存器采样锁存，防止前推源退休导致数据断流；
  2. **对称性设计与防御性验证**：处理微架构数据通路时，双操作数（`rs1`/`rs2`）必须严格对称处理；编写定向测试不仅要验证当前触发 bug 的特定通路（如 Load 的 `rs1`），也要对潜在受影响的镜像通路（`rs2`）做闭环回归。
---

## 2026-10-13 自动化测试与 Spike 差分验证搭建 (阶段 T1–T4)

### 阶段进展与成果总结

顺利完成官方 RISC-V 测试集环境移植与 Spike Golden Model 差分比对链搭建：
- **测试覆盖**：导入官方 `rv32ui` 基础指令集共 38 个严苛测试用例（覆盖算术、逻辑、移位、分支、跳转、以及 LB/LH/LW/SB/SH/SW 等高边界 Corner Cases）；
- **自动化执行 (`make isa-test`)**：38/38 项测试全部 100% 绿灯 PASS，耗时仅 2.8 秒，平均 CPI 处于 1.07~1.28 优异区间；
- **Spike DiffTest (`make difftest`)**：与官方 Spike 模拟器的提交追踪（PC、目的寄存器 rd、写入值 wdata）实现 38/38 逐条指令 100% 吻合（0 Mismatch）。

### 实战技术细节与收获

1. **无 CSR/特权级测试环境适配**：
   - 官方 `riscv-tests` 依赖 `mstatus`/`tohost` CSR 与 `ecall` 陷阱；
   - 本方案定制精简 `sim/isa/env/riscv_test.h`，复位清空全部通用寄存器，并将测试结束机制精简为向特殊内存信箱地址 `0x0000_1000` 写入测试结果（1 为 PASS，其余为失败用例编号），成功在纯基础 RV32I 核上无缝执行官方测试。
2. **Spike 硬件限制与 ELF 动态重定位**：
   - Spike 源码将 `[0x0, 0x1000)` 硬编码为 Debug Module，默认拒绝将 DRAM 载入 `0x0000_0000` 地址空间；
   - 差分脚本采用 `riscv-none-elf-objcopy --change-addresses 0x80000000` 动态映射 ELF，并基于模 $2^{32}$ 代数恒等式 `(core_val + 0x80000000) & 0xFFFFFFFF == spike_val` 统一归一化 PC 相对寻址（`auipc`、`jal`、`jalr`、`la`），消除虚拟地址基址偏差，实现了完美的指令级等价性验证。
3. **真实 BRAM 存储器模型与字节流装配**：
   - `tb_isa.v` 严格遵照 FPGA 同步 BRAM 1 拍读延迟模型；
   - 正确规避了 Verilog `$readmemh` 直接读取 8 位字节流 Hex 填入 32 位字数组时的高位补零陷阱，在 Testbench 中进行了精确的小端字拼接装配。

---

## 2026-10-14 SoC 总线与外设规格设计 (阶段 S1a)

### 阶段目标

为 RV32I 流水线核编写 SoC 集成规格说明书，定义总线协议、存储器映射与外设寄存器接口，为后续 RTL 实现（S1b）和 CoreMark 移植（S1d）铺路。

### 关键设计决策

1. **总线协议选择 Wishbone B4 Classic Cycle**：
   - 开源标准（OpenCores 维护），文档公开完整；
   - Classic 单拍传输模式与现有 BRAM 1 拍延迟完美匹配，S1 阶段无需引入流水线停顿扩展；
   - 未来可平滑升级至 Pipelined / Block Cycle 模式对接 Cache 与 DDR3。

2. **内存映射参照 SiFive FE310（RISC-V 生态事实标准）**：
   - SRAM `0x0000_0000`（兼容现有 ISA 测试的零起始地址）；
   - CLINT `0x0200_0000`（RISC-V 特权级规范硬性约定，工具链默认）；
   - UART `0x1001_0000`（SiFive 惯例，留出扩展空间）；
   - DDR3 `0x8000_0000`（RISC-V 标准 DRAM 基址，与 Spike 兼容）。

3. **指令端口不走 Wishbone，直连 SRAM Port A**：
   - 利用 FPGA 双端口 BRAM 物理特性，Port A 取指 + Port B 数据访问零冲突；
   - 消除取指与数据访问的总线仲裁开销，保证取指零等待状态。

### 交付物

- `docs/spec/soc.md`：完整 SoC 规格说明书（9 章，含 Wishbone 协议要点、存储器映射、6 个 RTL 模块接口定义、寄存器映射、验证计划与扩展路径）。

---

## 2026-10-15 SoC 总线与外设 RTL 实现与系统级集成 (阶段 S1b)

### 阶段目标与交付物

依据 `docs/spec/soc.md` 规格，完成 Wishbone B4 总线、片上外设及 SoC 顶层完整 RTL 与验证：
- **RTL 交付**：
  - `rtl/soc/wb_core_bridge.v`：CPU 核 Native dmem 端口到 Wishbone B4 Master 桥接器；
  - `rtl/soc/wb_interconnect.v`：基于地址解码的 1-Master 4-Slave 互联交叉矩阵；
  - `rtl/soc/wb_sram.v`：64KB 双端口可综合/可推断 BRAM 存储器（Port A 取指直连，Port B 挂载 Wishbone）；
  - `rtl/soc/wb_uart.v`：SiFive FE310 寄存器布局的 UART 控制器（内含 8 字节收发双 FIFO，驱动 `uart_tx`/`uart_rx` PHY）；
  - `rtl/soc/wb_clint.v`：标准 64 位单调递增时钟 `mtime`/`mtimecmp` 与定时器中断发生器；
  - `rtl/soc/soc_top.v`：SoC 顶层集成模块。
- **验证交付**：
  - 单元测试：`tb_wb_interconnect.v`（含 7 项定向测试，全面覆盖单次/连续未映射地址虚拟 ACK、跨从设备背靠背连续切换与总线空闲 ACK 回落）、`tb_wb_uart.v`、`tb_wb_clint.v`（全部通过）；
  - 系统集成测试：`sim/soc/test_soc.S` + `sim/soc/tb_soc.v`（验证汇编指令经由 Wishbone 访问 SRAM、向 UART 打印 "Hi!\n" 并在 TB 端接收校验字符流、轮询 CLINT 递增计数；支持高地址 `0xFFFF_FFF0` 与 `0x0000_1000` 信箱；触发当拍即时锁存性能指标，消除串口排空等待污染）；
  - 回归测试：`make lint`（0 警告）、`make unit-test`、`make test-core`、`make test-soc`、`make isa-test`（38/38）、`make difftest`（38/38 Spike DiffTest 100% 匹配）。

---

### BUG-004: UART 波特率计数器截断导致除二采样失真

- **模块**：`rtl/soc/uart_rx.v`, `rtl/soc/uart_tx.v`
- **现象**：在单元测试中设置较小波特率参数 `CLKS_PER_BIT=16` 时，UART 接收器在检测到起始位（Start bit）进入 `RX_STATE_START` 后，计数器立即触发，误报 Glitch 退出，无法接收到正确数据。
- **定位过程**：
  - 查看波形，发现采样计数器在进入 `RX_STATE_START` 后仅经过 0 个周期就判定超时并触发 glitch 退出；
  - 检查代码发现：`localparam [CW-1:0] CNT_MID = CLKS_PER_BIT[CW-1:0] / 2;`；
  - 当 `CLKS_PER_BIT = 16`，其二进制为 `5'b10000`。而位宽计算为 `CW = $clog2(16) = 4`；
  - 对 16 进行 `[3:0]` 截断，结果恰好为 `4'b0000 = 0`，导致 `CNT_MID = 0 / 2 = 0`！计数器立即满足条件并清零。
- **根因**：参数截断表达式在整型运算前执行了按位截断，当 `CLKS_PER_BIT` 恰为 2 的整数幂时，低 `CW` 位全为 0。
- **修复**：先在整型语义下除以 2，再赋值给带位宽的 localparam：
  ```verilog
  localparam [CW-1:0] CNT_MID = (CLKS_PER_BIT / 2);
  localparam [CW-1:0] CNT_MAX = (CLKS_PER_BIT - 1);
  ```
  配合 Verilator 豁免注释 `/* verilator lint_off WIDTHTRUNC */`。
- **教训**：Verilog 参数与常量计算中，必须警惕位宽截断先于除法/乘法运算生效的陷阱。对于位宽定义，`$clog2(MAX + 1)` 才能容纳最大值，或者在纯整型算术之后再进行位宽规整。

---

### BUG-005: UART 控制器连续 Store 写入丢包与 FIFO 读指针时序竞争

- **模块**：`rtl/soc/wb_uart.v`
- **现象**：CPU 执行连续两个 `sw` 写入 UART `txdata` 寄存器（如打印 "Hi"）时，第二个字符丢失，并且 TX PHY 发送出来的第一个字符是未初始化的 `0xXX` 垃圾数据。
- **定位过程**：
  1. 打印丢失：观察 CPU 访存请求与总线 ACK。CPU 流水线发出的 `dmem_we` 紧密相连（单拍脉冲）。由于之前为了防止重复写入，在 `tx_push` 上增加了 `~wbs_ack_o` 门控：
     ```verilog
     tx_push <= wbs_cyc_i & wbs_stb_i & wbs_we_i & ~wbs_ack_o & ...;
     ```
     在上一拍刚产生 `wbs_ack_o = 1` 时，第二拍新的 `sw` 请求刚好到达，此时 `~wbs_ack_o` 恰为 0，导致第二拍写操作被误屏蔽。
  2. 垃圾字符：观察 FIFO 弹出逻辑，原实现中 `tx_phy_data = tx_mem[tx_rptr]` 为组合逻辑输出，当发现 PHY 空闲时，触发 `tx_pop <= 1`；在下一个时钟上升沿，`tx_rptr <= tx_rptr + 1`，同时 `tx_phy_valid <= 1`。但此时组合逻辑的 `tx_mem[tx_rptr]` 已经由于 `tx_rptr` 加 1 而指向了下一个尚未写入的空单元！PHY 发送出去的是后一个无效字节。
- **根因**：
  1. Wishbone Classic 单拍总线在面对背靠背的连续单周期传输时，不能简单将前一拍的 ACK 状态作为当前拍写的互斥条件，必须严格按照当前周期的 `cyc & stb & we` 生成操作；
  2. 同步 FIFO 的读数据输出若依赖组合寻址，在出队脉冲使读指针加 1 的瞬间，数据线会立刻跳变到下一个条目。PHY 在握手确认时采样到的数据已不是弹出条目。
- **修复**：
  1. 去除 `~wbs_ack_o` 对写使能的误门控，`wbs_ack_o <= wbs_cyc_i & wbs_stb_i`；
  2. 在 `tx_pop` 触发时，同步将当前 `tx_mem[tx_rptr]` 打拍锁存入 `tx_phy_data`，并用 `~tx_phy_valid` 锁住下一拍的重复 pop，彻底消除了指针前移造成的数据撕裂。
- **教训**：在软硬件协同总线接口中，背靠背（Back-to-Back）传输和单周期脉冲是非常关键的边界场景。FIFO 的读出数据有效性与读指针推进必须在时序上严格对齐（对同步 FIFO，最稳妥的做法是在 pop 发生时锁存读出数据，或使用 Skid Buffer / FWFT 机制）。

---

### BUG-006: 仿真 Mailbox 串口排空延时污染性能计数器与信箱地址冲突隐患

- **模块**：`sim/soc/tb_soc.v`, `docs/spec/soc.md`
- **现象**：在 SoC 顶层冒烟测试 `test_soc.S` 运行中，虽然核心测试逻辑仅 ~30 条汇编指令（含 50 次循环延时，实际仅退休 128 条指令），但 Testbench 最终输出的性能统计却为 `Cycles: 2733, Instructions: 963, CPI: 2.84`，指令数与周期数严重失真，CPI 偏高数倍。
- **定位过程**：
  1. 检查 `test_soc.S` 汇编执行流程，程序在向 Mailbox 写入 1（PASS）后进入 `spin_pass: j spin_pass` 死循环等待仿真退出；
  2. 检查 `tb_soc.v` 发现：在检测到 Mailbox 写入后，为了防止物理 UART 的 TX FIFO 内部未发完的字符被直接截断，Testbench 执行了 `repeat (2500) @(posedge clk);` 等待物理串口串行序列化输出；
  3. 在这 2500 个等待周期内，CPU 核心并没有停止工作，而是在 `spin_pass` 死循环中高速空转，持续产生 `j spin_pass` 的取指、执行与写回，导致仿真周期计数器 `cycles` 暴增 2500 拍，`perf_instret` 额外虚增了 800+ 条指令；
  4. 同时审查发现，旧 Mailbox 地址 `0x0000_1000` 位于片上 64KB SRAM（`0x0000_0000 ~ 0x0000_FFFF`）内，在后续运行 C 程序/CoreMark 时与代码段/全局数据段/栈段存在物理地址冲突隐患。
- **根因**：
  1. Testbench 将“等待外设排空”的仿真延时与“被测程序本身”的执行周期/指令统计混为一谈，未在 Mailbox 触发时刻对硬件性能计数器进行即时采样锁存；
  2. 仿真退出信箱地址侵占了物理 SRAM 的可用寻址空间。
- **修复**：
  1. **性能计数器即时锁存**：在 `tb_soc.v` 检测到 Mailbox 写入（`u_soc.u_core.dmem_wdata == 32'h0000_0001`）的**当拍**（在 `repeat (2500)` 执行前），立即锁存当拍的 `perf_cycle` 与 `perf_instret`：
     ```verilog
     final_cycles  = perf_cycle;
     final_instret = perf_instret;
     repeat (2500) @(posedge clk);
     $display("Cycles: %0d, Instructions: %0d, CPI: %0.2f",
              final_cycles, final_instret, $itor(final_cycles) / $itor(final_instret));
     ```
     修复后实测输出精确反映程序真实性能：`Cycles: 233, Instructions: 128, CPI: 1.82`；
  2. **高地址仿真信箱与后向兼容**：扩展 Mailbox 触发条件支持高位未映射地址 `0xFFFF_FFF0`（`SIM_CTRL`），同时保持兼容旧地址 `0x0000_1000`；在硬件上依赖 `wb_interconnect` 对未映射地址返回虚拟单拍 `ACK=1, DAT=0`，避免对 64KB SRAM 内部物理空间的污染。
- **教训**：芯片验证中的性能剖析（Profiling）必须将被测核心的有效运行区间与仿真环境自身的清理/排空操作在时序上完全解耦；仿真控制信箱宜选择远离任何合法存储器与外设的保留高地址。
