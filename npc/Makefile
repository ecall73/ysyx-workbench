.DEFAULT_GOAL := build

# User-facing simulation knobs
SIM_MODE ?= ysyxsoc
DIFF ?= 0
PERF ?= 0
WAVE ?= 0
UART_STDOUT ?= 1
DIFF_REF_SO ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-so
DIFF_PORT ?= 1234

YSYX_SOC_HOME ?= $(abspath ../ysyxSoC)
NVBOARD_HOME ?= $(abspath ../nvboard)

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
ifneq ($(filter-out 0 1,$(UART_STDOUT)),)
$(error Unsupported UART_STDOUT='$(UART_STDOUT)'. Expected '0' or '1')
endif

ifeq ($(DIFF),1)
ifeq ($(strip $(NEMU_HOME)),)
$(error NEMU_HOME is required when DIFF=1)
endif
RUN_ARGS += -d $(DIFF_REF_SO) -p $(DIFF_PORT)
endif

# Tools and common flags
VERILATOR ?= verilator
# GCC 11 may ICE on some Verilator-generated PCH compilations when ccache is
# injected by verilated.mk. Keep objcache disabled by default for stability.
OBJCACHE ?=
export OBJCACHE

VERILATOR_CFLAGS += -MMD --build -cc \
	-O3 --x-assign fast --x-initial fast --noassert \
	-Wno-PINMISSING -Wno-WIDTHEXPAND \
	--timescale "1ns/1ns" --no-timing --autoflush \
	-MAKEFLAGS "VM_DEFAULT_RULES=0"

ifeq ($(WAVE),1)
  VERILATOR_CFLAGS += --trace
endif
ifeq ($(UART_STDOUT),1)
  VERILOG_DEFINES += -DNPC_UART_STDOUT_RTL
endif
ifeq ($(PERF),1)
  VERILOG_DEFINES += -DNPC_ENABLE_PERF
endif

# Build paths
BUILD_DIR = ./build/$(SIM_MODE)
OBJ_DIR = $(BUILD_DIR)/obj_dir-perf$(PERF)-wave$(WAVE)
BIN = $(BUILD_DIR)/$(TOPNAME)

VERILOG_BUILD_DIR = ./build
CPU_VERILOG = $(abspath $(VERILOG_BUILD_DIR)/ysyx_26030082.v)

NXDC_FILES = $(abspath ./constr/ysyxSoCFull.nxdc)
SRC_AUTO_BIND = $(abspath $(BUILD_DIR)/auto_bind.cpp)

# PERF/WAVE/UART_STDOUT are compile-time options while BIN keeps a stable path.
# The stamp forces a relink only when those options actually change.
BUILD_CONFIG = $(BUILD_DIR)/.build_config.mk
BUILD_CONFIG_TEXT := SIM_MODE=$(SIM_MODE) PERF=$(PERF) WAVE=$(WAVE) UART_STDOUT=$(UART_STDOUT)
-include $(BUILD_CONFIG)

ifneq ($(CONFIG_TEXT),$(BUILD_CONFIG_TEXT))
.PHONY: FORCE_BUILD_CONFIG
$(BUILD_CONFIG): FORCE_BUILD_CONFIG | $(BUILD_DIR)
	@printf '%s\n' 'CONFIG_TEXT := $(BUILD_CONFIG_TEXT)' > $@
else
$(BUILD_CONFIG): | $(BUILD_DIR)
	@:
endif

# Project sources
CPU_VSRCS = $(sort $(shell find $(abspath ./vsrc/core) -name "*.v"))
VSRCS_NPC = $(sort $(shell find $(abspath ./vsrc/npc) -name "*.v"))
VSRCS_NPC_NO_TOP = $(filter-out $(abspath ./vsrc/npc/top.v),$(VSRCS_NPC))
VHDRS_BASE = $(shell find $(abspath ./vsrc) -name "*.vh" -o -name "*.svh")
CSRCS = $(shell find $(abspath ./csrc) \( -name "*.c" -o -name "*.cc" -o -name "*.cpp" \))
CHDRS = $(shell find $(abspath ./csrc) \( -name "*.h" -o -name "*.hpp" \))

INC_PATH_COMMON = \
	$(abspath ./vsrc) \
	$(abspath ./vsrc/core)

ifeq ($(SIM_MODE),npc)
  TOPNAME = top
  MODE_CPPFLAGS += -DNPC_SIM_MODE_NPC=1
  VSRCS = $(CPU_VERILOG) $(VSRCS_NPC)
  VHDRS = $(VHDRS_BASE)
  INC_PATH = $(INC_PATH_COMMON) $(abspath ./vsrc/npc)
