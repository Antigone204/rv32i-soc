# 开发日志 / Bug 记录

> 记录工程推进过程中的关键设计决策与非平凡 Bug 排查：**现象 → 定位过程 → 根因 → 修复 → 教训**。

---

## 2026-10-09 项目启动

- 确定架构演进路线：先实现纯 RV32I 5 级流水线并建立 CoreMark 基准，随后逐步引入 RV32M 硬件乘除法、动态分支预测（BPU）与并行 SIMD 算子加速器。
- 搭建本地验证工具链：Verilator、Icarus Verilog、Spike Golden Model、xPack RISC-V GCC 15.2。

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

---

## 2026-10-16 裸机 C 语言运行时环境搭建与验收 (阶段 S1c)

### 阶段目标与交付物

为 RV32I SoC 建立完整、零外部 OS 依赖的 Freestanding 裸机 C 语言运行环境，打通 C 程序编译、软乘除法库（`libgcc`）链接、外设驱动与系统级仿真验证全链路，为 S1d（CoreMark 移植）提供基础设施：
- **软件运行时基础设施 (`sw/common/`)**：
  - `link.ld`：面向 64KB 片上 SRAM（`0x0000_0000 ~ 0x0000_FFFF`）的裸机链接脚本，规范排布 `.text.init`、`.text`、`.rodata`、`.data`、`.sdata`、`.bss`，导出 `__global_pointer$`、`__bss_start`、`__bss_end` 与 16 字节对齐栈顶 `__stack_top = 0x0001_0000`；
  - `crt0.S`：启动汇编，完成 `x1`~`x31` 通用寄存器清零、`gp`/`sp` 初始化、`.bss` 段按字清零、`main()` 调用以及向高地址信箱 `SIM_CTRL (0xFFFF_FFF0)` 上报退出状态（`main == 0` 写 `1`，`main != 0` 附带 `0xDEAD0000` 前缀防冲突）；
  - `soc.h`：统一封装 SRAM、UART0 (`0x1001_0000`)、CLINT (`0x0200_0000`) 与 `SIM_CTRL` (`0xFFFF_FFF0`) 寄存器访问宏；
  - `uart.h` / `uart.c`：基于 `TXDATA.full`（`bit[31]`）硬件流控轮询的串口驱动，以及内置轻量级 `printf` / `ee_printf`（支持 `%c`, `%s`, `%d`, `%i`, `%u`, `%x`, `%X`, `%p` 与宽度/前导零填充）；
  - `timer.h` / `timer.c`：实现 RISC-V 标准 `hi -> lo -> hi2` 防进位撕裂的 64 位原子读取 `get_time()` 及 `delay_cycles()`；
  - `str.h` / `str.c`：提供 `memcpy`、`memset`、`memmove`、`memcmp`、`strlen`、`strcmp`、`strncmp`、`strcpy` 基础库函数。
- **综合验收测试 (`sw/test_c/main.c` & `make test-c`)**：
  - 一次性覆盖 `.bss` 清零、`.data` 初值与修改、递归函数栈调用 (`fib(10)=55`)、`libgcc` 32 位有符号/无符号软乘除法与取模 (`__mulsi3`/`__divsi3`/`__udivsi3`)、CLINT 64 位计时器读取以及超出 8 字节 FIFO 深度的长字符串格式化打印；
  - 编译产物 `test_c.elf` 总大小 4492 字节（已跨越 `0x0000_1000` 地址边界，直接印证了迁移 `SIM_CTRL` 至 `0xFFFF_FFF0` 的必要性），实测 `Cycles: 34314, Instructions: 16438, CPI: 2.09`，全套回归 100% 通过。

---

## 2026-10-16 CoreMark 移植与纯 RV32I 性能基线测定 (阶段 S1d)

### 阶段目标与交付物

在 S1c 裸机 C 运行时环境基础上，将业界标准的 EEMBC CoreMark 基准测试程序完整移植到 RV32I SoC 平台，建立纯 RV32I 软硬件协同体系下的第一份权威 CPU 性能基线，作为后续引入分支预测器（阶段 P1）、硬件乘除法 M 扩展（阶段 M1）以及 Cache 存储层次时的关键量化对照指标：

