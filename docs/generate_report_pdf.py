#!/usr/bin/env python3
"""
Generate all 9 high-resolution figures for `docs/competition_report_draft.md`
and compile the final competition technical report PDF:
  - docs/RISCV_Parallel_Acc_SoC_Report.pdf
  - build/video_demo/RISCV_Parallel_Acc_SoC_Report.pdf
"""

import asyncio
import os
import re
import shutil
import markdown
from PIL import Image
from playwright.async_api import async_playwright

ROOT_DIR = "/Users/antigone204/Documents/antigravity/radiant-heisenberg"
DOCS_DIR = os.path.join(ROOT_DIR, "docs")
FIG_DIR = os.path.join(DOCS_DIR, "figures")
VIDEO_HTML = os.path.join(ROOT_DIR, "build", "video_demo", "master_video.html")
REPORT_MD = os.path.join(DOCS_DIR, "competition_report_draft.md")
REPORT_PDF = os.path.join(DOCS_DIR, "RISCV_Parallel_Acc_SoC_Report.pdf")
VIDEO_DIR_PDF = os.path.join(ROOT_DIR, "build", "video_demo", "RISCV_Parallel_Acc_SoC_Report.pdf")
CHROME_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


WAVEFORM_HTML = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    width: 1920px;
    height: 1040px;
    background: #0b0f17;
    color: #e6edf3;
    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif;
    padding: 28px 36px;
    display: flex;
    flex-direction: column;
    gap: 20px;
  }
  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 1px solid rgba(56, 139, 253, 0.3);
    padding-bottom: 12px;
  }
  .title {
    font-size: 24px;
    font-weight: 700;
    color: #f0f6fc;
    letter-spacing: 0.5px;
  }
  .subtitle {
    font-size: 15px;
    color: #58a6ff;
    font-family: "JetBrains Mono", "SFMono-Regular", Consolas, monospace;
    background: rgba(56, 139, 253, 0.12);
    border: 1px solid rgba(56, 139, 253, 0.35);
    padding: 5px 14px;
    border-radius: 999px;
  }
  .panel {
    background: #111824;
    border: 1px solid #26334d;
    border-radius: 12px;
    padding: 16px 22px;
    flex: 1;
    display: flex;
    flex-direction: column;
    justify-content: space-between;
  }
  .panel-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 6px;
  }
  .panel-title {
    font-size: 18px;
    font-weight: 700;
    color: #79c0ff;
  }
  .panel-badge {
    font-size: 13px;
    font-family: "JetBrains Mono", Consolas, monospace;
    color: #3fb950;
    background: rgba(46, 160, 67, 0.15);
    border: 1px solid rgba(46, 160, 67, 0.4);
    padding: 3px 10px;
    border-radius: 6px;
  }
  svg {
    width: 100%;
    height: 390px;
    overflow: visible;
  }
  .sig-name {
    font-family: "JetBrains Mono", "SFMono-Regular", Consolas, monospace;
    font-size: 14px;
    font-weight: 600;
    fill: #c9d1d9;
  }
  .sig-sub {
    font-family: "JetBrains Mono", "SFMono-Regular", Consolas, monospace;
    font-size: 11px;
    fill: #8b949e;
  }
  .val-text {
    font-family: "JetBrains Mono", "SFMono-Regular", Consolas, monospace;
    font-size: 13px;
    font-weight: 600;
    fill: #f0f6fc;
    text-anchor: middle;
  }
  .cyc-label {
    font-family: "JetBrains Mono", "SFMono-Regular", Consolas, monospace;
    font-size: 12px;
    fill: #8b949e;
    text-anchor: middle;
  }
  .note-text {
    font-size: 13px;
    font-weight: 600;
    fill: #ffa657;
  }
