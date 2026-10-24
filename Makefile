# 顶层 Makefile —— 所有验证入口
# 用法：make help

SHELL       := /bin/bash
BUILD       := build
GCC_DIR     := $(firstword $(wildcard tools/xpack-riscv-none-elf-gcc-*/bin))
CROSS       := $(GCC_DIR)/riscv-none-elf-

RTL_CORE    := rtl/core/core.v rtl/core/alu.v rtl/core/regfile.v rtl/core/imm_gen.v \
               rtl/core/decoder.v rtl/core/forwarding_unit.v rtl/core/hazard_unit.v \
               rtl/core/muldiv.v
RTL_SOC     := rtl/soc/uart_tx.v rtl/soc/uart_rx.v rtl/soc/wb_core_bridge.v \
               rtl/soc/wb_interconnect.v rtl/soc/wb_sram.v rtl/soc/wb_uart.v \
               rtl/soc/wb_clint.v rtl/soc/soc_top.v
SMOKE_SRCS  := rtl/soc/uart_tx.v rtl/soc/uart_rx.v platform/pango/smoke_top.v
FPGA_SRCS   := platform/pango/fpga_top.v $(RTL_SOC) $(RTL_CORE)

.PHONY: help lint smoke-sim test-core test-alu test-regfile test-immgen test-decoder test-forwarding test-hazard test-muldiv test-wb-interconnect test-wb-uart test-wb-clint test-soc test-c coremark fpga-fw unit-test isa-test difftest toolcheck clean

help:
	@echo "make toolcheck    - 检查本地工具链"
	@echo "make lint         - Verilator lint（零警告检查）"
	@echo "make fpga-fw      - 编译板级 CoreMark 固件并生成 platform/pango/firmware_words.hex"
	@echo "make unit-test    - 运行全部单元测试（含 ALU/译码/前推/冒险/Wishbone/UART/CLINT）"
	@echo "make test-core    - 运行 5 级流水线集成自检测试"
	@echo "make test-soc     - 运行 SoC 顶层软硬件集成冒烟测试 (SRAM/UART/CLINT)"
	@echo "make test-c       - 运行 S1c 裸机 C 语言运行时综合验收测试"
	@echo "make coremark     - 运行 EEMBC CoreMark 纯 RV32I 性能基线测试"
	@echo "make isa-test     - 运行官方 RV32UI 全套自动化指令集测试"
	@echo "make difftest     - 运行与 Spike 的差分比对验证"
	@echo "make smoke-sim    - 平台冒烟测试的仿真（UART banner + 回显）"
	@echo "make clean        - 清理 build/"

toolcheck:
	@verilator --version
	@iverilog -V 2>&1 | head -1
	@spike --help 2>&1 | head -1 || true
	@$(CROSS)gcc --version | head -1

lint:
	verilator --lint-only -Wall --top-module smoke_top $(SMOKE_SRCS)
	verilator --lint-only -Wall -Irtl/core --top-module core $(RTL_CORE)
	verilator --lint-only -Wall -Irtl/core -Irtl/soc --top-module soc_top $(RTL_SOC) $(RTL_CORE)
	verilator --lint-only -Wall -Irtl/core -Irtl/soc --top-module fpga_top $(FPGA_SRCS)

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

test-hazard:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_hazard_unit.vvp sim/unit/tb_hazard_unit.v rtl/core/hazard_unit.v
	vvp -n $(BUILD)/tb_hazard_unit.vvp | tee $(BUILD)/test_hazard.log
	@grep -q "ALL HAZARD UNIT TESTS PASSED" $(BUILD)/test_hazard.log

test-muldiv:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_muldiv.vvp sim/unit/tb_muldiv.v rtl/core/muldiv.v
	vvp -n $(BUILD)/tb_muldiv.vvp | tee $(BUILD)/test_muldiv.log
	@grep -q "ALL MULDIV TESTS PASSED" $(BUILD)/test_muldiv.log

test-wb-interconnect:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_wb_interconnect.vvp sim/unit/tb_wb_interconnect.v rtl/soc/wb_interconnect.v
	vvp -n $(BUILD)/tb_wb_interconnect.vvp | tee $(BUILD)/test_wb_interconnect.log
	@grep -q "ALL WB_INTERCONNECT TESTS PASSED" $(BUILD)/test_wb_interconnect.log