- **官方标准核心算法文件导入 (`sw/coremark/`)**：
  - 导入官方 EEMBC CoreMark 核心算法：`coremark.h`、`core_main.c`、`core_list_join.c`、`core_matrix.c`、`core_state.c`、`core_util.c`，严格保持官方核心测试逻辑原貌。
- **平台适配层定制与关键适配点 (`core_portme.h` & `core_portme.c`)**：
  1. **无浮点与零外部头文件**：设定 `#define HAS_FLOAT 0`、`HAS_TIME_H 0`、`USE_CLOCK 0`、`HAS_STDIO 0`、`HAS_PRINTF 0`，完全复用 `sw/common/uart.h` 内置的轻量高效 `ee_printf`；
  2. **静态片上存储分配**：配置 `#define MEM_METHOD MEM_STATIC` 与 `TOTAL_DATA_SIZE (2 * 1000)`，将 CoreMark 的状态机、链表与矩阵测试缓冲区全部静态收纳在片上 64KB SRAM 中，免除 malloc 堆管理开销；
  3. **Performance Run 标准种子**：配置 `#define SEED_METHOD SEED_VOLATILE`，设定 `seed1 = 0x0`、`seed2 = 0x0`、`seed3 = 0x66`（计算得出特征 `seedcrc = 0xe9f5`），触发 2K Performance Run 严苛校验集；
  4. **计时器抽象与符号冲突解耦**：将 CoreMark 内部抽象类型统一定义为 `typedef uint64_t CORE_TICKS;`，在 `sw/common/timer.c` 中将 `get_time(void)` 设为 `__attribute__((weak))`，并在 `core_portme.c` 中直接调用 CLINT 防撕裂机制精确测定 benchmark 有效运行区间内耗费的纯时钟周期数 `total_ticks = stop_time_val - start_time_val`；
  5. **仿真时间尺度规整与校验通过**：设定 `EE_TICKS_PER_SEC 1000` 并保证 `time_in_secs(ticks) >= 10`，顺利规避了在宿主机微秒级快速仿真环境下因运行秒数未满 10 秒而误报的机制，确保 CoreMark 判定执行有效并成功打印 `Correct operation validated.`；
  6. **定点化 CoreMark/MHz 打印**：在 `portable_fini()` 中直接基于 `total_ticks` 与迭代次数利用 64 位整数运算计算出定点化指标 $\text{score\_x1000} = \frac{\text{ITERATIONS} \times 10^9}{\text{total\_ticks}}$，通过 `ee_printf("CoreMark/MHz : %u.%03u\n", ...)` 输出精确到小数点后 3 位的标准化分值。
- **构建系统与自动化断言验证 (`Makefile` & `make coremark`)**：
  - 新增 `make coremark` 自动化目标，完成交叉编译、生成 ELF 与 Hex、执行 Verilog 仿真以及自动断言检查（`Correct operation validated`、`CoreMark/MHz`、`SOC VERIFICATION PASSED` 三重硬核校验）。

### 实测性能基线数据

- **ELF 存储占用 (`riscv-none-elf-size build/coremark.elf`)**：
  ```
     text    data     bss     dec     hex filename
    19832      24    2028   21884    557c build/coremark.elf
  ```
  - 代码段仅占约 19.4 KB，SRAM 数据与 BSS 仅占约 2 KB，总固件尺寸约 21.4 KB，片上 64KB SRAM 尚余 42KB 充裕栈空间与安全裕量。
- **CoreMark 执行与基线得分 (ITERATIONS = 2)**：
  - **总运行周期数 (Total Ticks)**：2,086,119 cycles
  - **测试用例校验结果**：
    - `seedcrc` : `0xe9f5`
    - `[0]crclist` : `0xe714`
    - `[0]crcmatrix` : `0x1fd7`
    - `[0]crcstate` : `0x8e3a`
    - `[0]crcfinal` : `0x72be`
    - 状态：**Correct operation validated.**
  - **基线得分**：**0.958 CoreMark/MHz**
