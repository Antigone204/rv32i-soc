#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# bin2words.py — 将 RISC-V ELF/BIN 转换为 32-bit 字格式 Hex 镜像 (供 FPGA BRAM $readmemh 使用)
#
# 功能：
#   1. 读取 objcopy -O binary 导出的原始二进制镜像；
#   2. 按小端序将每 4 字节打包为 1 个 32 位十六进制字 (如 00000013)；
#   3. 输出指定字数 (默认 16384 行 = 64 KB)，不足部分自动填充 NOP (00000013)；
#   4. 若输入大小超出容量则报错。
# -----------------------------------------------------------------------------

import sys
import struct
import os

def bin2words(input_bin, output_hex, words_count=16384):
    with open(input_bin, "rb") as f:
        data = f.read()

    pad_len = (4 - (len(data) % 4)) % 4
    if pad_len != 0:
        data += b'\x00' * pad_len

    num_words = len(data) // 4
    if num_words > words_count:
        raise ValueError(
            f"Binary size {len(data)} bytes ({num_words} words) exceeds SRAM capacity {words_count} words ({words_count * 4} bytes)"
        )

    words = struct.unpack(f"<{num_words}I", data)

    os.makedirs(os.path.dirname(os.path.abspath(output_hex)), exist_ok=True)
    with open(output_hex, "w") as f:
        for w in words:
            f.write(f"{w:08x}\n")
        # 剩余未使用的 SRAM 空间填充 NOP (addi x0, x0, 0 -> 0x00000013)
        nop_str = "00000013\n"
        for _ in range(words_count - num_words):
            f.write(nop_str)

    print(f"[bin2words] Converted {input_bin} ({len(data)} bytes, {num_words} words) -> {output_hex} ({words_count} lines)")

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.bin> <output.hex> [words_count]", file=sys.stderr)
        sys.exit(1)

    input_bin = sys.argv[1]
    output_hex = sys.argv[2]
    words_count = int(sys.argv[3]) if len(sys.argv) > 3 else 16384

    bin2words(input_bin, output_hex, words_count)

if __name__ == "__main__":
    main()