else
  TOPNAME = ysyxSoCFull
  MODE_CPPFLAGS += -DNPC_SIM_MODE_YSYXSOC=1

  VSRCS = \
	$(CPU_VERILOG) \
	$(shell find $(YSYX_SOC_HOME)/perip -name "*.v") \
	$(YSYX_SOC_HOME)/build/ysyxSoCFull.v
  VHDRS = \
	$(VHDRS_BASE) \
	$(shell find $(YSYX_SOC_HOME)/perip -name "*.vh" -o -name "*.svh")
  CSRCS += $(SRC_AUTO_BIND)
  MODE_EXTRA_INPUTS = $(NVBOARD_ARCHIVE)
  MODE_EXTRA_DEPS = $(NVBOARD_ARCHIVE)
  INC_PATH = \
	$(INC_PATH_COMMON) \
	$(YSYX_SOC_HOME)/perip/uart16550/rtl \
	$(YSYX_SOC_HOME)/perip/spi/rtl

  include $(NVBOARD_HOME)/scripts/nvboard.mk
endif

NPC_DEPS = $(VSRCS) $(VHDRS) $(CSRCS) $(CHDRS) $(MODE_EXTRA_DEPS) Makefile $(BUILD_CONFIG)
INCFLAGS = $(addprefix -I, $(INC_PATH)) -I$(abspath ./csrc)
CFLAGS += \
	$(INCFLAGS) \
	$(MODE_CPPFLAGS) \
	-DTOP_NAME="\"V$(TOPNAME)\"" \
	-DNPC_ENABLE_PERF=$(PERF) \
	-DNPC_ENABLE_WAVE=$(WAVE)
LDFLAGS += -lreadline



$(BUILD_DIR) $(VERILOG_BUILD_DIR):
	@mkdir -p $@

$(CPU_VERILOG): $(CPU_VSRCS) | $(VERILOG_BUILD_DIR)
	@echo + CAT "->" $@
	@cat $(CPU_VSRCS) > $@

$(SRC_AUTO_BIND): $(NXDC_FILES) | $(BUILD_DIR)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

$(BIN): $(NPC_DEPS) | $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_CFLAGS) $(VERILOG_DEFINES) $(INCFLAGS) \
		--top-module $(TOPNAME) $(VSRCS) $(CSRCS) $(MODE_EXTRA_INPUTS) \
		$(addprefix -CFLAGS , $(CFLAGS)) \
		$(addprefix -LDFLAGS , $(LDFLAGS)) \
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))
	@touch $(abspath $(BIN))

build: $(BIN)

sim: $(BIN)
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@$^ $(RUN_ARGS) $(ARGS)

clean:
	rm -rf ./build

include ../Makefile

.PHONY: build run clean verilog sim sim-iverilog sim-iverilog-netlist


# ==============================================================================
# CI debug flows
# ==============================================================================

IVERILOG ?= $(shell command -v iverilog 2>/dev/null || echo iverilog)
VVP ?= $(shell command -v vvp 2>/dev/null || echo vvp)

IVERILOG_FLAGS ?=
NETLIST_IVERILOG_FLAGS ?= -Dfunctional

IVERILOG_BUILD_DIR = ./build/iverilog
IVERILOG_VVP = $(abspath $(IVERILOG_BUILD_DIR)/simv)
IVERILOG_IMG_BIN = $(abspath $(IVERILOG_BUILD_DIR)/image.bin)
IVERILOG_HEX = $(abspath $(IVERILOG_BUILD_DIR)/image.hex)
IVERILOG_LOG = $(abspath $(IVERILOG_BUILD_DIR)/sim.log)
IVERILOG_TMPDIR = $(abspath $(IVERILOG_BUILD_DIR)/tmp)
IVERILOG_TB = $(abspath ./vsrc/iverilog/tb_iverilog.v)

IVERILOG_NETLIST_BUILD_DIR = ./build/iverilog-netlist
IVERILOG_NETLIST_VVP = $(abspath $(IVERILOG_NETLIST_BUILD_DIR)/simv)
IVERILOG_NETLIST_IMG_BIN = $(abspath $(IVERILOG_NETLIST_BUILD_DIR)/image.bin)
IVERILOG_NETLIST_HEX = $(abspath $(IVERILOG_NETLIST_BUILD_DIR)/image.hex)
IVERILOG_NETLIST_LOG = $(abspath $(IVERILOG_NETLIST_BUILD_DIR)/sim.log)
IVERILOG_NETLIST_TMPDIR = $(abspath $(IVERILOG_NETLIST_BUILD_DIR)/tmp)
IVERILOG_NETLIST_TB = $(abspath ./vsrc/iverilog/tb_iverilog_netlist.v)

WAVE_PLUSARG = $(if $(filter 1,$(WAVE)),+WAVE=1,)
BIN2HEX = python3 -c 'from pathlib import Path; import sys; data = Path(sys.argv[1]).read_bytes(); Path(sys.argv[2]).write_text("\n".join(f"{b:02x}" for b in data) + "\n")'

$(IVERILOG_BUILD_DIR) $(IVERILOG_NETLIST_BUILD_DIR):
	@mkdir -p $@

IVERILOG_SRCS = \
	$(CPU_VERILOG) \
	$(VSRCS_NPC) \
	$(IVERILOG_TB)

verilog: $(CPU_VERILOG)

