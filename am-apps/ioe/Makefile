.PHONY: run all image clean help

ARCH ?= riscv32e-ysyxsoc

DEFAULT_ALL = keyboard-visible uart-visible timer-visible gpu-pattern gpio-visible

comma := ,
empty :=
space := $(empty) $(empty)
ALL_LIST := $(strip $(subst $(comma),$(space),$(if $(ALL),$(ALL),$(DEFAULT_ALL))))

run all image:
	@set -e; \
	for t in $(ALL_LIST); do \
	  echo "[ioe] RUN  $(ARCH) $$t $(MAKECMDGOALS)"; \
	  $(MAKE) -C $$t ARCH=$(ARCH) $(MAKECMDGOALS); \
	done

clean:
	@rm -rf build
	@find . -mindepth 2 -maxdepth 2 -name build -type d -exec rm -rf {} +

help:
	@echo "Usage:"
	@echo "  make -C am-apps/ioe ARCH=riscv32e-ysyxsoc run"
	@echo "  make -C am-apps/ioe ARCH=riscv32e-ysyxsoc ALL='keyboard-visible gpio-visible' run"
	@echo "  make -C am-apps/ioe ARCH=riscv32e-npc ALL=timer-visible,uart-visible image"