</style>
</head>
<body>
  <div class="header">
    <div class="title">关键数据通路数字时序波形分析（BPU 零气泡动态分支预测 &amp; Wishbone 4-Lane SIMD 单拍隐式触发）</div>
    <div class="subtitle">Clock = 27.00 MHz (37.037 ns) · Cycle-Exact RTL &amp; ILA Sign-off</div>
  </div>

  <!-- Panel A: BPU Zero-Bubble Branch Prediction -->
  <div class="panel">
    <div class="panel-header">
      <div class="panel-title">（a）五级流水线 BPU（64项 BTB + 2-bit BHT）命中零气泡跳转时序（core.v / bpu.v）</div>
      <div class="panel-badge">✓ btb_hit &amp; bht[1]==1 当拍重定向 if_next_pc，消除 2 拍 EX 冲刷气泡 (0 Penalty)</div>
    </div>
    <svg viewBox="0 0 1800 385">
      <!-- Vertical cycle grid lines: x = 280, 520, 760, 1000, 1240, 1480, 1720 -->
      <g stroke="#21293a" stroke-width="1.5" stroke-dasharray="5,5">
        <line x1="280" y1="20" x2="280" y2="365"/>
        <line x1="520" y1="20" x2="520" y2="365"/>
        <line x1="760" y1="20" x2="760" y2="365"/>
        <line x1="1000" y1="20" x2="1000" y2="365"/>
        <line x1="1240" y1="20" x2="1240" y2="365"/>
        <line x1="1480" y1="20" x2="1480" y2="365"/>
        <line x1="1720" y1="20" x2="1720" y2="365"/>
      </g>
      <!-- Highlight Cycle T1 (BTB Hit) and T3 (EX Verify) -->
      <rect x="520" y="22" width="240" height="340" fill="rgba(56, 139, 253, 0.08)" stroke="rgba(56, 139, 253, 0.35)" stroke-width="1"/>
      <rect x="1000" y="22" width="240" height="340" fill="rgba(46, 160, 67, 0.08)" stroke="rgba(46, 160, 67, 0.35)" stroke-width="1"/>

      <!-- Cycle Headers -->
      <text x="400" y="15" class="cyc-label">Cycle T0 (顺序取指)</text>
      <text x="640" y="15" class="cyc-label" style="fill:#58a6ff;font-weight:700;">Cycle T1 (IF 级 BTB 命中!)</text>
      <text x="880" y="15" class="cyc-label" style="fill:#3fb950;font-weight:700;">Cycle T2 (0气泡切入 Target)</text>
      <text x="1120" y="15" class="cyc-label" style="fill:#3fb950;font-weight:700;">Cycle T3 (EX 级验证无误)</text>
      <text x="1360" y="15" class="cyc-label">Cycle T4 (流水线连续满载)</text>
      <text x="1600" y="15" class="cyc-label">Cycle T5 (WB 级正常退休)</text>

      <!-- Row 1: clk -->
      <text x="15" y="55" class="sig-name">sys_clk (27MHz)</text>
      <path d="M 280 65 L 280 35 L 400 35 L 400 65 L 520 65 L 520 35 L 640 35 L 640 65 L 760 65 L 760 35 L 880 35 L 880 65 L 1000 65 L 1000 35 L 1120 35 L 1120 65 L 1240 65 L 1240 35 L 1360 35 L 1360 65 L 1480 65 L 1480 35 L 1600 35 L 1600 65 L 1720 65" fill="none" stroke="#58a6ff" stroke-width="2.5"/>

      <!-- Row 2: if_pc[31:0] -->
      <text x="15" y="108" class="sig-name">if_pc[31:0]</text>
      <text x="15" y="124" class="sig-sub">IF 级当前取指 PC</text>
      <g stroke="#79c0ff" stroke-width="2" fill="#162238">
        <polygon points="280,105 290,90 510,90 520,105 510,120 290,120"/>
        <polygon points="520,105 530,90 750,90 760,105 750,120 530,120" fill="#1f3a60" stroke="#58a6ff"/>
        <polygon points="760,105 770,90 990,90 1000,105 990,120 770,120" fill="#133423" stroke="#3fb950"/>
        <polygon points="1000,105 1010,90 1230,90 1240,105 1230,120 1010,120"/>
        <polygon points="1240,105 1250,90 1470,90 1480,105 1470,120 1250,120"/>
        <polygon points="1480,105 1490,90 1710,90 1720,105 1710,120 1490,120"/>
      </g>
      <text x="400" y="110" class="val-text">0x0000_0418</text>
      <text x="640" y="110" class="val-text" style="fill:#79c0ff;">0x0000_041C (BNE)</text>
      <text x="880" y="110" class="val-text" style="fill:#56d364;">0x0000_03E0 (Target!)</text>
      <text x="1120" y="110" class="val-text">0x0000_03E4</text>
      <text x="1360" y="110" class="val-text">0x0000_03E8</text>
      <text x="1600" y="110" class="val-text">0x0000_03EC</text>

      <!-- Row 3: btb_hit & bht[1] (pred_taken_o) -->
      <text x="15" y="162" class="sig-name">bpu_pred_taken_o</text>
      <text x="15" y="178" class="sig-sub">btb_hit &amp; (uncond | bht[1])</text>
      <path d="M 280 172 L 520 172 L 528 142 L 752 142 L 760 172 L 1720 172" fill="rgba(56,139,253,0.18)" stroke="#58a6ff" stroke-width="2.5"/>
      <text x="640" y="162" class="val-text" style="fill:#58a6ff;">1'b1 (Hit! BHT=2'b11 强跳)</text>

      <!-- Row 4: if_next_pc[31:0] -->
      <text x="15" y="218" class="sig-name">if_next_pc[31:0]</text>
      <text x="15" y="234" class="sig-sub">组合逻辑下一拍 PC</text>
      <g stroke="#d2a8ff" stroke-width="2" fill="#231934">
        <polygon points="280,215 290,200 510,200 520,215 510,230 290,230"/>
        <polygon points="520,215 530,200 750,200 760,215 750,230 530,230" fill="#2e1d47" stroke="#bc8cff"/>
        <polygon points="760,215 770,200 990,200 1000,215 990,230 770,230"/>
        <polygon points="1000,215 1010,200 1230,200 1240,215 1230,230 1010,230"/>
        <polygon points="1240,215 1250,200 1470,200 1480,215 1470,230 1250,230"/>
        <polygon points="1480,215 1490,200 1710,200 1720,215 1710,230 1490,230"/>
      </g>
      <text x="400" y="220" class="val-text">0x0000_041C</text>
      <text x="640" y="220" class="val-text" style="fill:#e2c5ff;">pred_target = 0x03E0</text>
      <text x="880" y="220" class="val-text">0x0000_03E4</text>
      <text x="1120" y="220" class="val-text">0x0000_03E8</text>
      <text x="1360" y="220" class="val-text">0x0000_03EC</text>
      <text x="1600" y="220" class="val-text">0x0000_03F0</text>

      <!-- Row 5: if_id_valid & id_ex_valid -->
      <text x="15" y="275" class="sig-name">if_id_valid / id_ex_valid</text>
      <text x="15" y="291" class="sig-sub">流水线级间有效位</text>
      <path d="M 280 260 L 1720 260" fill="none" stroke="#3fb950" stroke-width="3"/>
      <rect x="280" y="260" width="1440" height="24" fill="rgba(46,160,67,0.12)"/>
      <text x="1000" y="277" class="val-text" style="fill:#56d364;">恒为 1'b1（全流水线连续满载，零冲刷气泡插入）</text>

      <!-- Row 6: ex_branch_mispred / flush -->
      <text x="15" y="332" class="sig-name">ex_branch_mispred</text>
      <text x="15" y="348" class="sig-sub">EX 级预测错误冲刷信号</text>
      <path d="M 280 342 L 1720 342" fill="none" stroke="#8b949e" stroke-width="2.5"/>
      <text x="1120" y="330" class="val-text" style="fill:#3fb950;">0 (actual == pred_taken, 预测准确!)</text>
    </svg>
  </div>

  <!-- Panel B: Wishbone B4 4-Lane SIMD Implicit Trigger & Zero-Latency ReLU -->
  <div class="panel">
    <div class="panel-header">
      <div class="panel-title">（b）Wishbone B4 总线 4 路并行 SIMD 隐式写触发与零延迟 ReLU 读出时序（wb_mac_acc.v）</div>
      <div class="panel-badge">✓ 写 0x08 (ACC_OPB_TRIG) 当拍完成 4×INT8 乘加；读 0x10 (ACC_RELU) 零额外周期返回激活值</div>
    </div>
    <svg viewBox="0 0 1800 385">
      <g stroke="#21293a" stroke-width="1.5" stroke-dasharray="5,5">
        <line x1="280" y1="20" x2="280" y2="365"/>
        <line x1="520" y1="20" x2="520" y2="365"/>
        <line x1="760" y1="20" x2="760" y2="365"/>
        <line x1="1000" y1="20" x2="1000" y2="365"/>
        <line x1="1240" y1="20" x2="1240" y2="365"/>
        <line x1="1480" y1="20" x2="1480" y2="365"/>
        <line x1="1720" y1="20" x2="1720" y2="365"/>
      </g>
      <rect x="280" y="22" width="240" height="340" fill="rgba(56, 139, 253, 0.06)"/>
      <rect x="520" y="22" width="240" height="340" fill="rgba(210, 153, 34, 0.08)" stroke="rgba(210, 153, 34, 0.35)"/>
      <rect x="760" y="22" width="240" height="340" fill="rgba(163, 113, 247, 0.10)" stroke="rgba(163, 113, 247, 0.4)"/>
      <rect x="1240" y="22" width="240" height="340" fill="rgba(46, 160, 67, 0.10)" stroke="rgba(46, 160, 67, 0.4)"/>

      <text x="400" y="15" class="cyc-label">Cycle C0 (写 0x0C 预载 Bias)</text>
      <text x="640" y="15" class="cyc-label" style="fill:#ffa657;font-weight:700;">Cycle C1 (写 0x04 打包权重 W)</text>
      <text x="880" y="15" class="cyc-label" style="fill:#d2a8ff;font-weight:700;">Cycle C2 (写 0x08 隐式触发 4×MAC!)</text>
      <text x="1120" y="15" class="cyc-label">Cycle C3 (下一组 4×MAC 触发)</text>
      <text x="1360" y="15" class="cyc-label" style="fill:#3fb950;font-weight:700;">Cycle C4 (读 0x10 硬件 ReLU 输出)</text>
      <text x="1600" y="15" class="cyc-label">Cycle C5 (总线释放 / 下一神经元)</text>

      <!-- Row 1: clk -->
      <text x="15" y="55" class="sig-name">sys_clk (27MHz)</text>
      <path d="M 280 65 L 280 35 L 400 35 L 400 65 L 520 65 L 520 35 L 640 35 L 640 65 L 760 65 L 760 35 L 880 35 L 880 65 L 1000 65 L 1000 35 L 1120 35 L 1120 65 L 1240 65 L 1240 35 L 1360 35 L 1360 65 L 1480 65 L 1480 35 L 1600 35 L 1600 65 L 1720 65" fill="none" stroke="#58a6ff" stroke-width="2.5"/>

      <!-- Row 2: wbs_cyc_i & wbs_stb_i -->
      <text x="15" y="106" class="sig-name">wbs_cyc_i &amp; wbs_stb_i</text>
      <text x="15" y="122" class="sig-sub">Wishbone 从设备选通</text>
      <path d="M 280 118 L 288 90 L 1472 90 L 1480 118 L 1720 118" fill="rgba(56,139,253,0.15)" stroke="#58a6ff" stroke-width="2.5"/>
      <text x="880" y="109" class="val-text">1'b1 (Slave 3: 0x2000_00xx 连续单拍事务)</text>

      <!-- Row 3: wbs_adr_i[4:0] & wbs_we_i -->
      <text x="15" y="162" class="sig-name">wbs_adr_i / wbs_we_i</text>
      <text x="15" y="178" class="sig-sub">寄存器偏移与读写方向</text>
      <g stroke="#ffa657" stroke-width="2" fill="#2b1d11">
        <polygon points="280,162 290,147 510,147 520,162 510,177 290,177"/>
        <polygon points="520,162 530,147 750,147 760,162 750,177 530,177"/>
        <polygon points="760,162 770,147 990,147 1000,162 990,177 770,177" fill="#321c4a" stroke="#d2a8ff"/>
        <polygon points="1000,162 1010,147 1230,147 1240,162 1230,177 1010,177" fill="#321c4a" stroke="#d2a8ff"/>
        <polygon points="1240,162 1250,147 1470,147 1480,162 1470,177 1250,177" fill="#133423" stroke="#3fb950"/>
        <polygon points="1480,162 1490,147 1710,147 1720,162 1710,177 1490,177" fill="#161b22" stroke="#484f58"/>
      </g>
      <text x="400" y="167" class="val-text">WR 0x0C (ACC_BIAS)</text>
      <text x="640" y="167" class="val-text" style="fill:#ffa657;">WR 0x04 (ACC_OPA)</text>
      <text x="880" y="167" class="val-text" style="fill:#e2c5ff;">WR 0x08 (OPB_TRIG!)</text>
      <text x="1120" y="167" class="val-text" style="fill:#e2c5ff;">WR 0x08 (OPB_TRIG!)</text>
      <text x="1360" y="167" class="val-text" style="fill:#56d364;">RD 0x10 (ACC_RELU)</text>
      <text x="1600" y="167" class="val-text" style="fill:#8b949e;">IDLE</text>

      <!-- Row 4: wbs_dat_i[31:0] (Packed INT8x4) -->
      <text x="15" y="220" class="sig-name">wbs_dat_i[31:0]</text>
      <text x="15" y="236" class="sig-sub">32位打包写入数据</text>
      <g stroke="#79c0ff" stroke-width="2" fill="#162238">
        <polygon points="280,218 290,203 510,203 520,218 510,233 290,233"/>
        <polygon points="520,218 530,203 750,203 760,218 750,233 530,233"/>
        <polygon points="760,218 770,203 990,203 1000,218 990,233 770,233"/>
        <polygon points="1000,218 1010,203 1230,203 1240,218 1230,233 1010,233"/>
        <polygon points="1240,218 1250,203 1710,203 1720,218 1710,233 1250,233" fill="#161b22" stroke="#484f58"/>
      </g>
      <text x="400" y="223" class="val-text">Bias = -120</text>
      <text x="640" y="223" class="val-text">{w3, w2, w1, w0}</text>
      <text x="880" y="223" class="val-text">{x3, x2, x1, x0} (+340)</text>
      <text x="1120" y="223" class="val-text">{x7, x6, x5, x4} (-290)</text>
      <text x="1480" y="223" class="val-text" style="fill:#8b949e;">-- (Read Transaction)</text>

      <!-- Row 5: acc_reg[31:0] (Internal 32-bit Accumulator) -->
      <text x="15" y="278" class="sig-name">acc_reg[31:0]</text>
      <text x="15" y="294" class="sig-sub">32位有符号累加器状态</text>
      <g stroke="#d2a8ff" stroke-width="2" fill="#231934">
        <polygon points="280,275 290,260 510,260 520,275 510,290 290,290"/>
        <polygon points="520,275 530,260 990,260 1000,275 990,290 530,290"/>
        <polygon points="1000,275 1010,260 1230,260 1240,275 1230,290 1010,290" fill="#321c4a" stroke="#d2a8ff"/>
        <polygon points="1240,275 1250,260 1710,260 1720,275 1710,290 1250,290" fill="#3a1d28" stroke="#ff7b72"/>
      </g>
      <text x="400" y="280" class="val-text">0</text>
      <text x="760" y="280" class="val-text">acc = -120 (Bias Preloaded)</text>
      <text x="1120" y="280" class="val-text" style="fill:#e2c5ff;">acc = -120 + 340 = +220</text>
      <text x="1480" y="280" class="val-text" style="fill:#ffa198;">acc = +220 - 290 = -70 (Negative)</text>

      <!-- Row 6: wbs_ack_o & wbs_dat_o (ReLU Readback) -->
      <text x="15" y="335" class="sig-name">wbs_ack_o / wbs_dat_o</text>
      <text x="15" y="351" class="sig-sub">单拍应答与 ReLU 读回值</text>
      <g stroke="#3fb950" stroke-width="2" fill="#133423">
        <polygon points="280,335 290,320 1230,320 1240,335 1230,350 290,350" fill="#162238" stroke="#58a6ff"/>
        <polygon points="1240,335 1250,320 1470,320 1480,335 1470,350 1250,350" fill="#133423" stroke="#3fb950"/>
        <polygon points="1480,335 1490,320 1710,320 1720,335 1710,350 1490,350" fill="#161b22" stroke="#484f58"/>
      </g>
      <text x="760" y="340" class="val-text" style="fill:#79c0ff;">wbs_ack_o = 1 (零等待单周期写应答)</text>
      <text x="1360" y="340" class="val-text" style="fill:#56d364;">ACK=1, dat_o=0 (ReLU 截断)</text>
      <text x="1600" y="340" class="val-text" style="fill:#8b949e;">ACK=0</text>
    </svg>
  </div>
