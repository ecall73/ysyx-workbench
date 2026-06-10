SIM_MODE ?= ysyxsoc
VALID_SIM_MODES := npc ysyxsoc
ifeq ($(filter $(SIM_MODE),$(VALID_SIM_MODES)),)
$(error Unsupported SIM_MODE='$(SIM_MODE)'. Expected one of: $(VALID_SIM_MODES))
endif

ifeq ($(SIM_MODE),npc)
  TOPNAME = top
  MODE_CPPFLAGS += -DNPC_SIM_MODE_NPC=1
else
  TOPNAME = ysyxSoCFull
  MODE_CPPFLAGS += -DNPC_SIM_MODE_YSYXSOC=1
endif

VERILATOR = verilator
YOSYS ?= $(if $(wildcard $(HOME)/oss-cad-suite/bin/yosys),$(HOME)/oss-cad-suite/bin/yosys,yosys)
IVERILOG ?= $(if $(wildcard /usr/bin/iverilog),/usr/bin/iverilog,$(if $(wildcard $(HOME)/oss-cad-suite/bin/iverilog),$(HOME)/oss-cad-suite/bin/iverilog,iverilog))
VVP ?= $(if $(wildcard /usr/bin/vvp),/usr/bin/vvp,$(if $(wildcard $(HOME)/oss-cad-suite/bin/vvp),$(HOME)/oss-cad-suite/bin/vvp,vvp))
IVERILOG_FLAGS ?=
NETLIST_IVERILOG_FLAGS ?= -Dfunctional
# GCC 11 may ICE on some Verilator-generated PCH compilations when ccache is
# injected by verilated.mk. Keep objcache disabled by default for stability.
# To re-enable cache manually: `make ... OBJCACHE=ccache`.
OBJCACHE ?=
export OBJCACHE
VERILATOR_CFLAGS += -MMD --build -cc  \
  -O3 --x-assign fast --x-initial fast --noassert \
  -Wno-PINMISSING -Wno-WIDTHEXPAND \
  --trace --timescale "1ns/1ns" --no-timing --autoflush \
  -MAKEFLAGS "VM_DEFAULT_RULES=0"

BUILD_DIR = ./build/$(SIM_MODE)
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(BUILD_DIR)/$(TOPNAME)
VERILOG_BUILD_DIR = ./build
CPU_VERILOG = $(abspath $(VERILOG_BUILD_DIR)/ysyx_26030082.v)
IVERILOG_BUILD_DIR = ./build/iverilog
IVERILOG_VVP = $(abspath $(IVERILOG_BUILD_DIR)/simv)
IVERILOG_IMG_BIN = $(abspath $(IVERILOG_BUILD_DIR)/image.bin)
IVERILOG_HEX = $(abspath $(IVERILOG_BUILD_DIR)/image.hex)
IVERILOG_LOG = $(abspath $(IVERILOG_BUILD_DIR)/sim.log)
IVERILOG_TMPDIR = $(abspath $(IVERILOG_BUILD_DIR)/tmp)
IVERILOG_TB = $(abspath ./vsrc/iverilog/tb_iverilog.v)
IVERILOG_MAX_CYCLES ?= 5000000
IVERILOG_NETLIST_BUILD_DIR = ./build/iverilog-netlist
IVERILOG_NETLIST_VVP = $(abspath $(IVERILOG_NETLIST_BUILD_DIR)/simv)
IVERILOG_NETLIST_IMG_BIN = $(abspath $(IVERILOG_NETLIST_BUILD_DIR)/image.bin)
IVERILOG_NETLIST_HEX = $(abspath $(IVERILOG_NETLIST_BUILD_DIR)/image.hex)
IVERILOG_NETLIST_LOG = $(abspath $(IVERILOG_NETLIST_BUILD_DIR)/sim.log)
IVERILOG_NETLIST_TMPDIR = $(abspath $(IVERILOG_NETLIST_BUILD_DIR)/tmp)
IVERILOG_NETLIST_TB = $(abspath ./vsrc/iverilog/tb_iverilog_netlist.v)
IVERILOG_NETLIST_TOP = $(abspath ./vsrc/iverilog/top_netlist.v)
YOSYS_STA_HOME ?= $(HOME)/yosys-sta
NETLIST_CELLS_DEFAULT = $(YOSYS_STA_HOME)/pdk/icsprout55/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/verilog/ics55_LLSC_H7CL.v
NETLIST_BUILD_ROOT = $(abspath ./build/netlist)
CLK_FREQ_MHZ ?= 800
NETLIST_RESET_PC ?= 32'h80000000
NETLIST_TARGET_NPC ?= 1
NETLIST_RESULT_DIR = $(NETLIST_BUILD_ROOT)/ysyx_26030082-$(CLK_FREQ_MHZ)MHz
NETLIST_RESULT = $(NETLIST_RESULT_DIR)/ysyx_26030082.netlist.v
NETLIST_SCRIPT_DIR = $(NETLIST_BUILD_ROOT)/scripts
NETLIST_COMPAT_TCL = $(NETLIST_SCRIPT_DIR)/yosys.tcl
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