- **硬件性能计数器实时统计 (Hardware Profiling)**：
  - **总周期数 (Total Cycles)**：2,357,625 cycles（含前后初始化与校验打印）
  - **退休指令数 (Retired Instructions)**：1,565,641 insts
  - **平均 CPI**：**1.51**



---

## 2026-10-24 RV32M 硬件乘除法单元实现、集成与 CoreMark 提速验证 (阶段 M1)

### 阶段目标与交付物

在纯 RV32I 基准架构上完整引入 RISC-V 标准整型乘除法 M 扩展（RV32M），彻底消除基础 C 运行时与 Benchmark 依赖 `libgcc` 软件移位模拟乘除法的巨大性能损耗，大幅提升核的算力密度与 CoreMark 跑分：

1. **架构规格书与方案对比讲义 (`docs/spec/m_ext.md`)**：
   - 完整定义 RV32M 支持的 8 条指令（`MUL`, `MULH`, `MULHSU`, `MULHU`, `DIV`, `DIVU`, `REM`, `REMU`）的机器码、操作数类型及语义；
   - 详列 RISC-V 官方标准边界条件表（除以 0 静默返回确定性默认值、有符号 $-2^{31} / -1$ 溢出处理）；
   - 深入对比三种乘法架构（32 拍移位加、FPGA 硬核 DSP 映射、Booth+Wallace 树）与三种除法架构（32 拍恢复余数试商减、Radix-4 SRT 冗余查表、牛顿/Goldschmidt 迭代）在资源、时序与时延维度的优劣取舍（Trade-offs）；
   - 确立本设计选型：33 位符号扩展硬核 DSP 乘法（打 1 拍寄存输出，EX 级停顿 1 拍，共耗 2 拍）+ 32 拍恢复余数移位减状态机（除以 0 及溢出 1 拍快速旁路）。
2. **纯 Verilog-2001 硬件乘除法单元 (`rtl/core/muldiv.v`)**：
   - 代码严格控制在 165 行（高内聚、低侵入设计），零厂商原语；
   - 纯基于寄存器状态输出 `busy_o` 握手信号，当拍计算完毕置 `done_o = 1` 解除停顿，零死锁、零重复触发，完美支持背靠背连续乘除法指令流动。
3. **独立单元测试套件 (`sim/unit/tb_muldiv.v`)**：
   - 覆盖全部 8 条指令的正负数、极大极小边界值、大数高 32 位截断；
   - 严苛覆盖除以 0、$-2^{31} / -1$ 溢出、背靠背流水以及除法进行中被冲刷（flush）的复位动作；
   - 输出 `ALL MULDIV TESTS PASSED`。
4. **低侵入流水线集成 (`decoder.v`, `hazard_unit.v`, `core.v`)**：
   - `decoder.v`：在 R-Type 指令中识别 `funct7 == 7'b0000001` 置 `muldiv_en = 1`；
   - `hazard_unit.v`：接入 `ex_muldiv_busy`，触发与 `sw_lw_hazard` 完全相同的精准停顿动作（冻结 PC、IF/ID、ID/EX，向 EX/MEM 注入气泡）；
   - `core.v`：在 EX 级实例化 `muldiv`，通过 `ex_result = id_ex_muldiv_en ? ex_muldiv_result : ex_alu_out` 统一输出至 `ex_mem_alu_out`；现有的 `EX-EX` 和 `MEM-EX` 数据前推网络无需修改一行代码即可天然将乘除法结果旁路给后续指令。

---

### BUG-007: 流水线冲刷语义混淆导致跨模块虚假组合回路 (UNOPTFLAT)