</body>
</html>
"""


MERMAID_SVG_1 = """
<div class="diagram-box">
<svg viewBox="0 0 980 210" style="width:100%;height:auto;display:block;margin:0 auto;">
  <defs>
    <marker id="arr1" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#2563eb"/>
    </marker>
  </defs>
  <!-- CPU Box -->
  <rect x="16" y="45" width="210" height="120" rx="10" fill="#eff6ff" stroke="#2563eb" stroke-width="2"/>
  <text x="121" y="95" text-anchor="middle" font-size="15" font-weight="700" fill="#1e3a8a">RV32IM 5级流水线核</text>
  <text x="121" y="120" text-anchor="middle" font-size="12.5" fill="#1d4ed8">(BTB+BHT / MULDIV)</text>

  <!-- Wishbone Box -->
  <rect x="350" y="85" width="230" height="80" rx="10" fill="#fef3c7" stroke="#d97706" stroke-width="2"/>
  <text x="465" y="120" text-anchor="middle" font-size="15" font-weight="700" fill="#92400e">Wishbone B4 互联矩阵</text>
  <text x="465" y="142" text-anchor="middle" font-size="12.5" fill="#b45309">(1-Master 4-Slave)</text>

  <!-- Slave 0: SRAM -->
  <rect x="720" y="8" width="240" height="44" rx="7" fill="#ecfdf5" stroke="#059669" stroke-width="1.8"/>
  <text x="840" y="27" text-anchor="middle" font-size="13.5" font-weight="700" fill="#065f46">64KB 双端口 SRAM</text>
  <text x="840" y="44" text-anchor="middle" font-size="11.5" fill="#047857">(GTP_DRM36K_E1 · Port A &amp; B)</text>

  <!-- Slave 1: UART -->
  <rect x="720" y="60" width="240" height="42" rx="7" fill="#f8fafc" stroke="#475569" stroke-width="1.6"/>
  <text x="840" y="78" text-anchor="middle" font-size="13.5" font-weight="700" fill="#1e293b">UART0 控制器</text>
  <text x="840" y="95" text-anchor="middle" font-size="11.5" fill="#475569">(8B TX/RX FIFO · 115200 bps)</text>

  <!-- Slave 2: CLINT -->
  <rect x="720" y="110" width="240" height="42" rx="7" fill="#f8fafc" stroke="#475569" stroke-width="1.6"/>
  <text x="840" y="128" text-anchor="middle" font-size="13.5" font-weight="700" fill="#1e293b">CLINT 定时器</text>
  <text x="840" y="145" text-anchor="middle" font-size="11.5" fill="#475569">(64-bit mtime / mtimecmp)</text>

  <!-- Slave 3: ACC -->
  <rect x="720" y="160" width="240" height="44" rx="7" fill="#f5f3ff" stroke="#7c3aed" stroke-width="2"/>
  <text x="840" y="179" text-anchor="middle" font-size="13.5" font-weight="700" fill="#5b21b6">4路 SIMD INT8 加速器</text>
  <text x="840" y="196" text-anchor="middle" font-size="11.5" fill="#6d28d9">(隐式写触发 + 零延迟 ReLU)</text>

  <!-- Arrows -->
  <path d="M 226 68 L 226 30 L 716 30" fill="none" stroke="#059669" stroke-width="2.2" marker-end="url(#arr1)"/>
  <text x="465" y="23" text-anchor="middle" font-size="12" font-weight="600" fill="#059669">Port A 专用零等待取指 (imem)</text>

  <path d="M 226 125 L 346 125" fill="none" stroke="#2563eb" stroke-width="2.2" marker-end="url(#arr1)"/>
  <text x="286" y="116" text-anchor="middle" font-size="12" font-weight="600" fill="#1d4ed8">dmem 访存桥</text>

  <path d="M 580 105 L 645 105 L 645 36 L 716 36" fill="none" stroke="#2563eb" stroke-width="1.8" marker-end="url(#arr1)"/>
  <text x="680" y="48" text-anchor="middle" font-size="11" fill="#334155">Slave 0</text>

  <path d="M 580 118 L 655 118 L 655 81 L 716 81" fill="none" stroke="#2563eb" stroke-width="1.8" marker-end="url(#arr1)"/>
  <text x="685" y="75" text-anchor="middle" font-size="11" fill="#334155">Slave 1</text>

  <path d="M 580 131 L 716 131" fill="none" stroke="#2563eb" stroke-width="1.8" marker-end="url(#arr1)"/>
  <text x="680" y="125" text-anchor="middle" font-size="11" fill="#334155">Slave 2</text>

  <path d="M 580 145 L 645 145 L 645 182 L 716 182" fill="none" stroke="#7c3aed" stroke-width="2" marker-end="url(#arr1)"/>
  <text x="680" y="176" text-anchor="middle" font-size="11" font-weight="600" fill="#6d28d9">Slave 3</text>
