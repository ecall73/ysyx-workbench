YOSYS_STA_HOME ?= $(abspath $(NPC_HOME)/../yosys-sta)

PERF_DESIGN ?= ysyx_26030082
PERF_CLK_FREQ_MHZ ?= 500
PERF_CLK_PORT_NAME ?= clock
PERF_OUTPUT ?= $(abspath $(NPC_HOME)/build/perf)
PERF_SDC_FILE ?= $(YOSYS_STA_HOME)/scripts/default.sdc

perf-check:
	@test -f "$(YOSYS_STA_HOME)/Makefile" || { printf 'error: yosys-sta is unavailable at %s\n' "$(YOSYS_STA_HOME)" >&2; exit 1; }
	@test -x "$(YOSYS_STA_HOME)/bin/iEDA" || { printf 'error: initialize yosys-sta with make -C %s init\n' "$(YOSYS_STA_HOME)" >&2; exit 1; }
	@test -d "$(YOSYS_STA_HOME)/pdk/icsprout55" || { printf 'error: initialize yosys-sta with make -C %s init\n' "$(YOSYS_STA_HOME)" >&2; exit 1; }

perf: $(CPU_VERILOG) perf-check
	$(MAKE) -C "$(YOSYS_STA_HOME)" sta \
		DESIGN="$(PERF_DESIGN)" \
		RTL_FILES="$(CPU_VERILOG)" \
		SDC_FILE="$(PERF_SDC_FILE)" \
		CLK_FREQ_MHZ="$(PERF_CLK_FREQ_MHZ)" \
		CLK_PORT_NAME="$(PERF_CLK_PORT_NAME)" \
		O="$(PERF_OUTPUT)"

.PHONY: perf perf-check