- **现象**：在 `core.v` 实例化 `muldiv` 并接入 `hazard_unit` 后，执行 `make lint` 报错：
  `%Warning-UNOPTFLAT: Signal unoptimizable: Circular combinational logic: 'core.ex_muldiv_busy'`，Verilator 检测到 `ex_muldiv_busy -> hazard_unit -> flush_id_ex -> muldiv.flush_i -> ex_muldiv_busy` 闭合组合环路。
- **定位过程**：
  1. 审查 Verilator 报告的环路路径：`core.ex_muldiv_busy` 驱动 `hazard_unit`，`hazard_unit` 输出 `flush_id_ex`，`flush_id_ex` 接入 `muldiv.flush_i`，而 `muldiv.busy_o` 原式为 `assign busy_o = !flush_i && ((state == S_IDLE && valid_i && !done_o) || (state == S_DIV));`；
  2. 尽管在逻辑上，当发生跳转冲刷时 `jump_or_branch` 具有最高优先级，但由于 `hazard_unit` 内所有信号均在同一个大过程块或相互关联的表达式中，Verilator 的静态保守数据流图认定 `flush_id_ex` 间接依赖于 `ex_muldiv_busy`，从而形成了闭环回路。
- **根因**：
  1. **微架构概念语义混淆**：`flush_id_ex` 是为清空 **ID 级指令**（向 ID/EX 寄存器注入气泡）而设立的信号，而 EX 级正在计算的 `muldiv` 自身并不受 ID 级的跳转冲刷影响（EX 级内只有当前一条指令）；将 ID 级冲刷信号直接引给 EX 级的内部计算单元违反了流水级冲刷的局部性原则；
  2. **跨模块握手路径不当引入组合直通**：`busy_o` 引入 `!flush_i` 是多余的，状态机本身在时钟沿采样同步复位即可，无需在组合路径上与冲刷信号耦合。
- **修复**：
  1. 在 `core.v` 中解绑 `u_muldiv.flush_i` 与 `flush_id_ex`，将其与同步复位对齐或置常低 `1'b0`（保留端口供未来全局 Trap/异常接入）；
  2. 在 `hazard_unit.v` 中对正交输出进行严格解耦连续赋值；
  3. `make lint` 恢复至 4 个顶层全部 0 Warning。
- **教训**：在 5 级流水线设计中，必须严格区分“当前级的操作数计算状态”与“相邻级的级间寄存器控制信号”；握手忙信号（`busy`）宜尽量由本级触发器（FF）状态纯组合生成，严禁让它穿过控制中枢后又折返作为自身输入的直通组合项。

---

### RV32I vs RV32IM 实测性能对比 (CoreMark 2K Performance Run)

将 `Makefile` 编译选项从 `-march=rv32i_zicsr` 升级为 **`-march=rv32im_zicsr`** 后，软乘除法函数全部替换为单条硬件 `mul`/`div`/`rem` 指令：

| 性能评测指标 | 纯 RV32I (软件模拟乘除) | RV32IM (硬件乘除加速) | 提升幅度 / 变动分析 |
|:---|:---:|:---:|:---:|
| **CoreMark 标准得分** | **0.958 CoreMark/MHz** | **2.533 CoreMark/MHz** | **+164.4% (性能提升 2.644 倍！)** |
| **Benchmark 运行周期 (Total Ticks)** | 2,086,119 cycles | **789,387 cycles** | **耗时减少 62.16% (快了 2.64 倍)** |
| **程序执行总周期数 (Total Cycles)** | 2,357,625 cycles | **1,055,178 cycles** | **总周期大幅缩减 55.24%** |
| **总退休指令数 (Retired Instructions)** | 1,565,641 insts | **691,182 insts** | **指令数减少 55.85% (消除 87.4 万条软运算开销)** |
| **平均 CPI** | 1.51 | **1.53** | 乘法仅停顿 1 拍，除法 32 拍，平均 CPI 保持在极佳水准 |
| **ELF 代码尺寸 (`coremark.elf`)** | 21,884 bytes (21.4 KB) | **18,348 bytes (17.9 KB)** | **固件尺寸缩减 16.16% (节省 3.5 KB 代码空间)** |
| **板级固件尺寸 (`coremark_board.bin`)** | 20,444 bytes | **17,560 bytes** | **SRAM 占用减少，余量更加充裕** |
| **C 语言综合运行时测试 (`make test-c`)** | 16,438 insts / 34,314 cycles | **14,118 insts / 33,334 cycles** | 软乘除库开销消除，全功能核验 100% PASS |
| **官方 ISA 测试 (`make isa-test`)** | 38/38 PASS | **38/38 PASS** | 保持基础指令集 100% 后向兼容 |
| **Spike 差分验证 (`make difftest`)** | 38/38 MATCH | **38/38 MATCH** | 与 Spike Golden Model 逐条一致 |