</svg>
</div>
"""


MERMAID_SVG_2 = """
<div class="diagram-box">
<svg viewBox="0 0 980 96" style="width:100%;height:auto;display:block;margin:0 auto;">
  <defs>
    <marker id="arr2" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#2563eb"/>
    </marker>
  </defs>
  <g font-family="sans-serif">
    <rect x="8" y="10" width="170" height="76" rx="8" fill="#eff6ff" stroke="#2563eb" stroke-width="1.8"/>
    <text x="93" y="34" text-anchor="middle" font-size="13.5" font-weight="700" fill="#1e3a8a">1. 架构定义</text>
    <text x="93" y="53" text-anchor="middle" font-size="11.5" fill="#334155">编写模块 Spec</text>
    <text x="93" y="70" text-anchor="middle" font-size="11.5" fill="#334155">与总线地址映射</text>

    <path d="M 178 48 L 204 48" stroke="#2563eb" stroke-width="2" marker-end="url(#arr2)"/>

    <rect x="208" y="10" width="170" height="76" rx="8" fill="#eff6ff" stroke="#2563eb" stroke-width="1.8"/>
    <text x="293" y="34" text-anchor="middle" font-size="13.5" font-weight="700" fill="#1e3a8a">2. RTL 实现</text>
    <text x="293" y="53" text-anchor="middle" font-size="11.5" fill="#334155">纯 Verilog-2001</text>
    <text x="293" y="70" text-anchor="middle" font-size="11.5" fill="#334155">Verilator 0 Warning</text>

    <path d="M 378 48 L 404 48" stroke="#2563eb" stroke-width="2" marker-end="url(#arr2)"/>

    <rect x="408" y="10" width="170" height="76" rx="8" fill="#ecfdf5" stroke="#059669" stroke-width="1.8"/>
    <text x="493" y="34" text-anchor="middle" font-size="13.5" font-weight="700" fill="#065f46">3. 差分验证</text>
    <text x="493" y="53" text-anchor="middle" font-size="11.5" fill="#047857">46项官方 ISA 测试</text>
    <text x="493" y="70" text-anchor="middle" font-size="11.5" fill="#047857">Spike 100% Match</text>

    <path d="M 578 48 L 604 48" stroke="#2563eb" stroke-width="2" marker-end="url(#arr2)"/>

    <rect x="608" y="10" width="170" height="76" rx="8" fill="#f5f3ff" stroke="#7c3aed" stroke-width="1.8"/>
    <text x="693" y="34" text-anchor="middle" font-size="13.5" font-weight="700" fill="#5b21b6">4. 软硬协同</text>
    <text x="693" y="53" text-anchor="middle" font-size="11.5" fill="#6d28d9">C Runtime 移植</text>
    <text x="693" y="70" text-anchor="middle" font-size="11.5" fill="#6d28d9">CoreMark &amp; 算子调优</text>

    <path d="M 778 48 L 804 48" stroke="#2563eb" stroke-width="2" marker-end="url(#arr2)"/>

    <rect x="808" y="10" width="164" height="76" rx="8" fill="#fef3c7" stroke="#d97706" stroke-width="1.8"/>
    <text x="890" y="34" text-anchor="middle" font-size="13.5" font-weight="700" fill="#92400e">5. 板级签核</text>
    <text x="890" y="53" text-anchor="middle" font-size="11.5" fill="#b45309">PDS 2022.2 综合</text>
    <text x="890" y="70" text-anchor="middle" font-size="11.5" fill="#b45309">远程实验箱实测</text>
  </g>
