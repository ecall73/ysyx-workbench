TOPNAME = ysyxSoCFull
VERILATOR = verilator
VERILATOR_CFLAGS += -MMD --build -cc  \
				-O3 --x-assign fast --x-initial fast --noassert \
				-Wno-PINMISSING -Wno-WIDTHEXPAND \
				--trace --timescale "1ns/1ns" --no-timing

BUILD_DIR = ./build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)
YSYX_SOC_HOME ?= $(abspath ../ysyxSoC)

default: $(BIN)

$(shell mkdir -p $(BUILD_DIR))

# project source
VSRCS = $(shell find $(abspath ./vsrc) -name "*.v") \
	$(shell find $(YSYX_SOC_HOME)/perip -name "*.v") \
	$(YSYX_SOC_HOME)/build/ysyxSoCFull.v
CSRCS = $(shell find $(abspath ./csrc) -name "*.c" -or -name "*.cc" -or -name "*.cpp")

# rules for verilator
INC_PATH ?= $(abspath ./vsrc) \
	$(YSYX_SOC_HOME)/perip/uart16550/rtl \
	$(YSYX_SOC_HOME)/perip/spi/rtl
INCFLAGS = $(addprefix -I, $(INC_PATH)) -I$(abspath ./csrc) -I$(NEMU_HOME)/tools/capstone/repo/include
CFLAGS += $(INCFLAGS) -DTOP_NAME="\"V$(TOPNAME)\""

LDFLAGS += -lreadline $(NEMU_HOME)/tools/capstone/repo/libcapstone.a

$(BIN): $(VSRCS) $(CSRCS)
	$(VERILATOR) $(VERILATOR_CFLAGS) $(INCFLAGS) \
		--top-module $(TOPNAME) $^ \
		$(addprefix -CFLAGS , $(CFLAGS)) \
		$(addprefix -LDFLAGS , $(LDFLAGS)) \
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

run: $(BIN)
	@$^ $(ARGS)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: default run clean