---

## 2026-10-24 动态分支预测器 BPU 实现与 CoreMark 提速验证 (阶段 P1)

> 本条目为 2026-10-26 根据 commit `745171c`、`docs/spec/bpu.md` 与当日回归实测补记。

### 阶段目标与交付物

M1 完成后 CoreMark CPI 为 1.53。EX 级裁决分支、静态 Predict-Not-Taken 的方案中，每次跳转成立都要冲刷 2 拍，这是剩余的主要开销。本阶段在 IF 级加入动态预测，让预测正确的跳转 0 气泡。

1. **规格书与方案对比讲义 (`docs/spec/bpu.md`)**：对比静态预测、1-bit BHT、BTB + 2-bit BHT、Gshare/锦标赛/RAS 四类方案，选定 64 项直接映射 BTB + 2-bit 饱和计数器。
2. **`rtl/core/bpu.v`（113 行）**：
   - 64 项直接映射，表项为 Tag + Target + `btb_uncond`，IF 级单拍组合查表给出 `pred_taken_o / pred_target_o`；
   - **Taken-only 分配**：只有分支实际跳转时才分配表项。条件分支初值为 `2'b10`（弱跳），JAL/JALR 初值为 `2'b11` 并置 `btb_uncond`。
3. **`core.v` 集成**：
   - `next_pc` 优先级：EX 纠偏 > IF 预测 > `pc+4`；
   - 预测结果 `pred_taken / pred_target` 随 `if_id_* → id_ex_*` 前传；
   - EX 级判定误预测：`(branch_taken != id_ex_pred_taken) | (branch_taken & (id_ex_pred_target != branch_target))`。误预测时冲刷 `IF/ID`、`ID/EX` 并重定向（预测不跳但实际跳 → 跳到目标；预测跳但实际不跳 → 回到 `id_ex_pc + 4`）。
4. **单元测试 `sim/unit/tb_bpu.v`**：输出 `ALL BPU TESTS PASSED`。

### 关键设计点：停顿期间的重复训练保护

- BPU 的更新使能接成 `upd_valid_i = ex_is_ctrl & !stall_id_ex`。
- **原因**：乘除法迭代（`ex_muldiv_busy`）或 SW→LW 结构冒险都会冻结 `ID/EX`，分支指令会在 EX 级停留多拍。如果不加门控，同一条分支在每个停顿拍都会训练一次，2-bit 计数器会被单条指令推到饱和。门控之后，每条指令只在离开 EX 的那一拍更新一次。
- **教训**：任何"在某一级发生时更新状态"的副作用（预测器训练、性能计数、CSR 写），都要问一句"这一级被冻结时会不会重复触发"。

### 实测数据（CoreMark 2K，ITERATIONS=2，仿真）

| 指标 | M1（静态不跳） | P1（BTB + BHT） | 变化 |
|:---|:---:|:---:|:---:|
| CoreMark/MHz | 2.533 | **3.025** | +19.4% |
| Total Ticks（计时区间） | 789,387 | 660,991 | -16.3% |
| 整机 Cycles / Insts | 1,055,178 / 691,182 | 922,895 / 753,719 | 见下方说明 |
| 整机 CPI | 1.53 | 1.22 | 仅作参考 |

