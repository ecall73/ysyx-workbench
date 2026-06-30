SIM_MODE ?= $(call remove_quote,$(CONFIG_PLATFORM))
DIFFTEST_ON := $(if $(CONFIG_DIFFTEST),1,0)
PERF_ON := $(if $(CONFIG_PERF),1,0)
WAVE_ON := $(if $(CONFIG_WAVE),1,0)
TRACE_ON := $(if $(CONFIG_TRACE),1,0)
ITRACE_ON := $(if $(CONFIG_ITRACE),1,0)
FTRACE_ON := $(if $(CONFIG_FTRACE),1,0)
MTRACE_ON := $(if $(CONFIG_MTRACE),1,0)
DTRACE_ON := $(if $(CONFIG_DTRACE),1,0)
ETRACE_ON := $(if $(CONFIG_ETRACE),1,0)
WATCHPOINT_ON := $(if $(CONFIG_WATCHPOINT),1,0)
DEBUG_DEFAULT := $(if $(CONFIG_CC_DEBUG),1,0)
DEBUG_ON := $(DEBUG_DEFAULT)
UART_STDOUT ?= 1

VALID_SIM_MODES := npc ysyxsoc
ifeq ($(filter $(SIM_MODE),$(VALID_SIM_MODES)),)
$(error Unsupported SIM_MODE='$(SIM_MODE)'. Expected one of: $(VALID_SIM_MODES))
endif
ifneq ($(filter-out 0 1,$(UART_STDOUT)),)
$(error Unsupported UART_STDOUT='$(UART_STDOUT)'. Expected '0' or '1')
endif

ifeq ($(SIM_MODE),npc)
CONFIG_PLATFORM_NPC := y
CONFIG_PLATFORM_YSYXSOC :=
else
CONFIG_PLATFORM_NPC :=
CONFIG_PLATFORM_YSYXSOC := y
endif

DIFF_REF_SO ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-so
DIFF_PORT ?= 1234
YSYX_SOC_HOME ?= $(abspath ../ysyxSoC)
NVBOARD_HOME ?= $(abspath ../nvboard)

VERILATOR ?= verilator
OBJCACHE ?=
export OBJCACHE

CAPSTONE_HOME = $(NPC_HOME)/tools/capstone
CAPSTONE_SO = $(CAPSTONE_HOME)/repo/libcapstone.so.5
comma := ,

BUILD_DIR = $(NPC_HOME)/build/$(SIM_MODE)
OBJ_DIR = $(BUILD_DIR)/obj_dir-perf$(PERF_ON)-wave$(WAVE_ON)
VERILOG_BUILD_DIR = $(NPC_HOME)/build
CPU_VERILOG = $(abspath $(VERILOG_BUILD_DIR)/ysyx_26030082.v)

NXDC_FILES = $(abspath $(NPC_HOME)/constr/ysyxSoCFull.nxdc)
SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)

CPU_VSRCS = $(sort $(shell find $(abspath $(NPC_HOME)/vsrc/core) -name "*.v"))
VSRCS_NPC = $(sort $(shell find $(abspath $(NPC_HOME)/vsrc/npc) -name "*.v"))
VSRCS_NPC_NO_TOP = $(filter-out $(abspath $(NPC_HOME)/vsrc/npc/top.v),$(VSRCS_NPC))
VHDRS_BASE = $(shell find $(abspath $(NPC_HOME)/vsrc) -name "*.vh" -o -name "*.svh")
INC_PATH_COMMON = $(NPC_HOME)/include $(abspath $(NPC_HOME)/vsrc) $(abspath $(NPC_HOME)/vsrc/core)

ifeq ($(SIM_MODE),npc)
TOPNAME = top
VSRCS = $(CPU_VERILOG) $(VSRCS_NPC)
VHDRS = $(VHDRS_BASE)
INC_PATH = $(INC_PATH_COMMON) $(abspath $(NPC_HOME)/vsrc/npc)
else
TOPNAME = ysyxSoCFull
VSRCS = \
	$(CPU_VERILOG) \
	$(shell find $(YSYX_SOC_HOME)/perip -name "*.v") \
	$(YSYX_SOC_HOME)/build/ysyxSoCFull.v
