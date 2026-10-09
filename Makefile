# 顶层 Makefile —— 所有验证入口
# 用法：make help

SHELL       := /bin/bash
BUILD       := build
GCC_DIR     := $(firstword $(wildcard tools/xpack-riscv-none-elf-gcc-*/bin))
CROSS       := $(GCC_DIR)/riscv-none-elf-

RTL_SOC     := rtl/soc/uart_tx.v rtl/soc/uart_rx.v
SMOKE_SRCS  := $(RTL_SOC) platform/pango/smoke_top.v

.PHONY: help lint smoke-sim toolcheck clean

help:
	@echo "make toolcheck   - 检查本地工具链"
	@echo "make lint        - Verilator lint（零警告）"
	@echo "make smoke-sim   - 平台冒烟测试的仿真（UART banner + 回显）"
	@echo "make clean       - 清理 build/"

toolcheck:
	@verilator --version
	@iverilog -V 2>&1 | head -1
	@spike --help 2>&1 | head -1 || true
	@$(CROSS)gcc --version | head -1

lint:
	verilator --lint-only -Wall --top-module smoke_top $(SMOKE_SRCS)

smoke-sim:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_smoke.vvp sim/smoke/tb_smoke.v $(SMOKE_SRCS)
	vvp -n $(BUILD)/tb_smoke.vvp | tee $(BUILD)/smoke.log
	@grep -q "ALL TESTS PASSED" $(BUILD)/smoke.log

clean:
	rm -rf $(BUILD) obj_dir