test-wb-uart:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_wb_uart.vvp sim/unit/tb_wb_uart.v rtl/soc/wb_uart.v rtl/soc/uart_tx.v rtl/soc/uart_rx.v
	vvp -n $(BUILD)/tb_wb_uart.vvp | tee $(BUILD)/test_wb_uart.log
	@grep -q "ALL WB_UART TESTS PASSED" $(BUILD)/test_wb_uart.log

test-wb-clint:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_wb_clint.vvp sim/unit/tb_wb_clint.v rtl/soc/wb_clint.v
	vvp -n $(BUILD)/tb_wb_clint.vvp | tee $(BUILD)/test_wb_clint.log
	@grep -q "ALL WB_CLINT TESTS PASSED" $(BUILD)/test_wb_clint.log

unit-test: test-alu test-regfile test-immgen test-decoder test-forwarding test-hazard test-muldiv \
           test-wb-interconnect test-wb-uart test-wb-clint

$(BUILD)/test_soc.hex: sim/soc/test_soc.S sim/isa/env/link.ld
	@mkdir -p $(BUILD)
	$(CROSS)gcc -march=rv32i_zicsr -mabi=ilp32 -static -nostdlib -nostartfiles -Tsim/isa/env/link.ld $< -o $(BUILD)/test_soc.elf
	$(CROSS)objcopy -O verilog $(BUILD)/test_soc.elf $@

test-soc: $(BUILD)/test_soc.hex
	@mkdir -p $(BUILD)
	iverilog -g2012 -Irtl/core -Irtl/soc -o $(BUILD)/tb_soc.vvp sim/soc/tb_soc.v $(RTL_SOC) $(RTL_CORE)
	vvp -n $(BUILD)/tb_soc.vvp +HEX=$< | tee $(BUILD)/test_soc.log
	@grep -q "SOC VERIFICATION PASSED" $(BUILD)/test_soc.log

SW_COMMON_SRCS := sw/common/crt0.S sw/common/uart.c sw/common/timer.c sw/common/str.c

$(BUILD)/test_c.hex: $(SW_COMMON_SRCS) sw/test_c/main.c sw/common/link.ld sw/common/soc.h sw/common/uart.h sw/common/timer.h sw/common/str.h
	@mkdir -p $(BUILD)
	$(CROSS)gcc -march=rv32im_zicsr -mabi=ilp32 -O2 -Wall -Wextra -ffreestanding -nostdlib -nostartfiles -Wl,--no-warn-rwx-segments -Isw/common -Tsw/common/link.ld $(SW_COMMON_SRCS) sw/test_c/main.c -lgcc -o $(BUILD)/test_c.elf
	$(CROSS)objcopy -O verilog $(BUILD)/test_c.elf $@

test-c: $(BUILD)/test_c.hex
	@mkdir -p $(BUILD)
	iverilog -g2012 -Irtl/core -Irtl/soc -o $(BUILD)/tb_soc.vvp sim/soc/tb_soc.v $(RTL_SOC) $(RTL_CORE)
	vvp -n $(BUILD)/tb_soc.vvp +HEX=$< +TIMEOUT=200000 | tee $(BUILD)/test_c.log
	@grep -q "\[S1c\] C Runtime OK! fib=55 mul=-69104 div=-2702 hex=0x00123456" $(BUILD)/test_c.log
	@grep -q "SOC VERIFICATION PASSED" $(BUILD)/test_c.log