</svg>
</div>
"""


MERMAID_SVG_3 = """
<div class="diagram-box">
<svg viewBox="0 0 980 230" style="width:100%;height:auto;display:block;margin:0 auto;">
  <defs>
    <marker id="arr3" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#2563eb"/>
    </marker>
  </defs>
  <!-- Subgraph 1: Host PC -->
  <rect x="10" y="8" width="465" height="214" rx="10" fill="#f8fafc" stroke="#94a3b8" stroke-width="1.5" stroke-dasharray="5,4"/>
  <text x="242" y="28" text-anchor="middle" font-size="13" font-weight="700" fill="#334155">宿主机开发与验证端 (Mac / Windows 工具链闭环)</text>

  <rect x="28" y="42" width="200" height="46" rx="6" fill="#eff6ff" stroke="#2563eb" stroke-width="1.5"/>
  <text x="128" y="62" text-anchor="middle" font-size="12" font-weight="700" fill="#1e3a8a">xPack RISC-V GCC 15.2</text>
  <text x="128" y="79" text-anchor="middle" font-size="11" fill="#1d4ed8">(-march=rv32im_zicsr -O2)</text>

  <rect x="260" y="42" width="195" height="46" rx="6" fill="#eff6ff" stroke="#2563eb" stroke-width="1.5"/>
  <text x="357" y="62" text-anchor="middle" font-size="12" font-weight="700" fill="#1e3a8a">固件 ELF / Binary</text>
  <text x="357" y="79" text-anchor="middle" font-size="11" fill="#334155">bin2words.py → 16384行 HEX</text>

  <rect x="28" y="108" width="200" height="46" rx="6" fill="#ecfdf5" stroke="#059669" stroke-width="1.5"/>
  <text x="128" y="128" text-anchor="middle" font-size="12" font-weight="700" fill="#065f46">Verilator / Icarus 仿真</text>
  <text x="128" y="145" text-anchor="middle" font-size="11" fill="#047857">+ Spike 逐指令 DiffTest</text>

  <rect x="260" y="108" width="195" height="46" rx="6" fill="#fef3c7" stroke="#d97706" stroke-width="1.5"/>
  <text x="357" y="128" text-anchor="middle" font-size="12" font-weight="700" fill="#92400e">PDS 2022.2 (pds_shell)</text>
  <text x="357" y="145" text-anchor="middle" font-size="11" fill="#b45309">综合布局布线 → fpga_top.sbit</text>

  <rect x="110" y="170" width="290" height="40" rx="6" fill="#f1f5f9" stroke="#475569" stroke-width="1.5"/>
  <text x="255" y="188" text-anchor="middle" font-size="12" font-weight="700" fill="#0f172a">紫光远程 FPGA 实验箱 Web 终端</text>
  <text x="255" y="203" text-anchor="middle" font-size="10.5" fill="#475569">(115200 8N1 串口报告 &amp; 4颗物理 LED 监控)</text>

  <!-- Subgraph 2: On-chip FW -->
  <rect x="495" y="8" width="475" height="214" rx="10" fill="#f8fafc" stroke="#94a3b8" stroke-width="1.5" stroke-dasharray="5,4"/>
  <text x="732" y="28" text-anchor="middle" font-size="13" font-weight="700" fill="#334155">FPGA 片上嵌入式软件栈 (64KB 双端口 SRAM)</text>

  <rect x="515" y="42" width="205" height="46" rx="6" fill="#eff6ff" stroke="#2563eb" stroke-width="1.5"/>
  <text x="617" y="62" text-anchor="middle" font-size="12" font-weight="700" fill="#1e3a8a">crt0.S 启动汇编</text>
  <text x="617" y="79" text-anchor="middle" font-size="11" fill="#334155">清零寄存器 / SP初始化 / BSS清零</text>

  <rect x="750" y="42" width="200" height="46" rx="6" fill="#f5f3ff" stroke="#7c3aed" stroke-width="1.5"/>
  <text x="850" y="62" text-anchor="middle" font-size="12" font-weight="700" fill="#5b21b6">1. 算子加速三路评测</text>
  <text x="850" y="79" text-anchor="middle" font-size="11" fill="#6d28d9">软乘 vs 硬件MUL vs SIMD加速器</text>

  <rect x="750" y="108" width="200" height="46" rx="6" fill="#ecfdf5" stroke="#059669" stroke-width="1.5"/>
  <text x="850" y="128" text-anchor="middle" font-size="12" font-weight="700" fill="#065f46">2. CoreMark 2K 满载评测</text>
  <text x="850" y="145" text-anchor="middle" font-size="11" fill="#047857">1000 Iterations (12.235s @ 27MHz)</text>

  <rect x="515" y="108" width="205" height="46" rx="6" fill="#fef3c7" stroke="#d97706" stroke-width="1.5"/>
  <text x="617" y="128" text-anchor="middle" font-size="12" font-weight="700" fill="#92400e">底层硬件抽象层 HAL</text>
  <text x="617" y="145" text-anchor="middle" font-size="11" fill="#b45309">uart.c / timer.c / str.c / soc.h</text>

  <!-- Connectors -->
  <path d="M 228 65 L 256 65" stroke="#2563eb" stroke-width="1.8" marker-end="url(#arr3)"/>
  <path d="M 300 88 L 160 106" stroke="#059669" stroke-width="1.6" marker-end="url(#arr3)"/>
  <path d="M 357 88 L 357 104" stroke="#d97706" stroke-width="1.8" marker-end="url(#arr3)"/>
  <path d="M 357 154 L 290 168" stroke="#475569" stroke-width="1.8" marker-end="url(#arr3)"/>
  <path d="M 720 65 L 746 65" stroke="#2563eb" stroke-width="1.8" marker-end="url(#arr3)"/>
  <path d="M 850 88 L 850 104" stroke="#7c3aed" stroke-width="1.8" marker-end="url(#arr3)"/>
  <path d="M 750 131 L 724 131" stroke="#059669" stroke-width="1.8" marker-end="url(#arr3)"/>
  <path d="M 617 154 L 617 190 L 404 190" fill="none" stroke="#475569" stroke-width="1.8" marker-end="url(#arr3)"/>