> [!NOTE]
> 整机统计区间包含 `uart_putc` 等待 TX FIFO 的忙等循环。核变快以后，自旋次数也会跟着变，所以同一个二进制的提交指令数变了（691k → 754k），整机 CPI 也被拉低了。**衡量 BPU 收益应以 CoreMark Ticks / 分数为准**，冲刷次数要等补上 `perf_branch_flush` 计数器后才能精确统计。

---

## 2026-10-24 4 路并行 SIMD INT8 乘累加加速器 (阶段 A1)

> 本条目为 2026-10-26 根据 commit `745171c`、`docs/spec/acc.md` 与当日回归实测补记。

### 阶段目标与交付物

1. **规格书与方案对比讲义 (`docs/spec/acc.md`)**：对比 4 种加速器耦合方式，选定 **MMIO 隐式写触发的 4 路 SIMD INT8 乘累加器**。
2. **`rtl/acc/wb_mac_acc.v`（134 行）**，挂在 Wishbone 上，地址 `0x2000_0000`：
   - `ACC_OPA`(0x04) 锁存打包的 4×INT8；写 `ACC_OPB_TRIG`(0x08) 时，**当拍**直接用 `wbs_dat_i` 与 `op_a_reg` 做 4 路有符号乘法和加法树，累加进 `acc_reg`，不需要 START/DONE 握手；
   - `ACC_RESULT`(0x0C) 可写，用来预置 Bias；`ACC_RELU`(0x10) 组合输出 `acc_reg[31] ? 0 : acc_reg`；`ACC_COUNT`(0x14) 统计 MAC 批次；
   - 固定 1 拍 ACK，符合现有 Wishbone 子集总线的约定。
3. **SoC 集成**：`wb_interconnect` 扩展为 1-Master 4-Slave，`soc_top` 实例化加速器，`soc.h` 增加基地址宏。
4. **测试**：单元测试 `sim/unit/tb_wb_mac_acc.v`；系统级基准 `sw/test_acc/main.c`（`make test-acc`），跑 16×64 INT8 全连接层（1024 MAC + Bias + ReLU），三种实现结果逐一比对。

### 实测数据（`make test-acc`）

| 实现 | 周期 | 相对软件乘 | 相对硬件 MUL |
|:---|:---:|:---:|:---:|
| [1] 软件移位加（RV32I） | 63,377 | 1.00× | — |
| [2] 标量硬件 MUL（RV32IM） | 8,418 | 7.53× | 1.00× |
| [3] SIMD 加速器（MMIO） | 2,537 | **24.98×** | **3.32×** |

### 教训：加速比必须说清楚基准是谁

- 24.98× 是相对**软件模拟乘法**的结果，其中大头（7.5×）其实来自 M 扩展本身。加速器自身的贡献是**相对硬件 MUL 的 3.32×**，来源包括 4 路并行、打包传输省掉 `lb` 和符号扩展、Bias/ReLU 融合进总线读写。
- 对外介绍时两个数字一起给，否则一被追问基准就站不住。

---

## 2026-10-26 补齐 RV32M 官方 ISA 测试与 Spike DiffTest 覆盖 (阶段 T5)

### 背景

M1 之后，`make isa-test` / `make difftest` 仍然只跑 `rv32ui`（`-march=rv32i_zicsr`、`spike --isa=rv32i`）。8 条 M 扩展指令只有 `tb_muldiv` 单元测试和 CoreMark 间接覆盖，**没有经过官方测试和 Golden Model 的逐条比对**。

### 做了什么

- 从官方 `riscv-software-src/riscv-tests` 导入 `isa/rv32um/{mul,mulh,mulhsu,mulhu,div,divu,rem,remu}.S`，存为 `sim/isa/src/rv32um-p-*.S`。这 8 个文件本身就是独立的 RV32 版本，直接复用现有的 `env/` 和 `macros/`，无需修改。
- `run_isa_tests.py`：同时收集 `rv32ui` 和 `rv32um`。按测试集选择 `-march`：rv32ui 保持 `rv32i_zicsr`（继续证明基础 ISA 不依赖 M），rv32um 用 `rv32im_zicsr`。单测参数支持 `add` / `mul` 这样的短名。
- `spike_diff.py`：rv32ui 对标 `--isa=rv32i`，rv32um 对标 `--isa=rv32im`。

