CC = gcc
CFLAGS = -Wall -O2

# 可执行文件名称
TARGET = semu

# 源文件和目标二进制文件
SRC = semu.c
TXT_FILES = $(wildcard *.txt)
BIN_FILES = $(TXT_FILES:.txt=.bin)

# 脚本路径
TXT2BIN = ./txt2bin.sh

.PHONY: all clean run

# 默认构建所有内容
all: $(TARGET) $(BIN_FILES)

# 编译 semu
$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $@ $^

# 转换 txt 到 bin
%.bin: %.txt $(TXT2BIN)
	@chmod +x $(TXT2BIN)
	$(TXT2BIN) $< $@

# 运行默认的 a.bin
run: all
	./$(TARGET) a.bin

# 清理构建产物
clean:
	rm -f $(TARGET) $(BIN_FILES)