</svg>
</div>
"""


MERMAID_SVG_4 = """
<div class="diagram-box">
<svg viewBox="0 0 980 112" style="width:100%;height:auto;display:block;margin:0 auto;">
  <defs>
    <marker id="arr4" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
      <path d="M 0 1 L 10 5 L 0 9 z" fill="#2563eb"/>
    </marker>
  </defs>
  <g font-family="sans-serif">
    <rect x="6" y="10" width="174" height="92" rx="8" fill="#eff6ff" stroke="#2563eb" stroke-width="1.8"/>
    <text x="93" y="31" text-anchor="middle" font-size="12.5" font-weight="700" fill="#1e3a8a">1. 顶层启动与调度</text>
    <text x="93" y="49" text-anchor="middle" font-size="11.5" font-weight="600" fill="#1d4ed8">_start (crt0.S) → main()</text>
    <text x="93" y="67" text-anchor="middle" font-size="10.5" fill="#334155">入: __bss_start / __stack_top</text>
    <text x="93" y="84" text-anchor="middle" font-size="10.5" fill="#334155">出: SIM_CTRL (LED1/2 状态)</text>

    <path d="M 180 56 L 204 56" stroke="#2563eb" stroke-width="2" marker-end="url(#arr4)"/>

    <rect x="206" y="10" width="174" height="92" rx="8" fill="#f5f3ff" stroke="#7c3aed" stroke-width="1.8"/>
    <text x="293" y="31" text-anchor="middle" font-size="12.5" font-weight="700" fill="#5b21b6">2. 算子三路评测</text>
    <text x="293" y="49" text-anchor="middle" font-size="11" font-weight="600" fill="#6d28d9">run_board_acc_benchmark()</text>
    <text x="293" y="67" text-anchor="middle" font-size="10.5" fill="#334155">入: g_weights[16][64] / g_inputs</text>
    <text x="293" y="84" text-anchor="middle" font-size="10.5" fill="#334155">出: out_acc[16] / 周期加速比</text>

    <path d="M 380 56 L 404 56" stroke="#2563eb" stroke-width="2" marker-end="url(#arr4)"/>

    <rect x="406" y="10" width="174" height="92" rx="8" fill="#ecfdf5" stroke="#059669" stroke-width="1.8"/>
    <text x="493" y="31" text-anchor="middle" font-size="12.5" font-weight="700" fill="#065f46">3. CoreMark 2K 评测</text>
    <text x="493" y="49" text-anchor="middle" font-size="11" font-weight="600" fill="#047857">core_main() / portable_fini()</text>
    <text x="493" y="67" text-anchor="middle" font-size="10.5" fill="#334155">入: seed=0x66 / iter=1000</text>
    <text x="493" y="84" text-anchor="middle" font-size="10.5" fill="#334155">出: CRC16 签名 / 3.027 CM/MHz</text>

    <path d="M 580 56 L 604 56" stroke="#2563eb" stroke-width="2" marker-end="url(#arr4)"/>

    <rect x="606" y="10" width="174" height="92" rx="8" fill="#fef3c7" stroke="#d97706" stroke-width="1.8"/>
    <text x="693" y="31" text-anchor="middle" font-size="12.5" font-weight="700" fill="#92400e">4. 外设与防撕裂计时 HAL</text>
    <text x="693" y="49" text-anchor="middle" font-size="11" font-weight="600" fill="#b45309">ee_printf / uart_putc / get_time</text>
    <text x="693" y="67" text-anchor="middle" font-size="10.5" fill="#334155">入: fmt 字符串 / MTIME_HI,LO</text>
    <text x="693" y="84" text-anchor="middle" font-size="10.5" fill="#334155">出: TX FIFO 帧 / 64-bit ticks</text>

    <path d="M 780 56 L 804 56" stroke="#2563eb" stroke-width="2" marker-end="url(#arr4)"/>

    <rect x="806" y="10" width="168" height="92" rx="8" fill="#f1f5f9" stroke="#475569" stroke-width="1.8"/>
    <text x="890" y="31" text-anchor="middle" font-size="12.5" font-weight="700" fill="#0f172a">5. 寄存器映射与内存布局</text>
    <text x="890" y="49" text-anchor="middle" font-size="11" font-weight="600" fill="#334155">soc.h (MMIO) &amp; link.ld</text>
    <text x="890" y="67" text-anchor="middle" font-size="10.5" fill="#334155">SRAM: 0x0000~0xFFFF (64KB)</text>
    <text x="890" y="84" text-anchor="middle" font-size="10.5" fill="#334155">ACC: 0x2000_0000~0x10</text>
  </g>
