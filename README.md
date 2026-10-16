# Radiant Heisenberg: RV32I Processor & Parallel Accelerated SoC

[![Language: Verilog-2001](https://img.shields.io/badge/Language-Verilog--2001-blue.svg)](#)
[![ISA: RV32I](https://img.shields.io/badge/ISA-RV32I%20(Zicsr%20ready)-orange.svg)](#)
[![Lint: Verilator 0W](https://img.shields.io/badge/Verilator%20Lint-0%20Warnings-brightgreen.svg)](#)
[![ISA Tests: 38/38 PASS](https://img.shields.io/badge/ISA%20Tests-38%2F38%20PASS-brightgreen.svg)](#)
[![DiffTest: Spike 100%](https://img.shields.io/badge/DiffTest-Spike%20100%25%20Match-brightgreen.svg)](#)
[![CoreMark: 0.958/MHz](https://img.shields.io/badge/CoreMark%2FMHz-0.958%20(CPI%201.51)-brightgreen.svg)](#)
[![Target: Pango Logos-2](https://img.shields.io/badge/Target%20FPGA-Pango%20Logos--2%20PG2L200H-purple.svg)](#)

> **2026 全国大学生嵌入式芯片与系统设计竞赛 · 紫光同创企业赛道 · 选题一**  
> 目标硬件：远程 FPGA 平台 · 盘古 MES2L676-200HP 开发板（紫光同创 Logos-2 PG2L200H，板载双片 1 GB DDR3，摄像头与外设接口）

---

## 1. 项目简介与定位

**Radiant Heisenberg** 是一个面向嵌入式 AI 算子加速的 RISC-V 软硬件协同 SoC 系统，采用 **纯 Verilog-2001 从零构建（From Scratch）**。

### 核心设计原则
1. **纯净 RTL 实现与零厂商原语锁定**：
   - 核心 CPU（`rtl/core/`）与 SoC 互联/外设（`rtl/soc/`）完全由标准 Verilog-2001 实现，不引入任何 FPGA 厂商专有原语。
   - 所有片上存储结构（通用寄存器堆、双端口 SRAM、同步 FIFO）均采用标准行为可综合/可推断描述，天然支持多平台移植。
   - 严格执行零警告策略，在 Verilator `-Wall` 顶层静态 Lint 下保持 **0 Error, 0 Warning**。
2. **严苛的软硬件协同验证闭环**：
   - **指令集验证**：官方 `rv32ui` 全套 38 项基准测试 100% 自动化通过。
   - **差分比对 (DiffTest)**：与 RISC-V 官方 Spike Golden Model 实现逐周期/逐指令提交追踪比对（PC、目标寄存器 `rd`、写入数据 `wdata`），实现 38/38 项 100% 吻合（零 Mismatch）。
   - **裸机 C 运行时与基准评测**：自主构建零 OS 依赖的 Freestanding C Runtime（含 `crt0`、`link.ld`、无锁原子防撕裂 64 位 CLINT 定时器、8B FIFO 流控 UART0 及轻量级 `printf`），并在纯 RV32I 体系下完整运行 EEMBC CoreMark 2K Performance Run，测定硬件基线指标 **`0.958 CoreMark/MHz`**（CPI 1.51）。
3. **架构可扩展性与模块化档位**：
   - 针对分支预测器（BTB/BHT）、M 扩展乘除法器、指令/数据 Cache 与并行加速算子预留标准解耦总线接口与升级路径。

---

## 2. 当前开发进度与里程碑看板 (Roadmap & Status)

| 阶段 / 模块 | 核心内容与技术特性 | 验证指标 / 成果 | 状态 |
|:---|:---|:---|:---:|
| **阶段 0<br>(Core)** | • 经典 5 级静态流水线（IF / ID / EX / MEM / WB）<br>• 全通路数据前推网络（EX-EX, MEM-EX, 内部直通 RegFile）<br>• 完整冒险控制（Load-Use 1 拍停顿、SW→LW 结构冒险停顿、停顿前推锁存）<br>• BRAM 同步读时序适配（提前发出取指与 Load 读地址） | • Verilator `-Wall` 0 警告<br>• 38/38 项官方 `rv32ui` 测试 100% PASS<br>• Spike DiffTest 38/38 逐指令 100% MATCH<br>• 加权平均 CPI = **1.116** | ✅ 已完成 |
| **阶段 S1a & S1b<br>(Minimal SoC)** | • **Wishbone B4 固定 1 拍同步子集总线**（Classic 周期，解耦无等待）<br>• 1-Master 4-Slave 互联交叉译码器（支持未映射空间单拍虚拟 ACK）<br>• 64KB 双端口片上 SRAM（Port A 零等待直连取指，Port B 挂载 Wishbone 数据总线）<br>• SiFive FE310 兼容 UART0（含 8 字节收发双 FIFO 与流控）<br>• RISC-V 标准 64 位单调递增 CLINT 定时器（`mtime` / `mtimecmp`） | • 9/9 单元模块全部 PASS<br>• SoC 顶层软硬件集成自检 `test_soc.S` PASS<br>• `Cycles: 233, Insts: 128, CPI: 1.82` | ✅ 已完成 |
| **阶段 S1c<br>(C Runtime)** | • 零 OS 依赖的裸机 C 运行时环境（Freestanding Runtime）<br>• 链接脚本 `link.ld`（规范排布 64KB 物理空间与栈顶）<br>• 启动汇编 `crt0.S`（寄存器清零、BSS 清零、`SIM_CTRL` 上报）<br>• 驱动与库函数：`soc.h`, `uart.h/c` (轻量 `printf`), `timer.h/c` (64 位原子防撕裂读取), `str.h/c`<br>• GCC 软乘除法库 `libgcc`（`__mulsi3`, `__divsi3`, `__udivsi3`）链接支持 | • `make test-c` 综合验收测试 PASS<br>• 覆盖递归调用 (`fib(10)=55`)、软乘除法与长字符串打印<br>• `Cycles: 34314, Insts: 16438, CPI: 2.09` | ✅ 已完成 |
| **阶段 S1d<br>(CoreMark)** | • 导入业界标准 EEMBC CoreMark 权威算法套件<br>• 定制底层适配移植层 `core_portme.c/h`（静态内存分配，无浮点依赖）<br>• 运行 2K Performance Run 严苛校验集（`seedcrc=0xe9f5`）<br>• 定点化计算与标准分值输出 | • `Correct operation validated.` 校验通过<br>• 特征 CRC 匹配（`crcfinal=0x72be`）<br>• **基线得分：`0.958 CoreMark/MHz`**<br>• 硬件实时 Profiling：CPI = **1.51** | ✅ 已完成 |
| **Checkpoint 1<br>(Board Bring-up)** | • 紫光同创 Pango Design Suite (PDS) 工程建立<br>• 板级顶层封装、时钟 PLL (50MHz) 与引脚约束 (`.fdc`)<br>• 远程开发板 MES2L676 烧录与物理串口通信验证 | • 综合实现无时序违例<br>• 物理 UART 打印 CoreMark 分数看板 | 🔜 进行中 |
| **阶段 S2<br>(Privilege & IRQ)** | • RISC-V 机器模式 CSR 寄存器组（`mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mip` 等）<br>• 精确异常与中断响应/恢复状态机（`ecall`, `ebreak`, `mret`）<br>• CLINT 定时器中断接入 | • 官方特权级指令集回归测试<br>• 定时器周期中断抢占验证 | 📅 规划中 |
| **阶段 S3<br>(Perf Upgrades)** | • 硬件 M 扩展多周期/流水化乘除法器（替换软乘除库）<br>• IF 级 BTB + 2-bit 饱和计数器 BHT 动态分支预测器<br>• 指令 Cache 与数据 Cache（Wishbone Pipelined 协议升级）<br>• DDR3 外部大容量存储器接入（1 GB） | • CoreMark 分数预期提升至 **1.8+ CoreMark/MHz**<br>• 运行大型应用程序与神经网络权重存储 | 📅 规划中 |
| **阶段 S4<br>(Accelerator)** | • 硬件并行矩阵/卷积张量算子加速器（Dedicated Coprocessor / DMA）<br>• PyTorch 算法定点量化、权重导出与算子调度驱动<br>• 摄像头图像实时采集与前向推理演示 | • 竞赛选题端到端系统功能演示与性能评估 | 📅 规划中 |

---

## 3. 系统架构与存储器映射 (Architecture & Memory Map)

### 3.1 总体架构拓扑

```
                            ┌──────────────────────────────────────────────┐
                            │                 core.v                       │
                            │      5-Stage Pipelined RV32I Processor       │
                            │                                              │
                            │      imem_*                      dmem_*      │
                            └────────┬───────────────────────────┬─────────┘
                                     │ (Fetch 直连)              │ (Memory 访问)
                               ┌─────▼──────┐              ┌─────▼──────┐
                               │   SRAM     │              │  WB Master │
                               │  Port A    │              │   Bridge   │
                               │ (零等待取指)│              └─────┬──────┘
                               └─────┬──────┘                     │ Wishbone B4
                                     │                     ┌──────▼──────────────────────────┐
                                     │                     │       wb_interconnect           │
                               ┌─────▼──────┐              │     (1-Master 4-Slave)          │
                               │  双端口    │◄────────────►├────────────┬───────────┬────────┤
                               │  片上 SRAM │  (Port B)    │   SRAM     │   UART0   │ CLINT  │
                               │  (64 KB)   │  (数据总线)  │  (64 KB)   │  (8B FIFO)│ (Timer)│
                               └────────────┘              └────────────┴─────┬─────┴───┬────┘
                                                                              │         │
                                                                           uart_txd  timer_irq
                                                                           uart_rxd
```

### 3.2 存储器映射表 (Memory Map)

系统遵循 SiFive FE310 与标准 RISC-V 特权级规范地址布局：

| 起始地址 | 结束地址 | 物理空间大小 | 挂载设备 / 模块 | 访问属性 | 详细说明 |
|:---|:---|:---:|:---|:---:|:---|
| `0x0000_0000` | `0x0000_FFFF` | 64 KB | **片上双端口 SRAM** | R / W / X | 存放指令代码与数据（Code + Data），CPU 复位向量为 `0x0000_0000` |
| `0x0200_0000` | `0x0200_FFFF` | 64 KB 区域 | **CLINT (Core-Local Interruptor)** | R / W | RISC-V 标准 64 位单调递增时钟 `mtime` (`0xBFF8`) 与 `mtimecmp` (`0x4000`) |
| `0x1001_0000` | `0x1001_001F` | 32 B | **UART0 串口控制器** | R / W | SiFive FE310 寄存器布局，含 8 字节收发 FIFO 与硬件流控轮询标志 |
| `0x8000_0000` | `0xBFFF_FFFF` | 1 GB | **外部 DDR3 (预留)** | R / W | 阶段 S3 扩展接入外部板载 DDR3 存储器 |
| `0xFFFF_FFF0` | `0xFFFF_FFFF` | 16 B | **SIM_CTRL (仿真专用信箱)** | W | 独立于 SRAM 物理空间的仿真退出信箱（未映射区域由总线返回单拍虚拟 ACK） |

---

## 4. 目录结构说明

```
.
├── rtl/                        # 纯 Verilog-2001 硬件源代码（禁止厂商专有原语）
│   ├── core/                   # 5 级流水线 CPU 核心
│   │   ├── core.v              # 流水线顶层集成（IF/ID/EX/MEM/WB 级间寄存器与控制）
│   │   ├── alu.v               # 算术逻辑单元（37 条基础指令运算）
│   │   ├── regfile.v           # 32x32b 整数寄存器堆（Write-First 内部直通）
│   │   ├── decoder.v           # 指令译码器（操作码、立即数格式、流水线控制掩码）
│   │   ├── imm_gen.v           # 符号扩展立即数生成器（I/S/B/U/J）
│   │   ├── forwarding_unit.v   # 全通路数据前推单元（EX-EX, MEM-EX）
│   │   ├── hazard_unit.v       # 冒险控制单元（Load-Use 停顿、SW-LW 结构冒险停顿）
│   │   └── alu_ops.vh          # ALU 操作码宏定义头文件
│   └── soc/                    # SoC 互联与片上外设
│       ├── soc_top.v           # SoC 顶层包装（集成 core、总线、SRAM、UART、CLINT）
│       ├── wb_core_bridge.v    # CPU 原生 dmem 访存端口到 Wishbone Master 适配桥
│       ├── wb_interconnect.v   # Wishbone B4 地址译码与数据多路选择互联器
│       ├── wb_sram.v           # 64KB 双端口片上存储器（Port A 取指直连，Port B 挂载总线）
│       ├── wb_uart.v           # 兼容 SiFive FE310 寄存器的 UART 从设备（含双 8B FIFO）
│       ├── wb_clint.v          # RISC-V 标准 64 位 CLINT 定时器
│       ├── uart_tx.v           # UART 串行发送 PHY 模块
│       └── uart_rx.v           # UART 串行接收 PHY 模块
├── platform/                   # 板级封装与约束
│   └── pango/                  # 紫光同创盘古 MES2L676 (Logos-2 PG2L200H) 约束与顶层
│       └── smoke_top.v         # 物理开发板回环冒烟测试顶层
├── sim/                        # 仿真与验证基础设施
│   ├── unit/                   # 针对各个独立硬件子模块的定向单元测试台
│   ├── core/                   # CPU 流水线集成自检与微架构冒险定向测试台
│   ├── isa/                    # RISC-V 官方 rv32ui 指令集移植环境与驱动脚本
│   ├── difftest/               # Spike 模拟器逐指令提交差分验证脚本与对比环境
│   └── soc/                    # SoC 系统级软硬件集成测试台与测试汇编固件
├── sw/                         # 软件与固件栈
│   ├── common/                 # 裸机 Freestanding C 语言基础运行时库
│   │   ├── crt0.S              # 系统启动汇编（通用寄存器与 BSS 段初始化）
│   │   ├── link.ld             # 64KB SRAM 内存布局链接脚本
│   │   ├── soc.h               # SoC 外设基地址与寄存器定义
│   │   ├── uart.h / uart.c     # 串口轮询驱动与轻量级 printf / ee_printf
│   │   ├── timer.h / timer.c   # 64 位防撕裂 CLINT 定时器读取与延时函数
│   │   └── str.h / str.c       # 标准内存与字符串操作函数 (memcpy, memset 等)
│   ├── test_c/                 # 阶段 S1c 裸机 C 综合验收程序
│   └── coremark/               # 阶段 S1d EEMBC CoreMark 权威性能基准测试移植
├── docs/                       # 项目工程与设计文档
│   ├── spec/
│   │   ├── core.md             # CPU 处理器核心微架构规格说明书
│   │   ├── soc.md              # SoC 总线与外设架构规格说明书
│   │   └── review_summary.md   # 核心微架构与总线设计评审总结
│   ├── journal.md              # 开发日志与详细 Bug 记录（含现象/定位/根因/修复/教训）
│   └── interview_qa.md         # 面试技术深度 Q&A 题库
├── tools/                      # 本地交叉编译工具链（xPack GCC 15.2 等，不入版本库）
├── Makefile                    # 全工程一键式构建与自动化测试入口
└── AGENTS.md                   # AI 协作开发准则与亲手档位规范
```

- 核心微架构规格请查阅：[`docs/spec/core.md`](docs/spec/core.md)
- SoC 总线与外设规格请查阅：[`docs/spec/soc.md`](docs/spec/soc.md)
- 详细开发演进与 Bug 排查记录请查阅：[`docs/journal.md`](docs/journal.md)

---

## 5. 快速开始与自动化验证 (Quick Start)

### 5.1 环境与工具链说明

本工程开发环境建立在 macOS (仿真验证) 与 Windows (PDS 综合)，所有功能验证均支持在 macOS/Linux 环境下秒级完成自动化回归：

- **RISC-V 交叉编译器**：`xPack riscv-none-elf-gcc 15.2.0`（`-march=rv32i_zicsr -mabi=ilp32`）
  > *注：竞赛官方说明中提及 `riscv32-unknown-elf-gcc`。两者为完全同源的 GCC 工具链，仅 target 三元组前缀差异，生成的 RV32I 机器码严格等价。*
- **Verilog 仿真工具**：`Icarus Verilog` (v12.0+)、`Verilator` (v5.052+)
- **Golden Model 模拟器**：`Spike` (支持 `--isa=rv32i`)
- **自动化测试驱动**：`Python 3`

### 5.2 一键式验证命令与当前实测状态

项目根目录下提供了高度集成的 `Makefile`，所有测试命令均集成了自动化断言与状态核验：

| 验证目标命令 | 验证层级 / 测试对象 | 覆盖范围与说明 | 当前实测结果 | 典型耗时 |
|:---|:---|:---|:---:|:---:|
| `make lint` | 静态代码分析 | 覆盖 `smoke_top`、`core`、`soc_top` 顶层与全部子模块 | ✅ **0 Error, 0 Warning** | ~0.1s |
| `make unit-test` | 模块级单元测试 | 9 项独立测试（ALU, RegFile, ImmGen, Decoder, Forwarding, Hazard, Interconnect, UART, CLINT） | ✅ **9/9 ALL PASSED** | ~1.5s |
| `make test-core` | 处理器核心自检 | 5 级流水线基础运算 + SW-LW 结构冒险 + EX 停顿前推锁存 | ✅ **3/3 ALL PASSED** | ~0.5s |
| `make test-soc` | SoC 软硬件集成 | 汇编固件经总线读写 SRAM、UART 字符回显、CLINT 轮询与信箱上报 | ✅ **PASSED**<br>(Cycles: 233, CPI: 1.82) | ~0.2s |
| `make test-c` | 裸机 C 运行时验收 | 栈空间、递归 (`fib(10)=55`)、`libgcc` 软乘除法、防撕裂 Timer、长字符串 `printf` | ✅ **PASSED**<br>(Cycles: 34314, CPI: 2.09) | ~1.0s |
| `make isa-test` | 官方指令集回归 | RV32UI 官方测试集 38 项严苛用例自动化回归 | ✅ **38/38 100% PASSED**<br>(加权 CPI = **1.116**) | ~2.8s |
| `make difftest` | Spike 差分比对 | 与 Spike 逐条比对 PC、目标寄存器索引、写回数值 | ✅ **38/38 100% MATCH**<br>(0 Mismatch) | ~4.5s |
| `make coremark` | 权威性能基准评测 | 完整运行 EEMBC CoreMark 2K Performance Run | ✅ **Correct operation validated**<br>**`0.958 CoreMark/MHz`** (CPI 1.51) | ~18s |

#### 常用一键全量回归命令：
```bash
# 1. 静态检查（Verilator -Wall 零警告）
make lint

# 2. 模块与核心级自检
make unit-test
make test-core

# 3. 官方 ISA 与 Spike DiffTest 严苛验证
make isa-test
make difftest

# 4. SoC 系统级软硬件协同与 CoreMark 基准跑分
make test-soc
make test-c
make coremark
```

---

## 6. 核心工程设计与关键 Bug 沉淀 (Engineering Journal)

本项目始终坚持“**设计决策归作者，每一行代码可解释**”的工程标准。在芯片软硬件微架构迭代过程中沉淀了多起高价值边界 Bug 的定位与修复记录，完整技术复盘请查阅 [`docs/journal.md`](docs/journal.md)：

- **[BUG-001] 串口冒烟测试快速输入丢字与 FIFO 缓冲解耦**：突发吞吐速率失配定位，在物理 PHY 间引入同步 FIFO；
- **[BUG-002] SW 紧跟 LW 时写内存地址被覆盖与测试环境掩盖设计缺陷**：发现由于提前在 EX 级发出读地址而导致的单内存总线结构冒险，严正确立“测试环境绝不能迁就或掩盖硬件缺陷”原则，重构硬件停顿控制；
- **[BUG-003] EX 级停顿期间前推操作数丢失与前推源退休逃逸**：揭示了经典流水线中纯组合前推网络在遇到本级冻结而后级流动时的数据撕裂问题，推导并实现了流水线停顿的前推值同步锁存机制；
- **[BUG-004] UART 波特率计数器位宽截断导致的除二采样失真**：定位了 Verilog 参数宏在整型运算前执行按位截断导致的边界失效；
- **[BUG-005] UART 控制器连续 Store 写入丢包与 FIFO 读指针时序竞争**：修复了 Wishbone Classic 总线在处理背靠背连续写请求时误用上一拍 ACK 门控造成的写丢弃问题；
- **[BUG-006] 仿真 Mailbox 串口排空延时污染性能计数器与信箱地址冲突隐患**：彻底解耦了 Profiling 统计区间与串口排空仿真延时，并将 Mailbox 迁移至保留高地址空间 `0xFFFF_FFF0`，规避与 C 程序物理空间的段重叠。
