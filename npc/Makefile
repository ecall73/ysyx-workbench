.DEFAULT_GOAL := build

NPC_HOME := $(abspath .)
NEMU_HOME ?= $(abspath ../nemu)

-include $(NPC_HOME)/include/config/auto.conf
-include $(NPC_HOME)/include/config/auto.conf.cmd

remove_quote = $(patsubst "%",%,$(1))

CXX ?= g++

include $(NPC_HOME)/scripts/config.mk

config-targets := menuconfig savedefconfig help distclean clean
config-targets += $(filter %defconfig,$(MAKECMDGOALS))

ifeq ($(filter $(config-targets),$(MAKECMDGOALS)),)
SIM_MODE ?= $(call remove_quote,$(CONFIG_PLATFORM))
ifeq ($(SIM_MODE),npc)
CONFIG_PLATFORM_NPC := y
CONFIG_PLATFORM_YSYXSOC :=
else
ifeq ($(SIM_MODE),ysyxsoc)
CONFIG_PLATFORM_NPC :=
CONFIG_PLATFORM_YSYXSOC := y
endif
endif

FILELIST_MK = $(shell find -L ./src -name "filelist.mk")
include $(FILELIST_MK)

SRCS-y += $(if $(DIRS-y),$(shell find -L $(DIRS-y) -name "*.cpp"),)
SRCS = $(sort $(SRCS-y))

include $(NPC_HOME)/scripts/build.mk
endif

clean:
	rm -rf ./build

distclean: clean
	rm -rf include/generated include/config .config .config.old

include ../Makefile

.PHONY: clean distclean sim-iverilog sim-iverilog-netlist

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
