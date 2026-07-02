.PHONY: run all clean help

ARCH ?= riscv32e-ysyxsoc
RUNNER := $(CURDIR)/run-contracts.sh

ALL_LIST := $(strip $(subst ,, ,$(ALL)))

run all:
	@bash $(RUNNER) $(ARCH) $(ALL_LIST)

clean:
	@rm -rf build
	@find . -mindepth 2 -maxdepth 2 -name build -type d -exec rm -rf {} +

help:
	@echo "Usage:"
	@echo "  make -C am-apps/contracts ARCH=riscv32e-ysyxsoc run"
	@echo "  make -C am-apps/contracts ARCH=riscv32e-npc ALL='03-klib-string 04-klib-stdio' run"
	@echo "  make -C am-apps/contracts ARCH=riscv32-nemu ALL=10-cte-yield run"