COREMARK_SRCS  := $(wildcard sw/coremark/*.c)

$(BUILD)/coremark.hex: $(SW_COMMON_SRCS) $(COREMARK_SRCS) sw/common/link.ld sw/common/soc.h sw/common/uart.h sw/common/timer.h sw/coremark/coremark.h sw/coremark/core_portme.h
	@mkdir -p $(BUILD)
	$(CROSS)gcc -march=rv32im_zicsr -mabi=ilp32 -O2 -ffreestanding -nostdlib -nostartfiles -Wl,--no-warn-rwx-segments -Isw/common -Isw/coremark -DITERATIONS=2 -DFLAGS_STR="\"-march=rv32im_zicsr -mabi=ilp32 -O2 -lgcc\"" -Tsw/common/link.ld $(SW_COMMON_SRCS) sw/coremark/*.c -lgcc -o $(BUILD)/coremark.elf
	$(CROSS)objcopy -O verilog $(BUILD)/coremark.elf $@

coremark: $(BUILD)/coremark.hex
	@mkdir -p $(BUILD)
	iverilog -g2012 -Irtl/core -Irtl/soc -o $(BUILD)/tb_soc.vvp sim/soc/tb_soc.v $(RTL_SOC) $(RTL_CORE)
	vvp -n $(BUILD)/tb_soc.vvp +HEX=$(BUILD)/coremark.hex +TIMEOUT=10000000 | tee $(BUILD)/coremark.log
	@grep -q "Correct operation validated" $(BUILD)/coremark.log
	@grep -q "CoreMark/MHz" $(BUILD)/coremark.log
	@grep -q "SOC VERIFICATION PASSED" $(BUILD)/coremark.log

FPGA_FW_HEX    := platform/pango/firmware_words.hex

$(BUILD)/coremark_board.elf: $(SW_COMMON_SRCS) $(COREMARK_SRCS) sw/common/link.ld sw/common/soc.h sw/common/uart.h sw/common/timer.h sw/coremark/coremark.h sw/coremark/core_portme.h
	@mkdir -p $(BUILD)
	$(CROSS)gcc -march=rv32im_zicsr -mabi=ilp32 -O2 -ffreestanding -nostdlib -nostartfiles -Wl,--no-warn-rwx-segments -Isw/common -Isw/coremark -DFPGA_BOARD_LOOP -DITERATIONS=2 -DFLAGS_STR="\"-march=rv32im_zicsr -mabi=ilp32 -O2 -lgcc -DFPGA_BOARD_LOOP\"" -Tsw/common/link.ld $(SW_COMMON_SRCS) sw/coremark/*.c -lgcc -o $@

$(BUILD)/coremark_board.bin: $(BUILD)/coremark_board.elf
	$(CROSS)objcopy -O binary $< $@

$(FPGA_FW_HEX): $(BUILD)/coremark_board.bin sw/common/bin2words.py
	python3 sw/common/bin2words.py $< $@ 16384

fpga-fw: $(FPGA_FW_HEX)

test-core:
	@mkdir -p $(BUILD)
	iverilog -g2012 -Irtl/core -o $(BUILD)/tb_core_basic.vvp sim/core/tb_core_basic.v $(RTL_CORE)
	vvp -n $(BUILD)/tb_core_basic.vvp | tee $(BUILD)/test_core_basic.log
	@grep -q "5-STAGE RV32I CORE BASIC VERIFICATION PASSED" $(BUILD)/test_core_basic.log
	iverilog -g2012 -Irtl/core -o $(BUILD)/tb_core_hazard_mem.vvp sim/core/tb_core_hazard_mem.v $(RTL_CORE)
	vvp -n $(BUILD)/tb_core_hazard_mem.vvp | tee $(BUILD)/test_core_hazard_mem.log
	@grep -q "SW-LW HAZARD DIRECTED VERIFICATION PASSED" $(BUILD)/test_core_hazard_mem.log
	iverilog -g2012 -Irtl/core -o $(BUILD)/tb_probe_stallfwd.vvp sim/core/tb_probe_stallfwd.v $(RTL_CORE)
	vvp -n $(BUILD)/tb_probe_stallfwd.vvp | tee $(BUILD)/test_probe_stallfwd.log
	@grep -q "BUG-003 DIRECTED TEST PASSED" $(BUILD)/test_probe_stallfwd.log

smoke-sim:
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_smoke.vvp sim/smoke/tb_smoke.v $(SMOKE_SRCS)
	vvp -n $(BUILD)/tb_smoke.vvp | tee $(BUILD)/smoke.log
	@grep -q "ALL TESTS PASSED" $(BUILD)/smoke.log

$(BUILD)/tb_isa.vvp: sim/isa/tb_isa.v $(RTL_CORE)
	@mkdir -p $(BUILD)
	iverilog -g2012 -Irtl/core -o $@ $^

isa-test: $(BUILD)/tb_isa.vvp
	python3 sim/isa/run_isa_tests.py

difftest: $(BUILD)/tb_isa.vvp
	python3 sim/difftest/spike_diff.py

clean:
	rm -rf $(BUILD) obj_dir