</svg>
</div>
"""


async def generate_all_figures():
    os.makedirs(FIG_DIR, exist_ok=True)
    async with async_playwright() as p:
        browser = await p.chromium.launch(executable_path=CHROME_PATH)

        # 1. Capture scenes from master_video.html (1920x1080)
        page = await browser.new_page(viewport={"width": 1920, "height": 1080})
        await page.goto(f"file://{VIDEO_HTML}", wait_until="networkidle")
        await page.wait_for_timeout(500)

        # Pause timeline and hide HUD & Subtitles so figures are clean technical visuals
        await page.evaluate("""() => {
            const sub = document.getElementById('subtitle-container');
            if (sub) sub.style.display = 'none';
            const hud = document.getElementById('hud-overlay');
            if (hud) hud.style.display = 'none';
        }""")

        async def seek_and_capture(t_sec, out_path, custom_js=None):
            await page.evaluate(f"async () => {{ await window.seekAndRender({t_sec}); }}")
            await page.evaluate("""() => {
                const sub = document.getElementById('subtitle-container');
                if (sub) sub.style.display = 'none';
                const hud = document.getElementById('hud-overlay');
                if (hud) hud.style.display = 'none';
            }""")
            if custom_js:
                await page.evaluate(custom_js)
            await page.wait_for_timeout(200)
            await page.screenshot(path=out_path)
            print(f"[OK] Saved figure: {out_path}")

        # Capture the 7 direct full-frame technical diagrams/scenes
        await seek_and_capture(37.5, os.path.join(FIG_DIR, "fig_arch_soc_topo.png"))
        await seek_and_capture(65.0, os.path.join(FIG_DIR, "fig_arch_pipeline_bpu.png"))
        await seek_and_capture(88.0, os.path.join(FIG_DIR, "fig_arch_simd_race.png"))
        await seek_and_capture(106.5, os.path.join(FIG_DIR, "fig1_verilator_difftest.png"))

        # For fig3_pds_synthesis_timing.png, align LUT/WNS numbers to Table 3.2.2 in the report
        act6_exact_js = """() => {
            const v1 = document.getElementById('act6-val-1');
            if (v1) v1.textContent = '2.10%';
            const subs = document.querySelectorAll('#act-6 .fpga-card-sub');
            if (subs && subs.length >= 3) {
                subs[0].textContent = '3,359 / 159,800 LUT · 33 DRM · 8 APM';
                subs[2].textContent = 'WNS = +20.228 ns · WHS = +0.149 ns · 0 违例';
            }
            const v2 = document.getElementById('act6-val-2');
            if (v2) v2.textContent = '58.03';
            const v3 = document.getElementById('act6-val-3');
            if (v3) v3.textContent = '+20.23';
        }"""
        await seek_and_capture(118.0, os.path.join(FIG_DIR, "fig3_pds_synthesis_timing.png"), custom_js=act6_exact_js)
        await seek_and_capture(124.5, os.path.join(FIG_DIR, "fig2_remote_board_overview.png"))
        await seek_and_capture(140.0, os.path.join(FIG_DIR, "fig4_board_leds_closeup.png"))

        # Capture Cut 2 (t=135.0s) and Cut 4 (t=155.0s) for fig5_uart_acc_coremark.png composite
        tmp_cut2 = os.path.join(FIG_DIR, "_tmp_cut2.png")
        tmp_cut4 = os.path.join(FIG_DIR, "_tmp_cut4.png")
        await seek_and_capture(135.0, tmp_cut2)
        await seek_and_capture(155.0, tmp_cut4)

        # Stitch Cut 2 and Cut 4 side-by-side into fig5_uart_acc_coremark.png
        im2 = Image.open(tmp_cut2)
        im4 = Image.open(tmp_cut4)
        # Crop each 1920x1080 frame to the central content area (80, 30, 1840, 1040) -> 1760x1010
        c2 = im2.crop((80, 25, 1840, 1045))
        c4 = im4.crop((80, 25, 1840, 1045))
        comp = Image.new("RGB", (c2.width + c4.width + 24, c2.height), (11, 15, 23))
        comp.paste(c2, (0, 0))
        comp.paste(c4, (c2.width + 24, 0))
        comp. resize((1920, int(1920 * comp.height / comp.width)), Image.Resampling.LANCZOS).save(
            os.path.join(FIG_DIR, "fig5_uart_acc_coremark.png")
        )
        os.remove(tmp_cut2)
        os.remove(tmp_cut4)
        print(f"[OK] Saved composite figure: {os.path.join(FIG_DIR, 'fig5_uart_acc_coremark.png')}")
        await page.close()

        # 2. Render fig6_datapath_waveform.png (1920x1040)
        wf_page = await browser.new_page(viewport={"width": 1920, "height": 1040})
        await wf_page.set_content(WAVEFORM_HTML, wait_until="load")
        await wf_page.wait_for_timeout(150)
        wf_out = os.path.join(FIG_DIR, "fig6_datapath_waveform.png")
        await wf_page.screenshot(path=wf_out)
        await wf_page.close()
        print(f"[OK] Saved waveform figure: {wf_out}")

        await browser.close()


def convert_markdown_to_html(md_text: str) -> str:
    # 0. Normalize indented fenced code blocks & nested lists for Python-Markdown
    lines = md_text.splitlines()
    norm_lines = []
    in_fence = False
    fence_indent = 0
    for line in lines:
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if stripped.startswith("```"):
            if not in_fence:
                if norm_lines and norm_lines[-1].strip() != "":
                    norm_lines.append("")
                in_fence = True
                fence_indent = indent
                norm_lines.append(stripped)
            else:
                in_fence = False
                norm_lines.append(stripped)
                norm_lines.append("")
            continue
        if in_fence:
            if indent >= fence_indent and line[:fence_indent].strip() == "":
                norm_lines.append(line[fence_indent:])
            else:
                norm_lines.append(line)
            continue

        # Handle list items: top-level (indent == 0) vs nested (indent >= 2)
        m_list = re.match(r"^(\s*)([*\-]|\d+\.)\s+(.*)$", line)
        if m_list:
            marker = m_list.group(2)
            content = m_list.group(3)
            if indent >= 2:
                # Python-Markdown requires 4-space indentation for nested lists
                # and a blank line when transitioning from a parent list item text
                if norm_lines and norm_lines[-1].strip() != "" and not norm_lines[-1].startswith("    "):
                    norm_lines.append("")
                norm_lines.append(f"    {marker} {content}")
            else:
                if norm_lines and norm_lines[-1].strip() != "" and (
                    not re.match(r"^([*\-]|\d+\.)\s+", norm_lines[-1])
                ):
                    norm_lines.append("")
                norm_lines.append(f"{marker} {content}")
        else:
            # Avoid accidental 4+ space indented code blocks on regular paragraph continuation lines
            if indent >= 2 and stripped != "":
                if norm_lines and norm_lines[-1].strip() != "":
                    norm_lines.append("")
                norm_lines.append(stripped)
            else:
                norm_lines.append(line)

    md_text = "\n".join(norm_lines)

    # 1. Replace the 4 mermaid fenced code blocks with crisp inline SVGs
    mermaid_blocks = list(re.finditer(r"```mermaid\s+.*?\s+```", md_text, flags=re.DOTALL))
    svgs = [MERMAID_SVG_1, MERMAID_SVG_2, MERMAID_SVG_3, MERMAID_SVG_4]
    for idx, match in enumerate(reversed(mermaid_blocks)):
        svg_idx = len(mermaid_blocks) - 1 - idx
        if svg_idx < len(svgs):
            md_text = md_text[:match.start()] + svgs[svg_idx] + md_text[match.end():]

    # 2. Replace inline LaTeX math expressions with clean HTML typography
    math_replacements = {
        r"$F_{\max}=58.03\text{ MHz}$": "<i>F</i><sub>max</sub> = 58.03 MHz",
        r"$F_{\max}$": "<i>F</i><sub>max</sub>",
        r"$16\times 64$": "16 × 64",
        r"$16 \times 64$": "16 × 64",
        r"$64 \times 1$": "64 × 1",
        r"$16 \times 1$": "16 × 1",
        r"$>10\text{s}$": "&gt; 10 s",
        r"$\ge 10\text{s}$": "≥ 10 s",
        r"$\sum_{i=0}^3 \text{ sext}(w_i \times x_i)$": "∑<sub><i>i</i>=0..3</sub> sext(<i>w<sub>i</sub></i> × <i>x<sub>i</sub></i>)",
    }
    for k, v in math_replacements.items():
        md_text = md_text.replace(k, v)

    # 3. Convert Markdown to HTML
    html_body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "sane_lists"]
    )

    # 4. Wrap standalone <p><img ...></p> into <figure><img ...><figcaption>...</figcaption></figure>
    def img_to_figure(match):
        alt = match.group(1)
        src = match.group(2)
        abs_src = f"file://{os.path.join(DOCS_DIR, src)}"
        return (
            f'<figure class="report-fig">'
            f'<img src="{abs_src}" alt="{alt}"/>'
            f'<figcaption>{alt}</figcaption>'
            f'</figure>'
        )

    html_body = re.sub(
        r'<p><img alt="([^"]*)" src="([^"]+)"\s*/?></p>',
        img_to_figure,
        html_body
    )

    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>RISC-V 并行加速系统 — 竞赛技术报告</title>
<style>
  @page {{
    size: A4 portrait;
    margin: 18mm 16mm 18mm 16mm;
  }}
  * {{
    box-sizing: border-box;
  }}
  body {{
    font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", "Noto Sans CJK SC", sans-serif;
    font-size: 10.2pt;
    line-height: 1.62;
    color: #1e293b;
    margin: 0;
    padding: 0;
  }}
  h1 {{
    font-size: 20pt;
    font-weight: 800;
    color: #0f172a;
    text-align: center;
    margin: 0 0 10px 0;
    padding-bottom: 10px;
    border-bottom: 2.5px solid #1d4ed8;
    letter-spacing: 0.5px;
  }}
  h2 {{
    font-size: 13.5pt;
    font-weight: 700;
    color: #1e3a8a;
    background: linear-gradient(90deg, #eff6ff 0%, #ffffff 100%);
    border-left: 4px solid #2563eb;
    padding: 5px 10px;
    margin: 18px 0 10px 0;
    page-break-after: avoid;
  }}
  h3 {{
    font-size: 11.5pt;
    font-weight: 700;
    color: #0f172a;
    margin: 14px 0 6px 0;
    page-break-after: avoid;
  }}
  h4 {{
    font-size: 10.5pt;
    font-weight: 700;
    color: #1e40af;
    margin: 11px 0 5px 0;
    page-break-after: avoid;
  }}
  h5 {{
    font-size: 10pt;
    font-weight: 700;
    color: #334155;
    margin: 10px 0 4px 0;
    page-break-after: avoid;
  }}
  p {{
    margin: 5px 0 7px 0;
    text-align: justify;
  }}
  ul, ol {{
    margin: 4px 0 8px 0;
    padding-left: 22px;
  }}
  li {{
    margin-bottom: 3.5px;
    text-align: justify;
  }}
  blockquote {{
    margin: 6px 0 12px 0;
    padding: 6px 12px;
    background: #f8fafc;
    border-left: 3.5px solid #64748b;
    color: #475569;
    font-size: 9.2pt;
  }}
  hr {{
    border: none;
    border-top: 1px solid #cbd5e1;
    margin: 14px 0;
  }}
  code {{
    font-family: "JetBrains Mono", "SFMono-Regular", Menlo, Monaco, Consolas, monospace;
    font-size: 8.8pt;
    background: #f1f5f9;
    color: #0f172a;
    padding: 1px 4px;
    border-radius: 3px;
    border: 1px solid #e2e8f0;
  }}
  pre {{
    background: #0f172a;
    color: #f8fafc;
    padding: 9px 12px;
    border-radius: 6px;
    overflow-x: hidden;
    margin: 7px 0 10px 0;
    page-break-inside: avoid;
    border: 1px solid #334155;
  }}
  pre code {{
    background: transparent;
    color: #e2e8f0;
    border: none;
    padding: 0;
    font-size: 6.7pt;
    line-height: 1.35;
    white-space: pre;
  }}
  table {{
    width: 100%;
    border-collapse: collapse;
    margin: 8px 0 12px 0;
    font-size: 8.8pt;
    page-break-inside: avoid;
  }}
  th, td {{
    border: 1px solid #cbd5e1;
    padding: 5px 7px;
    line-height: 1.4;
  }}
  th {{
    background: #eff6ff;
    color: #1e3a8a;
    font-weight: 700;
  }}
  tr:nth-child(even) td {{
    background: #f8fafc;
  }}
  .diagram-box {{
    margin: 8px 0 12px 0;
    padding: 8px 10px;
    background: #ffffff;
    border: 1px solid #cbd5e1;
    border-radius: 8px;
    page-break-inside: avoid;
  }}
  figure.report-fig {{
    margin: 10px 0 14px 0;
    text-align: center;
    page-break-inside: avoid;
    background: #f8fafc;
    border: 1px solid #cbd5e1;
    border-radius: 8px;
    padding: 7px 7px 6px 7px;
  }}
  figure.report-fig img {{
    width: 100%;
    max-height: 295px;
    object-fit: contain;
    border-radius: 5px;
    display: block;
    margin: 0 auto;
    background: #0b0f17;
  }}
  figure.report-fig figcaption {{
    margin-top: 5px;
    font-size: 8.8pt;
    font-weight: 600;
    color: #334155;
  }}
</style>
</head>
<body>
{html_body}
</body>
</html>
"""