sim-iverilog: verilog $(IVERILOG_TB) | $(IVERILOG_BUILD_DIR)
	@test -n "$(IMG)" || { echo "IMG=...bin is required"; exit 1; }
	@echo + COPY "->" $(IVERILOG_IMG_BIN)
	@cp "$(abspath $(IMG))" "$(IVERILOG_IMG_BIN)"
	@echo + BIN2HEX "->" $(IVERILOG_HEX)
	@$(BIN2HEX) "$(IVERILOG_IMG_BIN)" "$(IVERILOG_HEX)"
	@echo + IVERILOG "->" $(IVERILOG_VVP)
	@mkdir -p "$(IVERILOG_TMPDIR)"
	@TMPDIR="$(IVERILOG_TMPDIR)" TMP="$(IVERILOG_TMPDIR)" TEMP="$(IVERILOG_TMPDIR)" "$(IVERILOG)" $(IVERILOG_FLAGS) -I"$(abspath ./vsrc/npc)" -g2012 -o $(IVERILOG_VVP) -s tb_iverilog $(IVERILOG_SRCS)
	@img_bytes=$$(wc -c < "$(IVERILOG_IMG_BIN)"); \
	rm -f "$(IVERILOG_LOG)" "$(IVERILOG_BUILD_DIR)/wave.vcd"; \
	bash -o pipefail -c ' \
		"$(VVP)" "$$0" +IMG="$$1" +IMG_BYTES="$$2" $$3 $$4 2>&1 | tee "$$5" \
	' "$(IVERILOG_VVP)" "$(IVERILOG_HEX)" "$$img_bytes" "$(WAVE_PLUSARG)" "$(VVP_ARGS)" "$(IVERILOG_LOG)"; \
	grep -q "HIT GOOD TRAP" "$(IVERILOG_LOG)"

IVERILOG_NETLIST_SRCS = \
	$(VSRCS_NPC_NO_TOP) \
	$(abspath ./vsrc/npc/top.v) \
	$(IVERILOG_NETLIST_TB)

sim-iverilog-netlist: $(IVERILOG_NETLIST_TB) $(abspath ./vsrc/npc/top.v) | $(IVERILOG_NETLIST_BUILD_DIR)
	@test -n "$(IMG)" || { echo "IMG=...bin is required"; exit 1; }
	@test -n "$(NETLIST)" || { echo "NETLIST=...netlist.v is required"; exit 1; }
	@test -n "$(CELLS)" || { echo "CELLS=...cells.v is required"; exit 1; }
	@echo + COPY "->" $(IVERILOG_NETLIST_IMG_BIN)
	@cp "$(abspath $(IMG))" "$(IVERILOG_NETLIST_IMG_BIN)"
	@echo + BIN2HEX "->" $(IVERILOG_NETLIST_HEX)
	@$(BIN2HEX) "$(IVERILOG_NETLIST_IMG_BIN)" "$(IVERILOG_NETLIST_HEX)"
	@netlist_path="$(NETLIST)"; \
	netlist_sim="$$netlist_path"; \
	if [ "$${netlist_sim##*.}" != "sim" ] && [ -f "$$netlist_path.sim" ]; then \
		netlist_sim="$$netlist_path.sim"; \
	fi; \
	test -f "$$netlist_sim" || { echo "Missing netlist simulation file: $$netlist_sim"; exit 1; }; \
	cells_file="$(CELLS)"; \
	test -f "$$cells_file" || { echo "Missing cells simulation file: $$cells_file"; exit 1; }; \
	echo + IVERILOG "->" "$(IVERILOG_NETLIST_VVP)"; \
	mkdir -p "$(IVERILOG_NETLIST_TMPDIR)"; \
	TMPDIR="$(IVERILOG_NETLIST_TMPDIR)" TMP="$(IVERILOG_NETLIST_TMPDIR)" TEMP="$(IVERILOG_NETLIST_TMPDIR)" \
		"$(IVERILOG)" $(NETLIST_IVERILOG_FLAGS) -I"$(abspath ./vsrc/npc)" -g2012 -o "$(IVERILOG_NETLIST_VVP)" -s tb_iverilog_netlist $$netlist_sim $$cells_file $(IVERILOG_NETLIST_SRCS); \
	img_bytes=$$(wc -c < "$(IVERILOG_NETLIST_IMG_BIN)"); \
	rm -f "$(IVERILOG_NETLIST_LOG)" "$(IVERILOG_NETLIST_BUILD_DIR)/wave.vcd"; \
	bash -o pipefail -c ' \
		"$(VVP)" "$$0" +IMG="$$1" +IMG_BYTES="$$2" $$3 $$4 2>&1 | tee "$$5" \
	' "$(IVERILOG_NETLIST_VVP)" "$(IVERILOG_NETLIST_HEX)" "$$img_bytes" "$(WAVE_PLUSARG)" "$(VVP_ARGS)" "$(IVERILOG_NETLIST_LOG)"; \
	grep -q "HIT GOOD TRAP" "$(IVERILOG_NETLIST_LOG)"
