# -----------------------------------------------------------------------------
# build_smoke_top.tcl — PDS 2022.2-SP6.4 冒烟工程一键综合与比特流生成脚本
# -----------------------------------------------------------------------------

set SCRIPT_DIR [file dirname [info script]]
set REPO_ROOT  [file normalize "$SCRIPT_DIR/../.."]

set_arch -family Logos2 -device PG2L200H -package FBB676 -speedgrade -6

add_design "$REPO_ROOT/platform/pango/smoke_top.v"
add_design "$REPO_ROOT/rtl/soc/uart_tx.v"
add_design "$REPO_ROOT/rtl/soc/uart_rx.v"

add_constraint "$REPO_ROOT/platform/pango/pangu200k_mini.fdc"

compile -top_module smoke_top
synthesize -ads
dev_map
pnr
report_timing
gen_bit_stream -create_bit_file TRUE
