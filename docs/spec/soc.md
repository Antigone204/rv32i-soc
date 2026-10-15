# SoC 总线与外设规格说明书 (SoC Spec)

> **档位**：Tier C (AI 写 + 作者精读)
> **前置依赖**：[core.md](./core.md) 中定义的 CPU 核心 imem/dmem 接口
> **规则**：先 Spec 后 RTL。本文档定义完成并评审后才可开始编写 RTL。

---

## 1. 概述与设计目标

将已验证的 RV32I 流水线核 (`core.v`) 集成为一个可运行裸机 C 程序（CoreMark）的最小 SoC。

**S1 阶段目标**：
- 定义并实现 **Wishbone B4 Classic Cycle** 数据总线；
- 通过地址译码将 CPU 数据端口扇出到多个外设从设备；
- 提供足够的 SRAM、UART 输出与硬件计时器，支撑 CoreMark 移植；
- 为后续 CSR/中断 (S2)、Cache/DDR3 (S3) 预留扩展接口。

**设计约束**：
- 所有从设备响应延迟为 **1 个时钟周期**（与 BRAM 同步读一致），S1 阶段不引入流水线停顿扩展；
- 纯 RTL，不使用厂商原语（`rtl/soc/` 目录）；
- 指令总线 **不经过 Wishbone**，直连 SRAM Port A（零等待状态取指）。

---

## 2. 系统架构

```
                        ┌──────────────────────────────────┐
                        │            core.v                │
                        │                                  │
                        │   imem_*              dmem_*     │
                        └──────┬──────────────────┬────────┘
                               │                  │
                          ┌────▼─────┐      ┌─────▼──────┐
                          │  SRAM    │      │  WB Master  │
                          │  Port A  │      │  Bridge     │
                          │ (I-Fetch │      │             │
                          │  直连)   │      └─────┬──────┘
                          └────┬─────┘            │ Wishbone B4
                               │            ┌─────▼──────────────────┐
                               │            │   wb_interconnect      │
                          ┌────▼─────┐      │   (地址译码 + MUX)     │
                          │          │      ├──────┬──────┬──────────┤
                          │  双端口   │◄────►│ SRAM │ UART │  CLINT   │
                          │  SRAM    │      │Port B│      │ (Timer)  │
                          │ (64 KB)  │      └──────┘──────┘──────────┘
                          └──────────┘
                                            ┌──────┐    ┌──────────┐
                                            │UART  │    │ 心跳 LED │
                                            │TX/RX │    │          │
                                            │ Pin  │    │          │
                                            └──────┘    └──────────┘
```

**关键决策**：
1. **指令端口直连**：`imem_addr/imem_rdata` 不走 Wishbone，直连 SRAM Port A（BRAM 读端口），保证取指零等待状态、无总线仲裁开销。
2. **数据端口走 Wishbone**：`dmem_*` 经桥接转换为 Wishbone Master 信号，通过互连模块访问 SRAM Port B、UART 和 CLINT。
3. **统一物理存储**：指令和数据共享同一块 64KB 双端口 BRAM，Port A 供取指（只读），Port B 供数据访问（读写）。支持通过数据总线加载程序到指令存储区域（UART bootloader 可行）。

---

## 3. Wishbone B4 总线协议要点

