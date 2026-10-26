#!/usr/bin/env python3
"""
run_isa_tests.py — RISC-V 官方 RV32UI + RV32UM 测试集批量执行与汇总脚本

功能：
  1. 编译全部 sim/isa/src/rv32{ui,um}-p-*.S 到 build/isa/*.hex
     （rv32ui 用 -march=rv32i_zicsr，rv32um 用 -march=rv32im_zicsr）
  2. 调用 vvp 执行 tb_isa.vvp 仿真
  3. 收集并格式化展示每个用例的 PASS / FAIL / TIMEOUT 状态与周期数
  4. 生成总结报告，若有失败则返回非零退出码
"""

import os
import sys
import glob
import subprocess
import argparse
import time

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
GCC_BIN = os.path.join(PROJECT_ROOT, "tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin")
CROSS_GCC = os.path.join(GCC_BIN, "riscv-none-elf-gcc")
CROSS_OBJCOPY = os.path.join(GCC_BIN, "riscv-none-elf-objcopy")

BUILD_ISA = os.path.join(PROJECT_ROOT, "build/isa")
SRC_DIR = os.path.join(PROJECT_ROOT, "sim/isa/src")
ENV_DIR = os.path.join(PROJECT_ROOT, "sim/isa/env")
MACROS_DIR = os.path.join(PROJECT_ROOT, "sim/isa/macros")
TB_VVP = os.path.join(PROJECT_ROOT, "build/tb_isa.vvp")


TEST_SUITES = ("rv32ui", "rv32um")


def march_for(name):
    """rv32ui 保持纯 RV32I 编译，rv32um 才开启 M 扩展"""
    return "rv32im_zicsr" if name.startswith("rv32um-") else "rv32i_zicsr"


def resolve_test_name(target):
    """'add' -> 'rv32ui-p-add'，'mul' -> 'rv32um-p-mul'；完整名原样返回"""
    if "-p-" in target:
        return [target]
    return [f"{suite}-p-{target}" for suite in TEST_SUITES]


def compile_test(s_path, elf_path, hex_path):
    """编译汇编源文件生成 ELF 与 Hex"""
    name = os.path.splitext(os.path.basename(s_path))[0]
    cmd_gcc = [
        CROSS_GCC,
        f"-march={march_for(name)}",
        "-mabi=ilp32",
        "-static",
        "-nostdlib",
        "-nostartfiles",
        f"-I{ENV_DIR}",
        f"-I{MACROS_DIR}",
        f"-T{os.path.join(ENV_DIR, 'link.ld')}",
        s_path,
        "-o",
        elf_path,
    ]
    res = subprocess.run(cmd_gcc, capture_output=True, text=True)
    if res.returncode != 0:
        return False, f"GCC error: {res.stderr}"

    cmd_objcopy = [CROSS_OBJCOPY, "-O", "verilog", elf_path, hex_path]
    res = subprocess.run(cmd_objcopy, capture_output=True, text=True)
    if res.returncode != 0:
        return False, f"Objcopy error: {res.stderr}"

    return True, ""


def run_single_test(hex_path, trace_path=None, timeout=25000):
    """运行单项测试并解析输出"""
    cmd = ["vvp", TB_VVP, f"+HEX={hex_path}", f"+TIMEOUT={timeout}"]
    if trace_path:
        cmd.append(f"+TRACE={trace_path}")

    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        stdout = res.stdout
    except subprocess.TimeoutExpired:
        return "TIMEOUT", 0, 0, "Simulation host process timeout"

    cycles = 0
    instret = 0
    fail_case = 0
    fail_pc = ""

    for line in stdout.splitlines():
        if "[ISA-PASS]" in line:
            # [ISA-PASS] cycles=492 instret=456
            parts = line.strip().split()
            for p in parts:
                if p.startswith("cycles="):
                    cycles = int(p.split("=")[1])
                elif p.startswith("instret="):
                    instret = int(p.split("=")[1])
            return "PASS", cycles, instret, ""
        elif "[ISA-FAIL]" in line:
            # [ISA-FAIL] test_num=2 cycles=100 pc=0x...
            parts = line.strip().split()
            for p in parts:
                if p.startswith("test_num="):
                    fail_case = int(p.split("=")[1])
                elif p.startswith("cycles="):
                    cycles = int(p.split("=")[1])
                elif p.startswith("pc="):
                    fail_pc = p.split("=")[1]
            return "FAIL", cycles, instret, f"Failed case #{fail_case} at {fail_pc}"
        elif "[ISA-TIMEOUT]" in line:
            return "TIMEOUT", cycles, instret, line.strip()

    return "ERROR", 0, 0, f"Unknown output: {stdout[:200]}"


