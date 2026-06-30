SIM_MODE ?= $(call remove_quote,$(CONFIG_PLATFORM))
DIFF ?= $(if $(CONFIG_DIFFTEST),1,0)
PERF ?= $(if $(CONFIG_PERF),1,0)
WAVE ?= $(if $(CONFIG_WAVE),1,0)
TRACE ?= $(if $(CONFIG_TRACE),1,0)
ITRACE ?= $(if $(CONFIG_ITRACE),1,0)
FTRACE ?= $(if $(CONFIG_FTRACE),1,0)
MTRACE ?= $(if $(CONFIG_MTRACE),1,0)
DTRACE ?= $(if $(CONFIG_DTRACE),1,0)
ETRACE ?= $(if $(CONFIG_ETRACE),1,0)
DEBUG_DEFAULT := $(if $(CONFIG_DEBUG),1,0)
ifeq ($(origin DEBUG),command line)
DEBUG := $(if $(filter 1 y yes true,$(DEBUG)),1,0)
else
DEBUG := $(DEBUG_DEFAULT)
endif
UART_STDOUT ?= 1
BATCH ?= 0

VALID_SIM_MODES := npc ysyxsoc
ifeq ($(filter $(SIM_MODE),$(VALID_SIM_MODES)),)
$(error Unsupported SIM_MODE='$(SIM_MODE)'. Expected one of: $(VALID_SIM_MODES))
endif
ifneq ($(filter-out 0 1,$(DIFF)),)
$(error Unsupported DIFF='$(DIFF)'. Expected '0' or '1')
endif
ifneq ($(filter-out 0 1,$(PERF)),)
$(error Unsupported PERF='$(PERF)'. Expected '0' or '1')
endif
ifneq ($(filter-out 0 1,$(WAVE)),)
$(error Unsupported WAVE='$(WAVE)'. Expected '0' or '1')
endif
ifneq ($(filter-out 0 1,$(TRACE)),)
$(error Unsupported TRACE='$(TRACE)'. Expected '0' or '1')
endif
ifneq ($(filter-out 0 1,$(ITRACE)),)
$(error Unsupported ITRACE='$(ITRACE)'. Expected '0' or '1')
endif
ifneq ($(filter-out 0 1,$(FTRACE)),)
$(error Unsupported FTRACE='$(FTRACE)'. Expected '0' or '1')
endif
ifneq ($(filter-out 0 1,$(MTRACE)),)
$(error Unsupported MTRACE='$(MTRACE)'. Expected '0' or '1')
endif
ifneq ($(filter-out 0 1,$(DTRACE)),)
$(error Unsupported DTRACE='$(DTRACE)'. Expected '0' or '1')
endif
ifneq ($(filter-out 0 1,$(ETRACE)),)
$(error Unsupported ETRACE='$(ETRACE)'. Expected '0' or '1')
endif
ifeq ($(TRACE),0)
ifneq ($(filter 1,$(ITRACE) $(FTRACE) $(MTRACE) $(DTRACE) $(ETRACE)),)
$(error TRACE=0 disables trace infrastructure; enable TRACE=1 before enabling ITRACE/FTRACE/MTRACE/DTRACE/ETRACE)
endif
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
OBJ_DIR = $(BUILD_DIR)/obj_dir-perf$(PERF)-wave$(WAVE)
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
CFLAGS += -DNPC_BUILD_PERF=$(PERF) -DNPC_BUILD_WAVE=$(WAVE)
CFLAGS += -DNPC_BUILD_TRACE=$(TRACE) -DNPC_BUILD_ITRACE=$(ITRACE) -DNPC_BUILD_FTRACE=$(FTRACE)
CFLAGS += -DNPC_BUILD_MTRACE=$(MTRACE) -DNPC_BUILD_DTRACE=$(DTRACE) -DNPC_BUILD_ETRACE=$(ETRACE)
CFLAGS += -DITRACE_COND='$(if $(CONFIG_ITRACE_COND),$(subst ",,$(CONFIG_ITRACE_COND)),true)'
CFLAGS += -DMTRACE_COND='$(if $(CONFIG_MTRACE_COND),$(subst ",,$(CONFIG_MTRACE_COND)),true)'
CFLAGS += $(if $(filter 1,$(ITRACE)),-I$(CAPSTONE_HOME)/repo/include,)
CFLAGS += $(if $(filter 1,$(DEBUG)),-Og -ggdb3,-O2)
LDFLAGS += $(if $(filter 1,$(DEBUG)),-Og -ggdb3,-O2)
LDFLAGS += $(if $(filter 1,$(ITRACE)),-Wl$(comma)-rpath$(comma)$(CAPSTONE_HOME)/repo $(CAPSTONE_SO),)
LDFLAGS += -lreadline

