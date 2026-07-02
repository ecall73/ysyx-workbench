CONTRACT_ID = platform/ysyxsoc-layout-flash-sdram
CONTRACT_GROUP = platform
CONTRACT_ARCHS = riscv32e-ysyxsoc
CONTRACT_ROOT = ../..

ARCH ?= riscv32e-ysyxsoc
ifeq ($(filter $(ARCH),$(CONTRACT_ARCHS)),)
$(error contract $(CONTRACT_ID) does not support ARCH=$(ARCH); supported: $(CONTRACT_ARCHS))
endif

.PHONY: run image clean

run image:
	@echo "CONTRACT $(CONTRACT_ID) BEGIN"
	@grep -q "flash (rx)" linker-flash-sdram.ld
	@grep -q "sdram (rwx)" linker-flash-sdram.ld
	@grep -q "_data_start" linker-flash-sdram.ld
	@grep -q "_data_load_start" linker-flash-sdram.ld
	@grep -q "_heap_end = ORIGIN(sdram) + LENGTH(sdram)" linker-flash-sdram.ld
	@echo "CONTRACT $(CONTRACT_ID) PASS"

clean:
	@rm -rf build