def main():
    parser = argparse.ArgumentParser(description="Run RISC-V ISA rv32ui/rv32um tests")
    parser.add_argument("test", nargs="?", default=None, help="Run specific test (e.g., add, mul, rv32ui-p-add, rv32um-p-mul)")
    parser.add_argument("--trace", action="store_true", help="Generate commit trace file")
    args = parser.parse_args()

    os.makedirs(BUILD_ISA, exist_ok=True)

    if not os.path.exists(TB_VVP):
        print(f"[ERROR] Testbench binary {TB_VVP} not found! Run make first.")
        sys.exit(1)

    s_files = []
    for suite in TEST_SUITES:
        s_files += sorted(glob.glob(os.path.join(SRC_DIR, f"{suite}-p-*.S")))
    if not s_files:
        print(f"[ERROR] No test sources found in {SRC_DIR}")
        sys.exit(1)

    if args.test:
        targets = resolve_test_name(args.test)
        s_files = [f for f in s_files if os.path.splitext(os.path.basename(f))[0] in targets]
        if not s_files:
            print(f"[ERROR] Test {args.test} not found!")
            sys.exit(1)

    total_tests = len(s_files)
    passed_count = 0
    failed_count = 0
    timeout_count = 0
    results = []

    print(f"=== Starting RV32UI/RV32UM ISA Tests ({total_tests} test cases) ===\n")
    start_time = time.time()

    for idx, s_path in enumerate(s_files, 1):
        name = os.path.splitext(os.path.basename(s_path))[0]
        elf_path = os.path.join(BUILD_ISA, f"{name}.elf")
        hex_path = os.path.join(BUILD_ISA, f"{name}.hex")
        trace_path = os.path.join(BUILD_ISA, f"{name}.trace") if args.trace else None

        ok, err = compile_test(s_path, elf_path, hex_path)
        if not ok:
            print(f"[{idx:2d}/{total_tests:2d}] {name:<22} ... COMPILE ERROR: {err}")
            failed_count += 1
            results.append((name, "COMPILE_ERROR", 0, 0, err))
            continue

        status, cycles, instret, detail = run_single_test(hex_path, trace_path)

        if status == "PASS":
            passed_count += 1
            cpi = f", CPI={cycles/instret:.2f}" if instret > 0 else ""
            print(f"[{idx:2d}/{total_tests:2d}] {name:<22} ... PASS ({cycles:4d} cycles{cpi})")
        elif status == "FAIL":
            failed_count += 1
            print(f"[{idx:2d}/{total_tests:2d}] {name:<22} ... FAIL ({detail})")
        elif status == "TIMEOUT":
            timeout_count += 1
            print(f"[{idx:2d}/{total_tests:2d}] {name:<22} ... TIMEOUT ({detail})")
        else:
            failed_count += 1
            print(f"[{idx:2d}/{total_tests:2d}] {name:<22} ... ERROR ({detail})")

        results.append((name, status, cycles, instret, detail))

    elapsed = time.time() - start_time
    print("\n" + "=" * 55)
    print(f"SUMMARY: {passed_count}/{total_tests} PASSED ({failed_count} FAILED, {timeout_count} TIMEOUT)")
    print(f"Total Elapsed Time: {elapsed:.2f}s")
    print("=" * 55)

    if failed_count > 0 or timeout_count > 0:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
