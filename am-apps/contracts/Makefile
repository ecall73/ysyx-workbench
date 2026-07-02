.PHONY: run all clean help

ARCH ?= riscv32e-ysyxsoc
RUNNER := $(CURDIR)/run-contracts.sh

comma := ,
empty :=
space := $(empty) $(empty)
ALL_LIST := $(strip $(subst $(comma),$(space),$(ALL)))

run all:
	@bash $(RUNNER) $(ARCH) $(ALL_LIST)

clean:
	@rm -rf build
	@find . -mindepth 2 -name build -type d -exec rm -rf {} +

help:
	@echo "Usage:"
	@echo "  make -C am-apps/contracts ARCH=riscv32e-ysyxsoc run"
	@echo "  make -C am-apps/contracts ARCH=riscv32e-npc ALL='klib/string klib/stdio' run"
	@echo "  make -C am-apps/contracts ARCH=riscv32-nemu ALL=cte/yield run"
	@echo "  make -C am-apps/contracts ARCH=riscv32e-ysyxsoc GROUP=platform run"
