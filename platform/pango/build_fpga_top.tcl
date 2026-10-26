# -----------------------------------------------------------------------------
# build_fpga_top.tcl — PDS 2022.2-SP6.4 命令行一键综合与比特流生成脚本
#
# 用法 (Windows CMD / PowerShell，确保路径不含中文与空格)：
#   1. 将 platform/pango/firmware_words.hex 复制到 <work_dir> 根目录下
#   2. 在仓库根目录下运行（或在脚本中调整相对路径）：
#      set PANGO_LICENSE_FILE=C:\pango\license\your_license.lic
#      C:\pango\PDS_2022.2-SP6.4\bin\pds_shell.exe -work_dir <work_dir> -file platform/pango/build_fpga_top.tcl
#
# 注意事项：
#   - 严禁调用 save_project（批处理模式下会自动按脚本名创建 .pds 工程）
#   - 必须使用 synthesize -ads 调用内置 ADS 综合器（默认会寻找未安装的 Synplify）
# -----------------------------------------------------------------------------

set SCRIPT_DIR [file dirname [info script]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/../.."]

set_arch -family Logos2 -device PG2L200H -package FBB676 -speedgrade -6

# 板级顶层
add_design "$REPO_ROOT/platform/pango/fpga_top.v"

# CPU 核心
add_design "$REPO_ROOT/rtl/core/core.v"
add_design "$REPO_ROOT/rtl/core/alu.v"
add_design "$REPO_ROOT/rtl/core/decoder.v"
add_design "$REPO_ROOT/rtl/core/imm_gen.v"
add_design "$REPO_ROOT/rtl/core/regfile.v"
add_design "$REPO_ROOT/rtl/core/forwarding_unit.v"
add_design "$REPO_ROOT/rtl/core/hazard_unit.v"
add_design "$REPO_ROOT/rtl/core/bpu.v"
add_design "$REPO_ROOT/rtl/core/muldiv.v"

# SoC 总线与外设
add_design "$REPO_ROOT/rtl/soc/soc_top.v"
add_design "$REPO_ROOT/rtl/soc/wb_sram.v"
add_design "$REPO_ROOT/rtl/soc/wb_core_bridge.v"
add_design "$REPO_ROOT/rtl/soc/wb_interconnect.v"
add_design "$REPO_ROOT/rtl/soc/wb_uart.v"
add_design "$REPO_ROOT/rtl/soc/wb_clint.v"
add_design "$REPO_ROOT/rtl/soc/uart_tx.v"
add_design "$REPO_ROOT/rtl/soc/uart_rx.v"

# 硬件加速器
add_design "$REPO_ROOT/rtl/acc/wb_mac_acc.v"

# 约束文件（默认 200K-MINI 核心板；若跑远程实验箱可改为 pangu_experiment_box.fdc）
add_constraint "$REPO_ROOT/platform/pango/pangu200k_mini.fdc"

compile -top_module fpga_top -include_path "$REPO_ROOT/rtl/core"
synthesize -ads
dev_map
pnr
report_timing
gen_bit_stream -create_bit_file TRUE
