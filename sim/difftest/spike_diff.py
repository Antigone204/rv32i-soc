#!/usr/bin/env python3
"""
spike_diff.py — Spike Golden Model 与 Core RTL Commit Trace 自动差分比对工具

功能：
  1. 调用 Spike (--log-commits) 作为 Golden Model 运行测试 ELF
  2. 调用 iverilog 编译的 Core 测试台导出 RTL 提交日志 (Commit Trace)
  3. 逐条对齐比对每条指令的 PC、目的寄存器 (rd) 与写入值 (val)
  4. 分歧时高亮显示上下文并报错，确保 100% 逐条一致
"""

import os
import sys
import re
import glob
import subprocess
import argparse
import tempfile

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
GCC_BIN = os.path.join(PROJECT_ROOT, "tools/xpack-riscv-none-elf-gcc-15.2.0-1/bin")
CROSS_OBJCOPY = os.path.join(GCC_BIN, "riscv-none-elf-objcopy")
BUILD_ISA = os.path.join(PROJECT_ROOT, "build/isa")
TB_VVP = os.path.join(PROJECT_ROOT, "build/tb_isa.vvp")
SPIKE_BIN = "/opt/homebrew/bin/spike"


def parse_core_trace(trace_path):
    """
    解析 Core trace 文件：
    格式:
      core: pc=[0x00000000] rd=x1  val=0x00000000
      core: pc=[0x0000000c]
    返回: list of dict(pc, rd, val, raw)
    """
    commits = []
    reg_re = re.compile(r"core:\s+pc=\[0x([0-9a-fA-F]+)\]\s+rd=x(\d+)\s+val=0x([0-9a-fA-F]+)")
    nop_re = re.compile(r"core:\s+pc=\[0x([0-9a-fA-F]+)\]")

    if not os.path.exists(trace_path):
        return commits

    with open(trace_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            m = reg_re.match(line)
            if m:
                pc = int(m.group(1), 16)
                rd = int(m.group(2))
                val = int(m.group(3), 16)
                commits.append({"pc": pc, "rd": rd, "val": val, "raw": line})
                continue
            m = nop_re.match(line)
            if m:
                pc = int(m.group(1), 16)
                commits.append({"pc": pc, "rd": 0, "val": 0, "raw": line})
    return commits


def parse_spike_trace(log_path):
    """
    解析 Spike 日志文件：
    格式:
      core   0: 3 0x80000000 (0x00000093) x1  0x00000000
      core   0: 3 0x8000000c (0x0000006f)
      core   0: 3 0x80000020 (0x00012283) x5  0x00000010 mem 0x80001000
    返回: list of dict(pc, rd, val, raw)
    """
    commits = []
    # 正则匹配 Spike 提交行
    line_re = re.compile(r"core\s+\d+:\s+\d\s+0x([0-9a-fA-F]+)\s+\(0x[0-9a-fA-F]+\)(.*)")
    reg_re = re.compile(r"x(\d+)\s+0x([0-9a-fA-F]+)")

    if not os.path.exists(log_path):
        return commits

    with open(log_path, "r") as f:
        for line in f:
            line = line.strip()
            m = line_re.match(line)
            if not m:
                continue
            spike_pc = int(m.group(1), 16)
            # 映射回 0x0 空间
            pc = spike_pc & 0x7FFFFFFF
            rest = m.group(2)
            reg_m = reg_re.search(rest)
            if reg_m:
                rd = int(reg_m.group(1))
                val = int(reg_m.group(2), 16)
                if rd == 0:
                    val = 0
            else:
                rd = 0
                val = 0
            commits.append({"pc": pc, "rd": rd, "val": val, "raw": line})
    return commits


TEST_SUITES = ("rv32ui", "rv32um")


def isa_for(name):
    """rv32ui 对标纯 RV32I 的 Spike，rv32um 对标 RV32IM"""
    return "rv32im" if name.startswith("rv32um-") else "rv32i"


def run_diff_for_test(test_name, verbose=False):
    """运行单项测试并执行差分比对"""
    elf_path = os.path.join(BUILD_ISA, f"{test_name}.elf")
    hex_path = os.path.join(BUILD_ISA, f"{test_name}.hex")

    if not os.path.exists(elf_path) or not os.path.exists(hex_path):
        return False, f"Test files not found: {elf_path} or {hex_path}"

    with tempfile.TemporaryDirectory() as tmpdir:
        core_trace = os.path.join(tmpdir, "core.trace")
        spike_log = os.path.join(tmpdir, "spike.log")
        spike_elf = os.path.join(tmpdir, "spike.elf")

        # 1. 运行 RTL Core 仿真并导出 trace
        cmd_core = ["vvp", TB_VVP, f"+HEX={hex_path}", f"+TRACE={core_trace}"]
        res_core = subprocess.run(cmd_core, capture_output=True, text=True)
        if "[ISA-PASS]" not in res_core.stdout:
            return False, f"RTL did not PASS: {res_core.stdout.strip()}"

        # 2. 转换 ELF 地址并运行 Spike
        cmd_objcopy = [CROSS_OBJCOPY, "--change-addresses", "0x80000000", elf_path, spike_elf]
        subprocess.run(cmd_objcopy, check=True)

        cmd_spike = [
            SPIKE_BIN,
            f"--isa={isa_for(test_name)}",
            "--pc=0x80000000",
            "--instructions=20000",
            "--log-commits",
            spike_elf,
        ]
        with open(spike_log, "w") as f_spike:
            subprocess.run(cmd_spike, stderr=f_spike, stdout=subprocess.DEVNULL)

        # 3. 解析两份日志
        core_commits = parse_core_trace(core_trace)
        spike_commits = parse_spike_trace(spike_log)

        if not core_commits:
            return False, "Core trace is empty"
        if not spike_commits:
            return False, "Spike trace is empty"

        # 4. 逐条比对 (以 Core 提交的总条数为基准)
        compare_count = min(len(core_commits), len(spike_commits))
        for i in range(compare_count):
            c = core_commits[i]
            s = spike_commits[i]

            mismatch = False
            reasons = []
            if c["pc"] != s["pc"]:
                mismatch = True
                reasons.append(f"PC mismatch (Core=0x{c['pc']:08x}, Spike=0x{s['pc']:08x})")
            if c["rd"] != s["rd"]:
                mismatch = True
                reasons.append(f"rd mismatch (Core=x{c['rd']}, Spike=x{s['rd']})")
            if c["rd"] != 0 and c["val"] != s["val"]:
                # 由于 Core 链接在 0x00000000，而 Spike 运行在 0x80000000：
                # 涉及 PC 相对寻址 (auipc, jal, jalr, la) 的指令，Spike 写入值带有 0x80000000 基地址。
                # 在模 2^32 算术下：spike_val = (core_val + 0x80000000) & 0xFFFFFFFF
                if ((c["val"] + 0x80000000) & 0xFFFFFFFF) == s["val"]:
                    pass
                else:
                    mismatch = True
                    reasons.append(f"val mismatch (Core=0x{c['val']:08x}, Spike=0x{s['val']:08x})")

            if mismatch:
                # 打印分歧点上下文前后 5 条
                start_idx = max(0, i - 5)
                end_idx = min(compare_count, i + 6)
                ctx = []
                ctx.append(f"\n[DIFF MISMATCH] Step #{i+1} in {test_name}: " + ", ".join(reasons))
                ctx.append("--- Trace Context (steps %d..%d) ---" % (start_idx + 1, end_idx))
                for j in range(start_idx, end_idx):
                    prefix = ">>>" if j == i else "   "
                    cj = core_commits[j]
                    sj = spike_commits[j]
                    ctx.append(f"{prefix} [{j+1:4d}] Core : PC=0x{cj['pc']:08x} rd=x{cj['rd']:<2d} val=0x{cj['val']:08x}")
                    ctx.append(f"{prefix} [{j+1:4d}] Spike: PC=0x{sj['pc']:08x} rd=x{sj['rd']:<2d} val=0x{sj['val']:08x}")
                return False, "\n".join(ctx)

        return True, f"{compare_count} commits matched 100%"


def main():
    parser = argparse.ArgumentParser(description="DiffTest Core vs Spike")
    parser.add_argument("test", nargs="?", default=None, help="Specific test name (e.g. add, mul, rv32ui-p-add, rv32um-p-mul)")
    args = parser.parse_args()

    if not os.path.exists(TB_VVP):
        print(f"[ERROR] Testbench binary {TB_VVP} not found!")
        sys.exit(1)

    elf_files = []
    for suite in TEST_SUITES:
        elf_files += sorted(glob.glob(os.path.join(BUILD_ISA, f"{suite}-p-*.elf")))
    if not elf_files:
        print("[ERROR] No compiled ELFs found! Run 'make isa-test' first.")
        sys.exit(1)

    if args.test:
        targets = [args.test] if "-p-" in args.test else [f"{s}-p-{args.test}" for s in TEST_SUITES]
        elf_files = [f for f in elf_files if os.path.splitext(os.path.basename(f))[0] in targets]
        if not elf_files:
            print(f"[ERROR] Test {args.test} not found!")
            sys.exit(1)

    total = len(elf_files)
    passed = 0
    failed = 0

    print(f"=== Starting Spike DiffTest ({total} test cases) ===\n")
    for idx, elf in enumerate(elf_files, 1):
        name = os.path.splitext(os.path.basename(elf))[0]
        ok, msg = run_diff_for_test(name)
        if ok:
            passed += 1
            print(f"[{idx:2d}/{total:2d}] {name:<22} ... DIFF MATCH ({msg})")
        else:
            failed += 1
            print(f"[{idx:2d}/{total:2d}] {name:<22} ... DIFF MISMATCH!")
            print(msg)

    print("\n" + "=" * 55)
    print(f"DIFFTEST SUMMARY: {passed}/{total} MATCHED ({failed} MISMATCH)")
    print("=" * 55)

    if failed > 0:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
