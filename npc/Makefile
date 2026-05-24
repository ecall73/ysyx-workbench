TOPNAME = ysyxSoCFull
VERILATOR = verilator
# GCC 11 may ICE on some Verilator-generated PCH compilations when ccache is
# injected by verilated.mk. Keep objcache disabled by default for stability.
# To re-enable cache manually: `make ... OBJCACHE=ccache`.
OBJCACHE ?=
export OBJCACHE
VERILATOR_CFLAGS += -MMD --build -cc  \
				-O3 --x-assign fast --x-initial fast --noassert \
				-Wno-PINMISSING -Wno-WIDTHEXPAND \
				--trace --timescale "1ns/1ns" --no-timing --autoflush

BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)
YSYX_SOC_HOME ?= $(abspath ../ysyxSoC)
NVBOARD_HOME ?= $(abspath ../nvboard)
NXDC_FILES = $(abspath ./constr/ysyxSoCFull.nxdc)
SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)
CHAR_TEST_DIR = $(abspath ./tests)
CHAR_TEST_SRC = $(CHAR_TEST_DIR)/char-test.c
CHAR_TEST_LD = $(CHAR_TEST_DIR)/char-test.ld
CHAR_TEST_ELF = $(BUILD_DIR)/char-test.elf
CHAR_TEST_BIN = $(BUILD_DIR)/char-test.bin
RV_CC ?= riscv64-linux-gnu-gcc
RV_OBJCOPY ?= riscv64-linux-gnu-objcopy
CHAR_TEST_CFLAGS = -march=rv32e_zicsr -mabi=ilp32e -O2 -ffreestanding -fno-pic -fno-builtin -fno-stack-protector -fdata-sections -ffunction-sections -Wall -Werror
CHAR_TEST_LDFLAGS = -nostdlib -static -Wl,-melf32lriscv -Wl,-T,$(CHAR_TEST_LD) -Wl,--gc-sections -Wl,-e,_start

default: $(BIN)

$(shell mkdir -p $(BUILD_DIR))

# constraint file -> NVBoard auto bind source
$(SRC_AUTO_BIND): $(NXDC_FILES)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

# project source
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v") \
	$(shell find $(YSYX_SOC_HOME)/perip -name "*.v") \
	$(YSYX_SOC_HOME)/build/ysyxSoCFull.v
VHDRS = $(shell find $(abspath ./vsrc) -name "*.vh" -o -name "*.svh") \
	$(shell find $(YSYX_SOC_HOME)/perip -name "*.vh" -o -name "*.svh")
CSRCS = $(shell find $(abspath ./csrc) \( -name "*.c" -o -name "*.cc" -o -name "*.cpp" \))
CSRCS += $(SRC_AUTO_BIND)
CHDRS = $(shell find $(abspath ./csrc) \( -name "*.h" -o -name "*.hpp" \))
NPC_DEPS = $(VSRCS) $(VHDRS) $(CSRCS) $(CHDRS) $(CHAR_TEST_BIN) $(NVBOARD_ARCHIVE) Makefile

# rules for verilator
INC_PATH := $(abspath ./vsrc) \
	$(YSYX_SOC_HOME)/perip/uart16550/rtl \
	$(YSYX_SOC_HOME)/perip/spi/rtl
# rules for NVBoard
include $(NVBOARD_HOME)/scripts/nvboard.mk

INCFLAGS = $(addprefix -I, $(INC_PATH)) -I$(abspath ./csrc) -I$(NEMU_HOME)/tools/capstone/repo/include
CFLAGS += $(INCFLAGS) -DTOP_NAME="\"V$(TOPNAME)\""

LDFLAGS += -lreadline $(NEMU_HOME)/tools/capstone/repo/libcapstone.a

$(CHAR_TEST_ELF): $(CHAR_TEST_SRC) $(CHAR_TEST_LD)
	@echo + CC "->" $(CHAR_TEST_ELF)
	@$(RV_CC) $(CHAR_TEST_CFLAGS) $(CHAR_TEST_SRC) -o $(CHAR_TEST_ELF) $(CHAR_TEST_LDFLAGS)

$(CHAR_TEST_BIN): $(CHAR_TEST_ELF)
	@echo + OBJCOPY "->" $(CHAR_TEST_BIN)
	@$(RV_OBJCOPY) -O binary $(CHAR_TEST_ELF) $(CHAR_TEST_BIN)

$(BIN): $(NPC_DEPS)
	$(VERILATOR) $(VERILATOR_CFLAGS) $(INCFLAGS) \
		--top-module $(TOPNAME) $(VSRCS) $(CSRCS) $(CHAR_TEST_BIN) $(NVBOARD_ARCHIVE) \
		$(addprefix -CFLAGS , $(CFLAGS)) \
		$(addprefix -LDFLAGS , $(LDFLAGS)) \
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

run: $(BIN)
	@$^ $(ARGS)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: default run clean