VHDRS = \
	$(VHDRS_BASE) \
	$(shell find $(YSYX_SOC_HOME)/perip -name "*.vh" -o -name "*.svh")
SRCS += $(SRC_AUTO_BIND)
MODE_EXTRA_INPUTS = $(NVBOARD_ARCHIVE)
MODE_EXTRA_DEPS = $(NVBOARD_ARCHIVE)
INC_PATH = \
	$(INC_PATH_COMMON) \
	$(YSYX_SOC_HOME)/perip/uart16550/rtl \
	$(YSYX_SOC_HOME)/perip/spi/rtl
include $(NVBOARD_HOME)/scripts/nvboard.mk
endif

BIN = $(BUILD_DIR)/$(TOPNAME)
INCLUDES = $(addprefix -I, $(INC_PATH))

CFLAGS += $(INCLUDES) -MMD -Wall -Werror
CFLAGS += -DTOP_NAME="\"V$(TOPNAME)\""
CFLAGS += $(if $(filter npc,$(SIM_MODE)),-DNPC_BUILD_PLATFORM_NPC=1,-DNPC_BUILD_PLATFORM_YSYXSOC=1)
CFLAGS += -DITRACE_COND='$(if $(CONFIG_ITRACE_COND),$(subst ",,$(CONFIG_ITRACE_COND)),true)'
CFLAGS += -DMTRACE_COND='$(if $(CONFIG_MTRACE_COND),$(subst ",,$(CONFIG_MTRACE_COND)),true)'
CFLAGS += $(if $(filter 1,$(ITRACE_ON)),-I$(CAPSTONE_HOME)/repo/include,)
CFLAGS += $(if $(filter 1,$(DEBUG_ON)),-Og -ggdb3,-O2)
LDFLAGS += $(if $(filter 1,$(DEBUG_ON)),-Og -ggdb3,-O2)
LDFLAGS += $(if $(filter 1,$(ITRACE_ON)),-Wl$(comma)-rpath$(comma)$(CAPSTONE_HOME)/repo $(CAPSTONE_SO),)
LDFLAGS += -lreadline

VERILATOR_CFLAGS += -MMD --build -cc \
	$(call remove_quote,$(CONFIG_VERILATOR_OPT)) --x-assign fast --x-initial fast --noassert \
	-Wno-PINMISSING -Wno-WIDTHEXPAND \
	--timescale "1ns/1ns" --no-timing --autoflush \
	-MAKEFLAGS "VM_DEFAULT_RULES=0"
VERILATOR_CFLAGS += $(if $(filter 1,$(WAVE_ON)),--trace,)
VERILOG_DEFINES += $(if $(filter 1,$(UART_STDOUT)),-DNPC_UART_STDOUT_RTL,)
VERILOG_DEFINES += $(if $(filter 1,$(PERF_ON)),-DNPC_ENABLE_PERF,)
VERILOG_DEFINES += $(if $(filter 1,$(TRACE_ON)),-DNPC_ENABLE_TRACE,)
VERILOG_DEFINES += $(if $(filter 1,$(MTRACE_ON) $(DTRACE_ON)),-DNPC_ENABLE_MEMTRACE,)
VERILOG_DEFINES += $(if $(filter 1,$(ETRACE_ON)),-DNPC_ENABLE_ETRACE,)

