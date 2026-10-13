# 顶层 Makefile —— 所有验证入口
# 用法：make help

SHELL       := /bin/bash
BUILD       := build
GCC_DIR     := $(firstword $(wildcard tools/xpack-riscv-none-elf-gcc-*/bin))
CROSS       := $(GCC_DIR)/riscv-none-elf-

RTL_CORE    := rtl/core/alu.v rtl/core/regfile.v
RTL_SOC     := rtl/soc/uart_tx.v rtl/soc/uart_rx.v
SMOKE_SRCS  := $(RTL_SOC) platform/pango/smoke_top.v

.PHONY: help lint smoke-sim test-alu test-regfile unit-test toolcheck clean

help:
	@echo "make toolcheck    - 检查本地工具链"
	@echo "make lint         - Verilator lint（零警告检查）"
	@echo "make test-alu     - 运行 ALU 单元测试"
	@echo "make test-regfile - 运行通用寄存器堆单元测试"
	@echo "make test-immgen  - 运行立即数生成单元测试"
	@echo "make unit-test    - 运行全部单元测试"
	@echo "make smoke-sim    - 平台冒烟测试的仿真（UART banner + 回显）"
	@echo "make clean        - 清理 build/"

toolcheck:
	@verilator --version
	@iverilog -V 2>&1 | head -1
	@spike --help 2>&1 | head -1 || true
	@$(CROSS)gcc --version | head -1

lint:
	verilator --lint-only -Wall --top-module smoke_top $(SMOKE_SRCS)
	verilator --lint-only -Wall -Irtl/core rtl/core/alu.v
	verilator --lint-only -Wall rtl/core/regfile.v
	verilator --lint-only -Wall rtl/core/imm_gen.v
	verilator --lint-only -Wall -Irtl/core rtl/core/decoder.v
	verilator --lint-only -Wall rtl/core/forwarding_unit.v

test-alu:
	@mkdir -p $(BUILD)
	iverilog -g2012 -Irtl/core -o $(BUILD)/tb_alu.vvp sim/unit/tb_alu.v rtl/core/alu.v
	vvp -n $(BUILD)/tb_alu.vvp | tee $(BUILD)/test_alu.log
	@grep -q "ALL ALU TESTS PASSED" $(BUILD)/test_alu.log

test-regfile:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_regfile.vvp sim/unit/tb_regfile.v rtl/core/regfile.v
	vvp -n $(BUILD)/tb_regfile.vvp | tee $(BUILD)/test_regfile.log
	@grep -q "ALL REGFILE TESTS PASSED" $(BUILD)/test_regfile.log

test-immgen:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_imm_gen.vvp sim/unit/tb_imm_gen.v rtl/core/imm_gen.v
	vvp -n $(BUILD)/tb_imm_gen.vvp | tee $(BUILD)/test_imm_gen.log
	@grep -q "ALL IMM_GEN TESTS PASSED" $(BUILD)/test_imm_gen.log

test-decoder:
	@mkdir -p $(BUILD)
	iverilog -g2012 -Irtl/core -o $(BUILD)/tb_decoder.vvp sim/unit/tb_decoder.v rtl/core/decoder.v
	vvp -n $(BUILD)/tb_decoder.vvp | tee $(BUILD)/test_decoder.log
	@grep -q "ALL DECODER TESTS PASSED" $(BUILD)/test_decoder.log

test-forwarding:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_forwarding_unit.vvp sim/unit/tb_forwarding_unit.v rtl/core/forwarding_unit.v
	vvp -n $(BUILD)/tb_forwarding_unit.vvp | tee $(BUILD)/test_forwarding.log
	@grep -q "ALL FORWARDING UNIT TESTS PASSED" $(BUILD)/test_forwarding.log

unit-test: test-alu test-regfile test-immgen test-decoder test-forwarding

smoke-sim:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_smoke.vvp sim/smoke/tb_smoke.v $(SMOKE_SRCS)
	vvp -n $(BUILD)/tb_smoke.vvp | tee $(BUILD)/smoke.log
	@grep -q "ALL TESTS PASSED" $(BUILD)/smoke.log

clean:
	rm -rf $(BUILD) obj_dir