VERILATOR_CFLAGS += -MMD --build -cc \
	$(call remove_quote,$(CONFIG_VERILATOR_OPT)) --x-assign fast --x-initial fast --noassert \
	-Wno-PINMISSING -Wno-WIDTHEXPAND \
	--timescale "1ns/1ns" --no-timing --autoflush \
	-MAKEFLAGS "VM_DEFAULT_RULES=0"
VERILATOR_CFLAGS += $(if $(filter 1,$(WAVE)),--trace,)
VERILOG_DEFINES += $(if $(filter 1,$(UART_STDOUT)),-DNPC_UART_STDOUT_RTL,)
VERILOG_DEFINES += $(if $(filter 1,$(PERF)),-DNPC_ENABLE_PERF,)
VERILOG_DEFINES += $(if $(filter 1,$(TRACE)),-DNPC_ENABLE_TRACE,)
VERILOG_DEFINES += $(if $(filter 1,$(MTRACE) $(DTRACE)),-DNPC_ENABLE_MEMTRACE,)
VERILOG_DEFINES += $(if $(filter 1,$(ETRACE)),-DNPC_ENABLE_ETRACE,)

BUILD_CONFIG = $(BUILD_DIR)/.build_config.mk
BUILD_CONFIG_TEXT := SIM_MODE=$(SIM_MODE) TOPNAME=$(TOPNAME) DIFF=$(DIFF) PERF=$(PERF) WAVE=$(WAVE) TRACE=$(TRACE) TRACE_START=$(CONFIG_TRACE_START) TRACE_END=$(CONFIG_TRACE_END) ITRACE=$(ITRACE) ITRACE_COND=$(CONFIG_ITRACE_COND) FTRACE=$(FTRACE) MTRACE=$(MTRACE) MTRACE_COND=$(CONFIG_MTRACE_COND) DTRACE=$(DTRACE) ETRACE=$(ETRACE) DEBUG=$(DEBUG) UART_STDOUT=$(UART_STDOUT) SRCS=$(SRCS)
-include $(BUILD_CONFIG)

ifneq ($(CONFIG_TEXT),$(BUILD_CONFIG_TEXT))
.PHONY: FORCE_BUILD_CONFIG
$(BUILD_CONFIG): FORCE_BUILD_CONFIG | $(BUILD_DIR)
	@printf '%s\n' 'CONFIG_TEXT := $(BUILD_CONFIG_TEXT)' > $@
else
$(BUILD_CONFIG): | $(BUILD_DIR)
	@:
endif

NPC_DEPS = $(VSRCS) $(VHDRS) $(SRCS) $(MODE_EXTRA_DEPS) Makefile $(BUILD_CONFIG) $(NPC_HOME)/include/generated/autoconf.h
ifeq ($(ITRACE),1)
NPC_DEPS += $(CAPSTONE_SO)
endif

RUN_ARGS += $(if $(filter 1,$(BATCH)),-b,)
RUN_ARGS += $(if $(filter 1,$(DIFF)),-d $(DIFF_REF_SO) -p $(DIFF_PORT),)
RUN_ARGS += $(if $(IMG),$(IMG),)

ifeq ($(filter 1,$(DIFF)),1)
ifeq ($(strip $(NEMU_HOME)),)
$(error NEMU_HOME is required when DIFF=1)
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
	@$^ $(RUN_ARGS) $(ARGS)

verilog: $(CPU_VERILOG)

.PHONY: build sim run verilog