$(BUILD_DIR):
	@mkdir -p $@

$(VERILOG_BUILD_DIR):
	@mkdir -p $@

$(IVERILOG_BUILD_DIR):
	@mkdir -p $@

$(IVERILOG_NETLIST_BUILD_DIR):
	@mkdir -p $@

# Common project source
CPU_VSRCS = $(sort $(shell find $(abspath ./vsrc/core) -name "*.v"))
VSRCS_NPC = $(shell find $(abspath ./vsrc/npc) -name "*.v")
VSRCS_NPC_NO_TOP = $(filter-out $(abspath ./vsrc/npc/top.v),$(VSRCS_NPC))
VHDRS_BASE = $(shell find $(abspath ./vsrc) -name "*.vh" -o -name "*.svh")
CSRCS = $(shell find $(abspath ./csrc) \( -name "*.c" -o -name "*.cc" -o -name "*.cpp" \))
CHDRS = $(shell find $(abspath ./csrc) \( -name "*.h" -o -name "*.hpp" \))
INC_PATH_COMMON := $(abspath ./vsrc) \
	$(abspath ./vsrc/core)

$(CPU_VERILOG): $(CPU_VSRCS) | $(VERILOG_BUILD_DIR)
	@echo + CAT "->" $@
	@cat $(CPU_VSRCS) > $@

verilog: $(CPU_VERILOG)

IVERILOG_SRCS = \
	$(CPU_VERILOG) \
	$(sort $(shell find $(abspath ./vsrc/npc) -name "*.v")) \
	$(IVERILOG_TB)

IVERILOG_NETLIST_SRCS = \
	$(VSRCS_NPC_NO_TOP) \
	$(IVERILOG_NETLIST_TOP) \
	$(IVERILOG_NETLIST_TB)

ifeq ($(SIM_MODE),ysyxsoc)
# constraint file -> NVBoard auto bind source
$(SRC_AUTO_BIND): $(NXDC_FILES) | $(BUILD_DIR)
	python3 $(NVBOARD_HOME)/scripts/auto_pin_bind.py $^ $@

  VSRCS = $(CPU_VERILOG) \
	$(shell find $(YSYX_SOC_HOME)/perip -name "*.v") \
	$(YSYX_SOC_HOME)/build/ysyxSoCFull.v
  VHDRS = $(VHDRS_BASE) \
	$(shell find $(YSYX_SOC_HOME)/perip -name "*.vh" -o -name "*.svh")
  CSRCS += $(SRC_AUTO_BIND)
  MODE_EXTRA_INPUTS = $(CHAR_TEST_BIN) $(NVBOARD_ARCHIVE)
  MODE_EXTRA_DEPS = $(CHAR_TEST_BIN) $(NVBOARD_ARCHIVE)

  # rules for verilator
  INC_PATH := $(INC_PATH_COMMON) \
	$(YSYX_SOC_HOME)/perip/uart16550/rtl \
	$(YSYX_SOC_HOME)/perip/spi/rtl
  # rules for NVBoard
  include $(NVBOARD_HOME)/scripts/nvboard.mk
else
  VSRCS = $(CPU_VERILOG) $(VSRCS_NPC)
  VHDRS = $(VHDRS_BASE)

  # rules for verilator
  INC_PATH := $(INC_PATH_COMMON) \
	$(abspath ./vsrc/npc)