BUILD_CONFIG = $(BUILD_DIR)/.build_config.mk
BUILD_CONFIG_TEXT := SIM_MODE=$(SIM_MODE) TOPNAME=$(TOPNAME) DIFFTEST=$(DIFFTEST_ON) PERF=$(PERF_ON) WAVE=$(WAVE_ON) TRACE=$(TRACE_ON) TRACE_START=$(CONFIG_TRACE_START) TRACE_END=$(CONFIG_TRACE_END) ITRACE=$(ITRACE_ON) ITRACE_COND=$(CONFIG_ITRACE_COND) FTRACE=$(FTRACE_ON) MTRACE=$(MTRACE_ON) MTRACE_COND=$(CONFIG_MTRACE_COND) DTRACE=$(DTRACE_ON) ETRACE=$(ETRACE_ON) WATCHPOINT=$(WATCHPOINT_ON) DEBUG=$(DEBUG_ON) UART_STDOUT=$(UART_STDOUT) SRCS=$(SRCS)
-include $(BUILD_CONFIG)

SOURCE_LIST_CONFIG = $(BUILD_DIR)/.source_list.mk
SOURCE_LIST_TEXT := SRCS=$(SRCS)
-include $(SOURCE_LIST_CONFIG)

ifneq ($(CONFIG_TEXT),$(BUILD_CONFIG_TEXT))
.PHONY: FORCE_BUILD_CONFIG
$(BUILD_CONFIG): FORCE_BUILD_CONFIG | $(BUILD_DIR)
	@rm -rf $(OBJ_DIR)
	@printf '%s\n' 'CONFIG_TEXT := $(BUILD_CONFIG_TEXT)' > $@
else
$(BUILD_CONFIG): | $(BUILD_DIR)
	@:
endif

ifneq ($(SOURCE_LIST_CONFIG_TEXT),$(SOURCE_LIST_TEXT))
.PHONY: FORCE_SOURCE_LIST_CONFIG
$(SOURCE_LIST_CONFIG): FORCE_SOURCE_LIST_CONFIG | $(BUILD_DIR)
	@rm -rf $(OBJ_DIR)
	@printf '%s\n' 'SOURCE_LIST_CONFIG_TEXT := $(SOURCE_LIST_TEXT)' > $@
else
$(SOURCE_LIST_CONFIG): | $(BUILD_DIR)
	@:
endif

NPC_DEPS = $(VSRCS) $(VHDRS) $(SRCS) $(MODE_EXTRA_DEPS) Makefile $(NPC_HOME)/scripts/build.mk $(BUILD_CONFIG) $(SOURCE_LIST_CONFIG) $(NPC_HOME)/include/generated/autoconf.h
ifeq ($(ITRACE_ON),1)
NPC_DEPS += $(CAPSTONE_SO)
endif

RUN_ARGS += $(if $(filter 1,$(DIFFTEST_ON)),-d $(DIFF_REF_SO) -p $(DIFF_PORT),)

ifeq ($(filter 1,$(DIFFTEST_ON)),1)
ifeq ($(strip $(NEMU_HOME)),)
$(error NEMU_HOME is required when CONFIG_DIFFTEST=y)
endif
endif

$(BUILD_DIR) $(VERILOG_BUILD_DIR):
	@mkdir -p $@

$(CPU_VERILOG): $(CPU_VSRCS) | $(VERILOG_BUILD_DIR)
	@echo + CAT "->" $@
	@cat $(CPU_VSRCS) > $@

$(SRC_AUTO_BIND): $(NXDC_FILES) | $(BUILD_DIR)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

$(CAPSTONE_SO):
	$(MAKE) -C $(CAPSTONE_HOME)

$(BIN): $(NPC_DEPS) | $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_CFLAGS) $(VERILOG_DEFINES) $(INCLUDES) \
		--top-module $(TOPNAME) $(VSRCS) $(SRCS) $(MODE_EXTRA_INPUTS) \
		$(addprefix -CFLAGS , $(CFLAGS)) \
		$(addprefix -LDFLAGS , $(LDFLAGS)) \
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))
	@touch $(abspath $(BIN))

build: $(BIN)

sim run: $(BIN)
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@$^ $(RUN_ARGS) $(ARGS) $(IMG)

verilog: $(CPU_VERILOG)

.PHONY: build sim run verilog
