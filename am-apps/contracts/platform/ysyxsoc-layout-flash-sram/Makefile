CONTRACT_ID = platform/ysyxsoc-layout-flash-sram
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
	@grep -q "flash (rx)" linker-flash-sram.ld
	@grep -q "sram  (rwx)" linker-flash-sram.ld
	@grep -q "_data_start" linker-flash-sram.ld
	@grep -q "_data_load_start" linker-flash-sram.ld
	@grep -q "_heap_end = _stack_pointer - 0x400" linker-flash-sram.ld
	@echo "CONTRACT $(CONTRACT_ID) PASS"

clean:
	@rm -rf build