endif

NPC_DEPS = $(VSRCS) $(VHDRS) $(CSRCS) $(CHDRS) $(MODE_EXTRA_DEPS) Makefile

INCFLAGS = $(addprefix -I, $(INC_PATH)) -I$(abspath ./csrc) -I$(NEMU_HOME)/tools/capstone/repo/include
CFLAGS += $(INCFLAGS) $(MODE_CPPFLAGS) -DTOP_NAME="\"V$(TOPNAME)\""

LDFLAGS += -lreadline $(NEMU_HOME)/tools/capstone/repo/libcapstone.a

$(CHAR_TEST_ELF): $(CHAR_TEST_SRC) $(CHAR_TEST_LD) | $(BUILD_DIR)
	@echo + CC "->" $(CHAR_TEST_ELF)
	@$(RV_CC) $(CHAR_TEST_CFLAGS) $(CHAR_TEST_SRC) -o $(CHAR_TEST_ELF) $(CHAR_TEST_LDFLAGS)

$(CHAR_TEST_BIN): $(CHAR_TEST_ELF)
	@echo + OBJCOPY "->" $(CHAR_TEST_BIN)
	@$(RV_OBJCOPY) -O binary $(CHAR_TEST_ELF) $(CHAR_TEST_BIN)

$(BIN): $(NPC_DEPS) | $(BUILD_DIR)
	$(VERILATOR) $(VERILATOR_CFLAGS) $(INCFLAGS) \
		--top-module $(TOPNAME) $(VSRCS) $(CSRCS) $(MODE_EXTRA_INPUTS) \
		$(addprefix -CFLAGS , $(CFLAGS)) \
		$(addprefix -LDFLAGS , $(LDFLAGS)) \
		--Mdir $(OBJ_DIR) --exe -o $(abspath $(BIN))

sim: $(BIN)
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@$^ $(ARGS)

sim-iverilog: verilog $(IVERILOG_TB) | $(IVERILOG_BUILD_DIR)
	@test -n "$(IMG)" || { echo "IMG=...bin is required"; exit 1; }
	@echo + COPY "->" $(IVERILOG_IMG_BIN)
	@cp "$(abspath $(IMG))" "$(IVERILOG_IMG_BIN)"
	@echo + BIN2HEX "->" $(IVERILOG_HEX)
	@python3 -c 'from pathlib import Path; import sys; data = Path(sys.argv[1]).read_bytes(); Path(sys.argv[2]).write_text("\n".join(f"{b:02x}" for b in data) + "\n")' "$(IVERILOG_IMG_BIN)" "$(IVERILOG_HEX)"
	@echo + IVERILOG "->" $(IVERILOG_VVP)
	@mkdir -p "$(IVERILOG_TMPDIR)"
	@TMPDIR="$(IVERILOG_TMPDIR)" TMP="$(IVERILOG_TMPDIR)" TEMP="$(IVERILOG_TMPDIR)" "$(IVERILOG)" $(IVERILOG_FLAGS) -g2012 -o $(IVERILOG_VVP) -s tb_iverilog $(IVERILOG_SRCS)
	@img_bytes=$$(wc -c < "$(IVERILOG_IMG_BIN)"); \
	rm -f "$(IVERILOG_LOG)" "$(IVERILOG_BUILD_DIR)/wave.vcd"; \
	bash -o pipefail -c ' \
		"$(VVP)" "$$0" +IMG="$$1" +IMG_BYTES="$$2" +MAX_CYCLES="$$3" $$4 $$5 2>&1 | tee "$$6" \
	' "$(IVERILOG_VVP)" "$(IVERILOG_HEX)" "$$img_bytes" "$(IVERILOG_MAX_CYCLES)" "$(if $(filter 1 y yes true,$(WAVE)),+WAVE=1,)" "$(VVP_ARGS)" "$(IVERILOG_LOG)"; \
	grep -q "HIT GOOD TRAP" "$(IVERILOG_LOG)"

