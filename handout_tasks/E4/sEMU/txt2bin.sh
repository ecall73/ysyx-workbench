#!/bin/bash
# txt2bin.sh: Convert a text file with binary instructions to a binary file.
# Usage: ./txt2bin.sh input.txt output.bin

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_txt> <output_bin>"
    exit 1
fi

INPUT=$1
OUTPUT=$2

# 移除 # 后的注释内容，然后提取 8 位二进制指令并转换为二进制文件
sed 's/#.*//' "$INPUT" | grep -Eo "[01]{8}" | while read -r line; do
    printf "%02x" "$((2#$line))"
done | xxd -r -p > "$OUTPUT"