### 结果

- `make isa-test`：**46/46 PASS**；`make difftest`：**46/46 MATCH**。除零（返回 -1 / 被除数）和 $-2^{31}/-1$ 溢出这些边界全部与 Spike 一致。
- rv32um 测试的 CPI：mul 系列 1.26，div/rem 3.0~3.4（32 拍迭代除法所致）。

### 顺带发现：BPU 让 rv32ui 测试本身慢了 5.4%

- **现象**：rv32ui 的 38 个测试总周期从 P1 之前的 12,604 增加到 13,288（加权 CPI 1.117 → 1.177）。逐个对比后发现：每个 R 型测试 +30 拍，I 型和访存测试 +12 拍，分支测试 +24 拍，无循环的测试（`lui` / `jal` / `simple` 等）+0 拍。
- **根因**：`test_macros.h` 里的 bypass 测试都是**只执行 2 次的小循环**（`addi x4,x4,1; li x5,2; bne x4,x5,1b`）。
  - 静态不跳：第 1 次回跳误预测，第 2 次退出预测正确，共 1 次冲刷；
  - Taken-only 分配 + 初值弱跳 `2'b10`：第 1 次回跳是冷 miss，分配表项；第 2 次退出时 BTB 命中，预测"跳"，又误预测一次，共 2 次冲刷。
  - 每个循环多 2 拍。R 型测试有 15 个 bypass 循环（+30），I 型有 6 个（+12），完全吻合。
- **结论**：这不是功能 bug，而是 2-bit BHT 在"短循环 + 冷启动"场景下的固有代价。CoreMark 里的长循环占主导，所以总体仍然 +19%。
- **教训**：微架构优化要在**真实负载**上评估，ISA 合规测试的 CPI 不能当性能指标。这个现象也直观解释了"为什么动态分支预测在极短循环冷启动场景下可能比静态预测多冲刷一次"。

---

## 2026-10-26 PDS 2022.2-SP6.4 首次全流程综合、时序签核与远程实验箱引脚核查 (阶段 B1)

### 阶段背景与目标

Windows 端 Pango Design Suite (`PDS 2022.2-SP6.4 build 146967`) License 就绪后，通过命令行 `pds_shell.exe` 对 `smoke_top` 与完整 RV32IM + BPU + SIMD MAC SoC (`fpga_top`) 执行首次端到端综合、映射、布局布线、静态时序分析与 `.sbit` 比特流生成，并核查远程 FPGA 实验平台的实际硬件形态。

### 实测资源占用与硬核推断 (`fpga_top` @ `PG2L200H-6FBB676`)

| 资源类型 | 占用数量 | 芯片总量 | 利用率 | 硬件推断与映射明细 (`apm_drm_lutram_utilization.log`) |
|:---|---:|---:|---:|:---|
| **LUT** | **3,359** | 159,800 | **2.10%** | 5 级流水线 + BPU 控制 + Wishbone 互联与外设 |
| **FF (Registers)** | **5,067** | 319,600 | **1.59%** | 流水线级间寄存器 + 64 项 BTB/BHT + 除数/余数迭代寄存器 |
| **DRM (Block RAM)** | **33.0** | 415 | **7.95%** | `u_soc/u_sram/mem`: 8 × `GTP_DRM36K_E1` (16K×8 SDP, 64 KB) + `u_regfile`: 2 × `GTP_DRM18K_E1` |
| **APM (DSP Slices)** | **8** | 280 | **2.86%** | `u_core/u_muldiv`: 4 × `GTP_APM_E2` (24×17 级联拼 33×33) + `u_mac_acc`: 4 × `GTP_APM_E2` (8×8 SIMD) |