synth-netlist: verilog
	@mkdir -p "$(NETLIST_BUILD_ROOT)" "$(NETLIST_SCRIPT_DIR)" "$(NETLIST_RESULT_DIR)"
	@python3 "$(abspath ./scripts/gen_yosys_netlist_compat.py)" "$(YOSYS_STA_HOME)/scripts/yosys.tcl" "$(NETLIST_COMPAT_TCL)" "$(YOSYS_STA_HOME)"
	@echo tcl "$(NETLIST_COMPAT_TCL)" ysyx_26030082 icsprout55 "\"$(CPU_VERILOG)\"" "$(NETLIST_RESULT)" | NETLIST_RESET_PC="$(NETLIST_RESET_PC)" NETLIST_TARGET_NPC="$(NETLIST_TARGET_NPC)" CLK_FREQ_MHZ="$(CLK_FREQ_MHZ)" "$(YOSYS)" -g -l "$(NETLIST_RESULT_DIR)/yosys.log" -s -

sim-iverilog-netlist: $(IVERILOG_NETLIST_TB) $(IVERILOG_NETLIST_TOP) | $(IVERILOG_NETLIST_BUILD_DIR)
	@test -n "$(IMG)" || { echo "IMG=...bin is required"; exit 1; }
	@test -n "$(NETLIST)" || { echo "NETLIST=... is required"; exit 1; }
	@echo + COPY "->" $(IVERILOG_NETLIST_IMG_BIN)
	@cp "$(abspath $(IMG))" "$(IVERILOG_NETLIST_IMG_BIN)"
	@echo + BIN2HEX "->" $(IVERILOG_NETLIST_HEX)
	@python3 -c 'from pathlib import Path; import sys; data = Path(sys.argv[1]).read_bytes(); Path(sys.argv[2]).write_text("\n".join(f"{b:02x}" for b in data) + "\n")' "$(IVERILOG_NETLIST_IMG_BIN)" "$(IVERILOG_NETLIST_HEX)"
	@netlist_sim="$(NETLIST)"; \
	if [ ! -f "$$netlist_sim" ] && [ "$${netlist_sim##*.}" != "sim" ] && [ -f "$(NETLIST).sim" ]; then \
		netlist_sim="$(NETLIST).sim"; \
	fi; \
	test -f "$$netlist_sim" || { echo "Missing netlist simulation file: $$netlist_sim"; exit 1; }; \
	cells_file="$(if $(CELLS),$(CELLS),$(NETLIST_CELLS_DEFAULT))"; \
		test -f "$$cells_file" || { echo "Missing cells simulation file: $$cells_file"; exit 1; }; \
	echo + IVERILOG "->" "$(IVERILOG_NETLIST_VVP)"; \
	mkdir -p "$(IVERILOG_NETLIST_TMPDIR)"; \
		TMPDIR="$(IVERILOG_NETLIST_TMPDIR)" TMP="$(IVERILOG_NETLIST_TMPDIR)" TEMP="$(IVERILOG_NETLIST_TMPDIR)" \
		"$(IVERILOG)" $(NETLIST_IVERILOG_FLAGS) -g2012 -o "$(IVERILOG_NETLIST_VVP)" -s tb_iverilog_netlist $$netlist_sim $$cells_file $(IVERILOG_NETLIST_SRCS); \
	img_bytes=$$(wc -c < "$(IVERILOG_NETLIST_IMG_BIN)"); \
	rm -f "$(IVERILOG_NETLIST_LOG)" "$(IVERILOG_NETLIST_BUILD_DIR)/wave.vcd"; \
	bash -o pipefail -c ' \
		"$(VVP)" "$$0" +IMG="$$1" +IMG_BYTES="$$2" +MAX_CYCLES="$$3" $$4 $$5 2>&1 | tee "$$6" \
	' "$(IVERILOG_NETLIST_VVP)" "$(IVERILOG_NETLIST_HEX)" "$$img_bytes" "$(IVERILOG_MAX_CYCLES)" "$(if $(filter 1 y yes true,$(WAVE)),+WAVE=1,)" "$(VVP_ARGS)" "$(IVERILOG_NETLIST_LOG)"; \
	grep -q "HIT GOOD TRAP" "$(IVERILOG_NETLIST_LOG)"

clean:
	rm -rf ./build

include ../Makefile

.PHONY: default run clean verilog sim-iverilog synth-netlist sim-iverilog-netlist
