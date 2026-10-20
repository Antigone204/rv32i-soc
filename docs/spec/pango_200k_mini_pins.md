# 盘古 200K-MINI（PG2L200H-6FBB676）管脚约束表

> 依据：`3_Hardware\FPGA管脚分配\mini-base管脚映射.xlsx` + `2_Demo` 里厂家工程的 `.fdc` 与 `.pds`（`_flow fab_demo "2022.2-SP6.4"`，`_device PG2L200H / -6 / FBB676`）。
> 配套约束文件：`pangu200k_mini.fdc`（可直接 `Import Logic Constraint File` 导入）。

## 1. 先定版本：装资料包自带的 PDS_2022.2-SP6.4

`5_Software\PDS\PDS_2022.2-SP6.4-win64.zip`（1.8 GB）+ `小眼睛FPGA--license申请模板.xlsx`。

所有 demo 的 `.pds` 头都是 `(_flow fab_demo "2022.2-SP6.4" ... build 146967)`，即**这批例程就是 SP6.4 生成的**。用官网最新 SP6.7.1 打开会提示升级工程格式（不可逆）；除非有明确需求，否则就装 SP6.4，和例程、IP、教程完全对齐。

## 2. 约束表（核心板，27 MHz 系统）

| 端口名（fdc 里的名字） | FPGA 球号 | 方向 | IO 标准 | VCCIO | 驱动 / 斜率 | 板上网络 | 说明 |
|---|---|---|---|---|---|---|---|
| `sys_clk` | **D18** | 输入 | LVCMOS33 | 3.3 V | — | 核心板 27 MHz 有源晶振 | 27 MHz；周期 37.037 ns |
| `rst_n` | **C22** | 输入 | LVCMOS33 | 3.3 V | — | USER_BUTTON0（丝印 KEY0/RST） | 低有效复位（代码 `if(!rstn)`） |
| `key[0]` | **C23** | 输入 | LVCMOS33 | 3.3 V | — | USER_BUTTON1 | 按下为 0（典型上拉按键，待实测确认） |
| `key[1]` | **B22** | 输入 | LVCMOS33 | 3.3 V | — | USER_BUTTON2 | 同上 |
| `key[2]` | **A22** | 输入 | LVCMOS33 | 3.3 V | — | USER_BUTTON3 | 同上 |
| `key[3]` | **B20** | 输入 | LVCMOS33 | 3.3 V | — | USER_BUTTON4 | 同上 |
| `led[0]` | **A20** | 输出 | LVCMOS33 | 3.3 V | 8 mA / SLOW | USER_LED0 | 高电平点亮（按 demo 推断） |
| `led[1]` | **C18** | 输出 | LVCMOS33 | 3.3 V | 8 mA / SLOW | USER_LED1 | |
| `led[2]` | **C19** | 输出 | LVCMOS33 | 3.3 V | 8 mA / SLOW | USER_LED2 | |
| `led[3]` | **E18** | 输出 | LVCMOS33 | 3.3 V | 8 mA / SLOW | USER_LED3 | |
| `led[4]` | **A17** | 输出 | LVCMOS33 | 3.3 V | 8 mA / SLOW | USER_LED4 | |
| `led[5]` | **A18** | 输出 | LVCMOS33 | 3.3 V | 8 mA / SLOW | 核心板板载 LED5 | 不引出到底板 J2 |
| `led[6]` | **C17** | 输出 | LVCMOS33 | 3.3 V | 8 mA / SLOW | 核心板板载 LED6 | 同上 |
| `led[7]` | **B17** | 输出 | LVCMOS33 | 3.3 V | 8 mA / SLOW | 核心板板载 LED7 | 同上 |
| `uart_txd` | **C24** | 输出 | LVCMOS33 | 3.3 V | 8 mA / SLOW | FPGA_UART_TXD → CP2102 | 115200 8N1（27 MHz 时 `BPS_NUM=234`） |
| `uart_rxd` | **B24** | 输入 | LVCMOS33 | 3.3 V | — | FPGA_UART_RXD ← CP2102 | |

### 备用 / 扩展时钟

| 端口名 | 球号 | 说明 |
|---|---|---|
| `clk_27m_alt` | **E17** | 底板经 J2-76 送进来的 27 MHz（xlsx 里叫 `FPGA_GCLK_27M`）。**demo 全部用 D18**，只有在底板另供时钟时才用这个 |

### 不要手动分配（会抢脚/锁死）

| 功能 | 球号 |
|---|---|
| JTAG TCK / TMS / TDI / TDO | H12 / H11 / H10 / J10 |
| DDR3、HDMI、以太网、SFP 等 | 见 xlsx 的 J1 / J2 / J10 / 高速扩展口 各页 |

## 3. 怎么用

1. 新建工程 → Family `Logos2`，Device `PG2L200H`，Speed `-6`，Package `FBB676`。
2. 顶层端口名必须与 fdc 完全一致（`sys_clk`、`rst_n`、`key[3:0]`、`led[7:0]`、`uart_txd`、`uart_rxd`）；如果你的命名不同，用编辑器全局替换 fdc 里的 `p:xxx` 即可。
3. `Import Logic Constraint File` 选 `pangu200k_mini.fdc`；也可以直接在 PDS 的 Pin Planner 里按上表手填。
4. 综合 → 布局布线 → 生成 `.sbit` → 传到远程平台。

## 4. 你给的三个目录里到底有什么

| 目录 | 内容 | 用途 |
|---|---|---|
| `3_Hardware` | `FPGA管脚分配\mini-base管脚映射.xlsx`（底板 J1/J2/J10/高速扩展口的完整球号表）、`点位图`（PCB 器件位置）、`结构图`（DXF） | **没有原理图 PDF**。管脚权威来源就是这份 xlsx；想看电路连接得去 `1_Demo_document\实验例程说明篇\教程1 盘古100K MINI 硬件指导手册.pdf` |
| `4_IC_datasheet` | `DS04001_Logos2系列FPGA器件数据手册.pdf`、RTL8211F、MS7200/MS7210、OV5640、AT24C02、电源芯片 | 查 bank/VCCIO、IO 标准、器件资源；**不含板级管脚** |
| `6_IP_setup_packet` | 只有 `DDR3\ips2l_hmic_s_v1_16a.iar`（8 MB） | 跑 DDR3 例程才需要，用 PDS 的 IP Manager 安装（见 `教程\03_IP核安装与查看用户指南.pdf`） |

## 5. 两个还没被文档证实、但值得实测的点

- **LED 极性**：demo 用 `led_status` 循环移位 `0000_0001`，若高有效则"单灯顺时针跑"；若上板看到"单灯逆时针/反相"，说明低有效，把输出取反即可。
- **按键极性**：`key_led_test.v` 里 `key==1` 左移、`key==0` 右移，但没写按下是 0 还是 1。用 `assign led = {8{key}}` 烧一次，按下看灯灭还是亮即可确定。

## 6. 和远程平台的对应关系

远程平台是 **200K-MINI（PG2L200H）**，与本表同一块板 → 这张表可直接用于测评题；若换到 200Pro（MES2L676-200HP），器件相同但**管脚不同**，本表不能照搬。