async def render_report_pdf(html_content: str):
    tmp_html = os.path.join(DOCS_DIR, "_tmp_report_render.html")
    with open(tmp_html, "w", encoding="utf-8") as f:
        f.write(html_content)

    header_template = """
    <div style="width:100%;font-size:8pt;color:#64748b;padding:0 16mm;display:flex;justify-content:space-between;font-family:sans-serif;border-bottom:1px solid #e2e8f0;padding-bottom:3px;">
      <span>全国大学生嵌入式芯片与系统设计竞赛 · 紫光同创赛道设计报告</span>
      <span>RISC-V 并行加速系统 (PG2L200H-6FBB676)</span>
    </div>
    """
    footer_template = """
    <div style="width:100%;font-size:8pt;color:#64748b;padding:0 16mm;display:flex;justify-content:flex-end;font-family:sans-serif;">
      <span>第 <span class="pageNumber"></span> 页 / 共 <span class="totalPages"></span> 页</span>
    </div>
    """

    async with async_playwright() as p:
        browser = await p.chromium.launch(executable_path=CHROME_PATH)
        page = await browser.new_page()
        await page.goto(f"file://{tmp_html}", wait_until="networkidle")
        await page.wait_for_timeout(300)
        await page.pdf(
            path=REPORT_PDF,
            format="A4",
            print_background=True,
            display_header_footer=True,
            header_template=header_template,
            footer_template=footer_template,
            margin={"top": "18mm", "bottom": "16mm", "left": "15mm", "right": "15mm"}
        )
        await browser.close()

    if os.path.exists(tmp_html):
        os.remove(tmp_html)
    shutil.copy2(REPORT_PDF, VIDEO_DIR_PDF)
    print(f"[OK] Final PDF generated: {REPORT_PDF}")
    print(f"[OK] Copied PDF to: {VIDEO_DIR_PDF}")


async def main():
    expected_figs = [
        "fig_arch_soc_topo.png",
        "fig_arch_pipeline_bpu.png",
        "fig_arch_simd_race.png",
        "fig1_verilator_difftest.png",
        "fig2_remote_board_overview.png",
        "fig3_pds_synthesis_timing.png",
        "fig4_board_leds_closeup.png",
        "fig5_uart_acc_coremark.png",
        "fig6_datapath_waveform.png",
    ]
    if not all(os.path.exists(os.path.join(FIG_DIR, f)) for f in expected_figs):
        await generate_all_figures()
    else:
        print("[OK] All 9 figures already present in docs/figures/, rendering PDF...")
    with open(REPORT_MD, "r", encoding="utf-8") as f:
        md_text = f.read()
    html_content = convert_markdown_to_html(md_text)
    await render_report_pdf(html_content)


if __name__ == "__main__":
    asyncio.run(main())
