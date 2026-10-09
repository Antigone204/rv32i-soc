# AGENTS.md — AI 协作规则

本文件给参与本项目的 AI agent 阅读。开始任何任务前先读完本文件。

## 1. 项目定位

- 项目：**RISC-V 并行加速系统**（全国大学生嵌入式芯片与系统设计竞赛 2026 · 紫光同创赛道 · 选题一）
- 目的：**面试简历项目 + 个人训练**。比赛提交节点是 2026-11-04 18:00，不追求名次。
- 作者单人开发，原则是尽量使用 AI，但**设计决策归作者**，作者必须能讲清楚每一行代码。
- 硬件平台：远程 FPGA 平台上的盘古 MES2L676-200HP（紫光同创 Logos-2 PG2L200H），板载 2 片 DDR3（共 1 GB，32 位）和摄像头。
- 综合工具：Pango Design Suite（PDS），在作者的 Windows 主机上运行。Mac 上只做仿真。

## 2. 亲手档位（最重要）

| 档位 | AI 可以做什么 | 当前适用模块 |
|---|---|---|
| **A 手写** | **不得编写实现代码**。只能讨论方案、写 spec 草稿、写测试/testbench、review 作者的代码、出题 | 分支预测器（BTB/BHT）、加速器核心数据通路、乘除法单元（M 扩展）、Cache |
| **B 共写** | 作者先写骨架或关键逻辑，AI 再补全；AI 不得替换作者写的关键逻辑 | CSR / 异常 trap 流程 |
| **C AI 写 + 作者精读** | AI 实现；完成后必须提供逐段讲解和 3–5 道小测题 | 流水线骨架、前推/冒险单元、译码器、ALU、外设、总线 |
| **D 全交给 AI** | 自由实现 | 构建脚本、trace 对比、CoreMark 移植、画图脚本、文档初稿 |

如果某任务属于 A 档，但作者要求 AI 直接实现，**先提醒一次档位约定**，作者坚持就照做，并在 journal 中注明。

## 3. 目录结构

```
rtl/core/        CPU 核（纯 RTL，禁止使用厂商原语）
rtl/soc/         总线、外设、SoC 顶层（纯 RTL）
rtl/acc/         加速器（纯 RTL）
platform/pango/  板级顶层、PLL/BRAM/ILA 封装、约束（.fdc）、PDS 工程说明
sim/             Verilator testbench、difftest、脚本
sw/              bootloader、CoreMark、测试程序、加速器 benchmark
model/           PyTorch 模型训练、量化、权重导出
docs/spec/       各模块 spec（先写 spec 再写 RTL）
docs/journal.md  开发日志 / bug 记录（面试素材）
tools/           本地工具链（不提交 git）
```

## 4. RTL 编码规范

- 语言：**Verilog-2001**，可以使用少量 PDS 和 Verilator 都支持的 SystemVerilog 语法（如 `logic`），不确定时用纯 Verilog。
- 每个文件开头写 `` `default_nettype none ``，文件末尾写 `` `default_nettype wire ``。
- 一个文件一个模块，文件名 = 模块名。
- 时钟 `clk`；复位 `rst_n`，**低有效、同步复位**。
- 时序逻辑用 `always @(posedge clk)` 和非阻塞赋值；组合逻辑用 `always @(*)` 和阻塞赋值，并给所有输出赋默认值，避免锁存器。
- 信号命名带上流水级前缀：`if_`、`id_`、`ex_`、`mem_`、`wb_`；流水线寄存器写成 `id_ex_xxx` 的形式。
- 存储器在 `rtl/` 里用可推断的写法（`reg [31:0] mem [0:N-1]`）；厂商 IP 只能出现在 `platform/pango/`。
- 每个模块头部注释说明：功能、接口、时序假设、所在流水级。
- `make lint` 必须**零警告**；确实需要豁免的，用 `/* verilator lint_off XXX */` 并写明理由。

## 5. 验证要求（完成的定义）

一个 RTL 改动只有满足以下条件才能算"完成"：
1. `make lint` 通过；
2. `make isa-test` 全部 PASS（核相关改动）；
3. 相关的 difftest / 单元测试通过；
4. 涉及性能的改动要附上前后对比数据（cycle、CPI 或 CoreMark）。

**禁止**在没有运行测试的情况下声称"应该可以工作"。

## 6. 工具链

- RISC-V GCC：`tools/xpack-riscv-none-elf-gcc-*/bin/riscv-none-elf-gcc`（xPack 15.2），使用 `-march=rv32i_zicsr -mabi=ilp32`。
  - 比赛要求写的是 `riscv32-unknown-elf-gcc`。两者是同一套 GCC，只是 target 三元组名字不同，生成的 RV32I 代码等价；文档中需要注明这一点。
- 仿真：Verilator（主力）、Icarus Verilog（快速小测试）。
- Golden model：Spike（`spike --isa=rv32i`）。

## 7. 日志与提交

- 每解决一个非平凡 bug，就在 `docs/journal.md` 追加一条：现象 → 定位过程 → 根因 → 修复 → 教训。
- 小步提交，commit message 使用中文或英文均可，格式为 `<模块>: <做了什么>`。
- 不要提交 `tools/`、`build/` 和波形文件。