> 本节摘取 [Wishbone B4 Specification](https://cdn.opencores.org/downloads/wbspec_b4.pdf) 的核心要义，供系统学习参考。

### 3.1 信号定义

Wishbone 采用 **主-从 (Master-Slave)** 模型。信号以 `_o`（输出）和 `_i`（输入）为后缀，方向相对于信号所在模块。

| 信号 | 宽度 | 方向 (Master) | 描述 |
|:-----|:-----|:-------------|:-----|
| `cyc_o` | 1 | → Slave | **总线周期有效**。持续为高表示一个完整的总线事务正在进行 |
| `stb_o` | 1 | → Slave | **选通/请求**。表示当前地址和控制信号有效，请求一次传输 |
| `we_o`  | 1 | → Slave | **写使能**。1 = 写操作，0 = 读操作 |
| `adr_o` | 32 | → Slave | **字节地址** |
| `dat_o` | 32 | → Slave | **写数据**（Master → Slave） |
| `sel_o` | 4 | → Slave | **字节选择**。每一位对应数据总线的一个字节通道，1 = 该字节参与传输 |
| `dat_i` | 32 | ← Slave | **读数据**（Slave → Master） |
| `ack_i` | 1 | ← Slave | **应答**。Slave 在完成传输后拉高 1 拍，通知 Master 数据已就绪（读）或写入已完成（写） |
| `err_i` | 1 | ← Slave | **错误**。访问了无效地址或非法操作（S1 阶段未使用，由互连默认处理） |

### 3.2 Classic Single Cycle 时序

**单次读操作** (1 Wait State，匹配 BRAM 时序)：

```
Clock :  __|‾‾|__|‾‾|__|‾‾|__|‾‾|
          T0     T1     T2     T3

cyc_o :  ____/‾‾‾‾‾‾‾‾‾\________
stb_o :  ____/‾‾‾‾‾‾‾‾‾\________
we_o  :  ____________________________   (= 0, 读操作)
adr_o :  ----< ADDR >-----------
sel_o :  ----< 1111 >-----------
dat_i :  ____________< DATA >-------
ack_i :  ________/‾‾‾‾\_____________

         T1: Master 发出地址      T2: Slave 返回数据 + ACK
```

- T1 上升沿：Master 断言 `cyc`、`stb`、`adr`、`sel`。Slave 收到地址，启动 BRAM 读取。
- T2 上升沿：Slave 将 BRAM 读出数据放上 `dat_o`（Slave 端），同时断言 `ack`。Master 采样数据。
- T2 之后：Master 撤销 `cyc`/`stb`，总线空闲。

**单次写操作** (1 Wait State)：

```
Clock :  __|‾‾|__|‾‾|__|‾‾|__|‾‾|
          T0     T1     T2     T3

cyc_o :  ____/‾‾‾‾‾‾‾‾‾\________
stb_o :  ____/‾‾‾‾‾‾‾‾‾\________
we_o  :  ____/‾‾‾‾‾‾‾‾‾\________   (= 1, 写操作)
adr_o :  ----< ADDR >-----------
sel_o :  ----< SEL  >-----------     (字节使能，如 4'b0001 = SB)
dat_o :  ----< DATA >-----------
ack_i :  ________/‾‾‾‾\_____________

         T1: Master 发出地址+数据   T2: Slave 确认写入完成
```

### 3.3 握手规则

1. Master **必须先断言 `cyc`**，然后才能断言 `stb`（本设计中 `cyc` 和 `stb` 同时断言）；
2. Master 在看到 `ack` 之前 **不得撤销 `stb`**（保持请求直到被应答）；
3. Slave 在看到 `cyc & stb` 之前 **不得断言 `ack`**；
4. `ack` 必须是 **单周期脉冲**——应答后立即撤销，避免 Master 误认为是连续两次传输。

---

## 4. 存储器映射 (Memory Map)

参照 SiFive FE310 / RISC-V 平台规范的地址布局惯例：

| 起始地址 | 结束地址 | 大小 | 设备 | 说明 |
|:---------|:---------|:-----|:-----|:-----|
| `0x0000_0000` | `0x0000_FFFF` | 64 KB | **On-chip SRAM** | Code + Data，双端口 BRAM。CPU 复位向量 `0x0000_0000` |
| `0x0200_0000` | `0x0200_FFFF` | 64 KB 区域 | **CLINT** | `mtime` / `mtimecmp`（RISC-V 标准地址） |
| `0x1001_0000` | `0x1001_001F` | 32 B | **UART0** | TX/RX 数据与控制寄存器 |
| `0x8000_0000` | `0xBFFF_FFFF` | 1 GB | **DDR3**（未来） | 外部 DDR3 存储器，S3 阶段接入 |

### 4.1 地址译码规则

使用地址高位进行粗粒度译码：

```verilog
wire sel_sram  = (adr[31:16] == 16'h0000);   // 0x0000_xxxx
wire sel_clint = (adr[31:16] == 16'h0200);   // 0x0200_xxxx
wire sel_uart  = (adr[31:16] == 16'h1001);   // 0x1001_xxxx
wire sel_none  = ~(sel_sram | sel_clint | sel_uart);  // 未映射区域
```

**未映射地址处理**：互连模块对未映射地址返回 `ack = 1`，`dat = 32'h0000_0000`（静默忽略，不挂起总线）。

### 4.2 地址布局设计理由

| 选择 | 理由 |
|:-----|:-----|
| SRAM 从 `0x0` 开始 | CPU 复位向量为 `0x0`，简化启动流程；与现有 ISA 测试完全兼容 |
| CLINT 在 `0x0200_0000` | RISC-V 特权级规范硬性约定的标准地址；多数 RISC-V 工具链默认此地址 |
| UART 在 `0x1001_0000` | SiFive FE310 UART0 地址惯例；留出 `0x1001_1000` 等地址给未来外设 |
| DDR3 在 `0x8000_0000` | RISC-V 规范标准 DRAM 起始地址；Spike 默认 DRAM 基址也是此值 |

---

## 5. 模块设计

### 5.1 Core-to-Wishbone 主机桥 (`wb_core_bridge.v`)

将 CPU 核心的原生 `dmem_*` 接口转换为 Wishbone B4 Master 信号。

**端口定义**：

```verilog
module wb_core_bridge (
    input  wire        clk,
    input  wire        rst_n,

    // ---- CPU 侧 (来自 core.v dmem 端口) ----
    input  wire [31:0] dmem_addr,
    input  wire [31:0] dmem_wdata,
    input  wire [3:0]  dmem_byte_we,     // 非零 = 写操作
    input  wire        dmem_req,
    output wire [31:0] dmem_rdata,

    // ---- Wishbone Master 侧 ----
    output wire        wbm_cyc_o,
    output wire        wbm_stb_o,
    output wire        wbm_we_o,
    output wire [31:0] wbm_adr_o,
    output wire [31:0] wbm_dat_o,
    output wire [3:0]  wbm_sel_o,
    input  wire [31:0] wbm_dat_i,
    input  wire        wbm_ack_i
);
```

**信号映射** (S1 阶段为纯组合直通)：

| CPU 信号 | Wishbone Master 信号 | 映射逻辑 |
|:---------|:--------------------|:---------|
| `dmem_req` | `wbm_cyc_o`, `wbm_stb_o` | `cyc = stb = dmem_req` |
| `dmem_addr` | `wbm_adr_o` | 直通 |
| `dmem_wdata` | `wbm_dat_o` | 直通 |
| `dmem_byte_we` | `wbm_sel_o` | 写时 = `dmem_byte_we`；读时 = `4'b1111` |
| `|dmem_byte_we|` | `wbm_we_o` | `we = \|dmem_byte_we\|`（任意字节写使能 → 写操作） |
| `wbm_dat_i` | `dmem_rdata` | 直通 |

> **S1 简化**：桥不检查 `wbm_ack_i`，不生成流水线停顿。所有从设备保证 1 周期响应，时序与直连 BRAM 等价。
>
> **S3 升级路径**：增加 `dmem_stall` 输出至 `hazard_unit`，当 `wbm_ack_i` 未及时返回时冻结流水线（Cache Miss、DDR3 延迟等场景）。

---

### 5.2 Wishbone 互连 (`wb_interconnect.v`)

**功能**：共享总线拓扑。单 Master → 多 Slave 的地址译码 + 读数据多路选择。

```verilog
module wb_interconnect (
    // ---- Wishbone Master 端口 (来自 wb_core_bridge) ----
    input  wire        wbm_cyc_i,
    input  wire        wbm_stb_i,
    input  wire        wbm_we_i,
    input  wire [31:0] wbm_adr_i,
    input  wire [31:0] wbm_dat_i,
    input  wire [3:0]  wbm_sel_i,
    output reg  [31:0] wbm_dat_o,
    output reg         wbm_ack_o,

    // ---- Slave 0: SRAM ----
    output wire        wbs0_cyc_o,
    output wire        wbs0_stb_o,
    // ... (we, adr, dat, sel 直通)
    input  wire [31:0] wbs0_dat_i,
    input  wire        wbs0_ack_i,

    // ---- Slave 1: UART ----
    output wire        wbs1_cyc_o,
    output wire        wbs1_stb_o,
    input  wire [31:0] wbs1_dat_i,
    input  wire        wbs1_ack_i,

    // ---- Slave 2: CLINT ----
    output wire        wbs2_cyc_o,
    output wire        wbs2_stb_o,
    input  wire [31:0] wbs2_dat_i,
    input  wire        wbs2_ack_i
);
```

**核心逻辑**：

```verilog
// 地址译码（组合逻辑）
wire sel_sram  = (wbm_adr_i[31:16] == 16'h0000);
wire sel_clint = (wbm_adr_i[31:16] == 16'h0200);
wire sel_uart  = (wbm_adr_i[31:16] == 16'h1001);

// 将 stb 路由到被选中的从设备
assign wbs0_stb_o = wbm_stb_i & sel_sram;
assign wbs1_stb_o = wbm_stb_i & sel_uart;
assign wbs2_stb_o = wbm_stb_i & sel_clint;

// cyc 广播给所有从设备（或仅给被选中的）
assign wbs0_cyc_o = wbm_cyc_i & sel_sram;
assign wbs1_cyc_o = wbm_cyc_i & sel_uart;
assign wbs2_cyc_o = wbm_cyc_i & sel_clint;

// we, adr, dat, sel 直通（广播，从设备仅在 stb 有效时响应）
// 省略：wbsX_we_o = wbm_we_i; wbsX_adr_o = wbm_adr_i; ...

// 读数据多路选择（组合逻辑）
always @(*) begin
    if (sel_sram)       wbm_dat_o = wbs0_dat_i;
    else if (sel_uart)  wbm_dat_o = wbs1_dat_i;
    else if (sel_clint) wbm_dat_o = wbs2_dat_i;
    else                wbm_dat_o = 32'h0000_0000;  // 未映射
end

// ACK 多路选择
always @(*) begin
    if (sel_sram)       wbm_ack_o = wbs0_ack_i;
    else if (sel_uart)  wbm_ack_o = wbs1_ack_i;
    else if (sel_clint) wbm_ack_o = wbs2_ack_i;
    else                wbm_ack_o = wbm_stb_i;  // 未映射：立即 ACK 防挂起
end
```

---

### 5.3 片上 SRAM (`wb_sram.v`)

**双端口同步 SRAM**：

- **Port A**：指令取指专用端口（不在 Wishbone 上，直连 core 的 `imem_*`），只读，1 周期延迟。
- **Port B**：数据访问端口（Wishbone Slave），支持字节写使能，1 周期延迟。

```verilog
module wb_sram #(
    parameter integer WORDS = 16384     // 16K × 32bit = 64 KB
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Port A: 指令取指 (直连 core.imem_*) ----
    input  wire [31:0] imem_addr,       // 字节地址
    output reg  [31:0] imem_rdata,      // 1 拍后返回

    // ---- Port B: Wishbone Slave (数据访问) ----
    input  wire        wbs_cyc_i,
    input  wire        wbs_stb_i,
    input  wire        wbs_we_i,
    input  wire [31:0] wbs_adr_i,       // 字节地址
    input  wire [31:0] wbs_dat_i,
    input  wire [3:0]  wbs_sel_i,
    output reg  [31:0] wbs_dat_o,
    output reg         wbs_ack_o
);
```

**BRAM 推断写法** (Verilog-2001，可被 PDS / Vivado 推断为 True Dual-Port BRAM)：

```verilog
reg [31:0] mem [0:WORDS-1];

localparam AW = $clog2(WORDS);   // 字地址宽度 = 14

// Port A: 指令读 (同步 1 拍延迟)
always @(posedge clk) begin
    imem_rdata <= mem[imem_addr[AW+1:2]];  // 字节地址 → 字地址
end

// Port B: 数据读写 (字节使能写 + 同步读)
wire [AW-1:0] word_addr_b = wbs_adr_i[AW+1:2];

always @(posedge clk) begin
    if (wbs_cyc_i & wbs_stb_i & wbs_we_i) begin
        if (wbs_sel_i[0]) mem[word_addr_b][ 7: 0] <= wbs_dat_i[ 7: 0];
        if (wbs_sel_i[1]) mem[word_addr_b][15: 8] <= wbs_dat_i[15: 8];
        if (wbs_sel_i[2]) mem[word_addr_b][23:16] <= wbs_dat_i[23:16];
        if (wbs_sel_i[3]) mem[word_addr_b][31:24] <= wbs_dat_i[31:24];
    end
    wbs_dat_o <= mem[word_addr_b];  // Read-After-Write: 返回旧值 (Read-First 模式)
end

// ACK: 1 周期延迟脉冲
always @(posedge clk) begin
    if (!rst_n)
        wbs_ack_o <= 1'b0;
    else
        wbs_ack_o <= wbs_cyc_i & wbs_stb_i & ~wbs_ack_o;
end
```

**仿真支持**：通过 `$readmemh` 初始化（ISA 测试、CoreMark 加载）：

```verilog
`ifdef SIM
    reg [255:0] hex_file;
    initial begin
        if ($value$plusargs("HEX=%s", hex_file))
            // 加载 8-bit hex 后小端拼装为 32-bit word（复用 tb_isa 的字节流装配方案）
    end
`endif
```

---

### 5.4 UART 控制器 (`wb_uart.v`)

封装现有 `uart_tx.v` / `uart_rx.v`，提供 Wishbone 寄存器接口。参照 SiFive FE310 UART 寄存器布局。

#### 5.4.1 寄存器映射

基地址：`0x1001_0000`

| 偏移 | 名称 | 位域 | 访问 | 描述 |
|:-----|:-----|:-----|:-----|:-----|
| `0x00` | **TXDATA** | `[31]` = full, `[7:0]` = data | RW | **写**：将 `[7:0]` 送入 TX FIFO。**读**：`bit[31]` = TX FIFO 满标志 |
| `0x04` | **RXDATA** | `[31]` = empty, `[7:0]` = data | RO | **读**：`bit[31]` = RX FIFO 空标志；非空时 `[7:0]` 为接收到的字节并自动出队 |
| `0x08` | **TXCTRL** | `[0]` = txen | RW | `bit[0]`: TX 使能（S1 阶段固定为 1） |
| `0x0C` | **RXCTRL** | `[0]` = rxen | RW | `bit[0]`: RX 使能（S1 阶段固定为 1） |
| `0x10` | **IE** | `[1:0]` = {rxwm, txwm} | RW | 中断使能（S1 阶段未接线，预留） |
| `0x14` | **IP** | `[1:0]` = {rxwm, txwm} | RO | 中断挂起（S1 阶段只读 0） |
| `0x18` | **DIV** | `[15:0]` = divisor | RW | 波特率分频值：`divisor = clk_freq / baud - 1` |

#### 5.4.2 内部结构

```
                    Wishbone Slave Interface
                            │
                    ┌───────▼───────┐
                    │  Register     │
                    │  File         │
                    │ (TXDATA, etc.)│
                    └──┬────────┬──┘
                       │        │
                  ┌────▼──┐  ┌─▼─────┐
                  │TX FIFO│  │RX FIFO│   ← 各 8 字节深度
                  │(8×8b) │  │(8×8b) │
                  └────┬──┘  └─┬─────┘
                       │       │
                  ┌────▼──┐  ┌─▼─────┐
                  │uart_tx│  │uart_rx │   ← 复用现有 RTL
                  └───┬───┘  └──┬────┘
                      │         │
                   uart_txd   uart_rxd    ← FPGA 引脚
```

#### 5.4.3 软件使用示例 (`putchar`)

```c
#define UART_BASE    0x10010000
#define UART_TXDATA  (*(volatile uint32_t *)(UART_BASE + 0x00))

void putchar(int ch) {
    while (UART_TXDATA & 0x80000000)  // 等待 TX FIFO 非满
        ;
    UART_TXDATA = (uint32_t)ch;       // 写入 1 字节
}
```

---

### 5.5 CLINT 定时器 (`wb_clint.v`)

实现 RISC-V 标准 Core-Local Interruptor (CLINT) 的定时器子集。

#### 5.5.1 寄存器映射

基地址：`0x0200_0000`

| 偏移 | 名称 | 宽度 | 访问 | 描述 |
|:-----|:-----|:-----|:-----|:-----|
| `0x0000` | **MSIP** | 32 | RW | `bit[0]`: Machine Software Interrupt Pending（S1 阶段写忽略、读 0） |
| `0x4000` | **MTIMECMP_LO** | 32 | RW | 定时器比较值低 32 位（S1 阶段写入保存、用于 S2 中断触发） |
| `0x4004` | **MTIMECMP_HI** | 32 | RW | 定时器比较值高 32 位 |
| `0xBFF8` | **MTIME_LO** | 32 | RW | 自由运行计数器低 32 位（每个时钟周期 +1） |
| `0xBFFC` | **MTIME_HI** | 32 | RW | 自由运行计数器高 32 位 |

> **偏移地址说明**：这些看似奇怪的偏移（`0x4000`、`0xBFF8`）是 RISC-V 特权级规范 (v1.12) 硬性规定的标准值。在多核系统中，每个 Hart 有独立的 `msip[i]` 和 `mtimecmp[i]`（间隔 4/8 字节排列），而 `mtime` 是全局共享的，因此被放在区域末尾。单核场景下只需实现 Hart 0 的对应偏移即可。

#### 5.5.2 计数器行为

```verilog
reg [63:0] mtime;        // 自由运行 64 位计数器
reg [63:0] mtimecmp;     // 比较值

// 每个时钟上升沿 +1
always @(posedge clk) begin
    if (!rst_n)
        mtime <= 64'd0;
    else
        mtime <= mtime + 64'd1;
end

// 定时器中断条件（S2 阶段接入 CSR.mip.MTIP）
wire timer_irq = (mtime >= mtimecmp);
```

#### 5.5.3 软件使用示例 (`get_time`)

```c
#define CLINT_BASE      0x02000000
#define MTIME_LO        (*(volatile uint32_t *)(CLINT_BASE + 0xBFF8))
#define MTIME_HI        (*(volatile uint32_t *)(CLINT_BASE + 0xBFFC))

// 原子读 64 位 mtime（防止读取过程中低位溢出导致高位翻转）
uint64_t get_time(void) {
    uint32_t hi, lo, hi2;
    do {
        hi  = MTIME_HI;
        lo  = MTIME_LO;
        hi2 = MTIME_HI;
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}
```

---

## 6. SoC 顶层 (`soc_top.v`)

### 6.1 端口列表

```verilog
module soc_top #(
    parameter integer CLK_HZ    = 50_000_000,
    parameter integer BAUD      = 115_200,
    parameter integer SRAM_WORDS = 16384       // 64 KB
) (
    input  wire        clk,
    input  wire        rst_n,

    // ---- UART ----
    output wire        uart_txd,
    input  wire        uart_rxd,

    // ---- 调试 LED ----
    output wire [7:0]  led,

    // ---- 提交追踪 (DiffTest / 仿真用) ----
    output wire        wb_valid,
    output wire        wb_we,
    output wire [31:0] wb_pc,
    output wire [4:0]  wb_rd,
    output wire [31:0] wb_wdata
);
```

### 6.2 内部实例化

```
soc_top
 ├─ core (CPU 核心)
 │    ├── imem_* → wb_sram.Port_A (直连)
 │    └── dmem_* → wb_core_bridge
 ├─ wb_core_bridge (CPU dmem → Wishbone Master)
 ├─ wb_interconnect (地址译码 + MUX)
 │    ├── Slave 0 → wb_sram.Port_B
 │    ├── Slave 1 → wb_uart
 │    └── Slave 2 → wb_clint
 ├─ wb_sram (64KB 双端口 SRAM)
 ├─ wb_uart (UART 控制器，内含 TX/RX FIFO)
 └─ wb_clint (CLINT 定时器)
```

---

## 7. 验证计划

| 测试层级 | 测试目标 | 方法 | 完成标准 |
|:---------|:---------|:-----|:---------|
| Lint | SoC 顶层零警告 | `verilator --lint-only -Wall --top soc_top` | 0 Error, 0 Warning |
| 单元测试 | 各 Wishbone Slave 寄存器读写 | 独立 testbench 发 WB 事务 | 读写值匹配、ACK 时序正确 |
| ISA 回归 | 38 项 ISA 测试在 SoC 上仍然通过 | 将 `tb_isa` 改接 `soc_top` | 38/38 PASS |
| DiffTest 回归 | Spike 差分在 SoC 上仍然通过 | 同上 | 38/38 MATCH |
| UART 输出 | `putchar('H')` 正确发出串口波形 | SoC 级 testbench + 虚拟串口监测 | 接收到正确字符 |
| Timer 读取 | `mtime` 单调递增且可被软件正确读取 | 裸机 C 程序读 Timer 两次并求差 | 差值 > 0 且与周期数一致 |
| CoreMark | CoreMark 在仿真中完整执行并输出分数 | 完整移植 + 仿真运行 | 产出 CoreMark/MHz 数字 |

---

## 8. 未来扩展路径

| 阶段 | 扩展内容 | 对本 Spec 的影响 |
|:-----|:---------|:---------------|
| **S2** CSR/中断 | CLINT 的 `timer_irq` → `csr.mip.MTIP`；UART 中断 → PLIC（或简易中断线） | 增加中断信号线，不改总线协议 |
| **S3a** Cache | 在 core 与 wb_core_bridge 之间插入 I-Cache / D-Cache；Cache Miss 时产生多周期停顿 | `wb_core_bridge` 增加 `dmem_stall` 输出；总线可升级为 Wishbone **Pipelined** 或 **Block Cycle** |
| **S3b** DDR3 | 在 `0x8000_0000` 挂接 DDR3 控制器（使用 PDS IP） | 互连增加 Slave 3；DDR3 控制器在 `platform/pango/` 中实现 |
| **S3c** DMA | 加速器通过 DMA Master 直接读写 DDR3 | 互连升级为多 Master 仲裁（Crossbar 或 Round-Robin 仲裁器） |

---

## 9. RTL 文件清单

| 文件 | 目录 | 功能 |
|:-----|:-----|:-----|
| `wb_core_bridge.v` | `rtl/soc/` | Core dmem → Wishbone Master 桥 |
| `wb_interconnect.v` | `rtl/soc/` | 地址译码 + 读数据/ACK 多路选择 |
| `wb_sram.v` | `rtl/soc/` | 双端口 SRAM (BRAM 推断) |
| `wb_uart.v` | `rtl/soc/` | UART 寄存器接口 + TX/RX FIFO |
| `wb_clint.v` | `rtl/soc/` | CLINT Timer |
| `soc_top.v` | `rtl/soc/` | SoC 顶层集成 |