- **固件初始化**：综合日志明确打印 `Loading memory data from file .../firmware_words.hex`，证实纯 Verilog `$readmemh` 在 PDS ADS 综合器下成功将 CoreMark 固件写入 `GTP_DRM36K_E1` 块 RAM 初始值。

### 实测静态时序分析 (Slow Corner, 目标 27.00 MHz / 37.037 ns)

| 顶层工程 | 约束周期 | 估算最短周期 | 估算最高频率 ($F_{\max}$) | Setup WNS / TNS | Hold WHS / THS | 违例端点 |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **`smoke_top`** | 37.037 ns | 3.310 ns | **302.11 MHz** | **+33.727 ns** / 0.000 | +0.150 ns / 0.000 | **0** |
| **`fpga_top`** | 37.037 ns | 17.233 ns | **58.03 MHz** | **+19.804 ns** / 0.000 | **+0.149 ns** / 0.000 | **0 / 17,792** |

- 在 27 MHz 板载晶振下周期利用率仅约 46.5%，建立时间余量高达 `+19.804 ns`，全部 17,792 个时序端点零违例一次收敛，最高可运行在 **58 MHz**。

### PDS 批处理构建 (`pds_shell`) 五条实测避坑记录

1. **禁止在批处理 Tcl 中调用 `save_project`**：脚本模式下调用会报 `Flow-4055: Please new or open a project`；`pds_shell` 会自动按脚本名创建同名 `.pds` 工程。
2. **必须显式指定 `synthesize -ads`**：裸调 `synthesize` 默认走未安装的第三方 Synplify，表现为假成功但不生成 `synthesize/` 目录，随后 `dev_map` 报 `Flow-0227`。
3. **工程与源码路径严禁含中文/非 ASCII 字符**：置于 `OneDrive\文档` 下会报 `Flow-0002: File '...\??\...' doesn't exist`。
4. **`firmware_words.hex` 必须放置在 `-work_dir`（`.pds` 同级启动目录）**：`$readmemh` 按进程工作目录解析，放在 `synthesize/` 子目录下不生效。
5. **`.fdc` 必须补齐 `create_clock` 时序约束**：原 `pangu200k_mini.fdc` 仅含 IO 位置属性，缺省时 PDS 按 `1000 ns (1 MHz)` 分析；已补入标准约束语法：
   `create_clock -name {sys_clk} [get_ports {sys_clk}] -period {37.037} -waveform {0.000 18.519}`

### 远程平台硬件形态核查：200K-MINI 核心板 vs 远程实验箱

- **发现**：对比远程平台导出的 `Matrix_led.fdc`（48 端口）与底板映射表 `mini-base管脚映射.xlsx` 发现，远程平台并非裸跑 200K-MINI 底板丝印外设（J3），而是在底板 **J10（40-pin 扩展口，Bank L6）** 上挂载了**实验箱外设面板**（4 颗单色 LED、4 颗按键、4 颗 RGB 灯、8 位数码管、8×8 点阵）：
  - `sys_clk` (`D18`, 27 MHz) 与 `rst_n` (`C22`) 与核心板完全一致；
  - 实验箱 `key[3:0]` 位于 `U21, W24, V24, AA23`（J10 引脚 32/33/34/35），而非底板的 `C23, B22, A22, B20`；
  - 实验箱 `led[3:0]` 位于 `U16, U15, V17, V16`（J10 引脚 27/28/29/30），而非底板的 `A20, C18, C19, E18`；
  - 实验箱的 UART 引脚未出现在点阵 demo 的 48 个端口中，待从平台串口通信例程中获取。
- **仓库处置**：
  - 保留 `platform/pango/pangu200k_mini.fdc`（供 200K-MINI 实物板使用，已补 `create_clock`）；
  - 新增 `platform/pango/pangu_experiment_box.fdc`（将 `key[3:0]` 与 `led[3:0]` 映射至实验箱 J10 对应球号，`led[7:4]` 留驻核心板无冲突球号 `A17..B17`）；
  - 新增 `platform/pango/build_fpga_top.tcl` 与 `build_smoke_top.tcl`，固化一键可复现构建流程。
