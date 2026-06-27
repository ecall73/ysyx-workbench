AM_SRCS := riscv/npc/start.S \
           riscv/npc/trm.c \
           riscv/npc/ioe.c \
           riscv/npc/timer.c \
           riscv/npc/input.c \
           riscv/npc/cte.c \
           riscv/npc/trap.S \
           platform/dummy/vme.c \
           platform/dummy/mpe.c

CFLAGS    += -fdata-sections -ffunction-sections
LDSCRIPTS += $(AM_HOME)/scripts/linker.ld
LDFLAGS   += --defsym=_pmem_start=0x80000000 --defsym=_entry_offset=0x0
LDFLAGS   += --gc-sections -e _start

NPCFLAGS += -l $(shell dirname $(IMAGE).elf)/npc-log.txt
DEBUG ?= 0
ifeq ($(filter 1 y yes true,$(DEBUG)),)
NPCFLAGS += -b
endif

DIFF ?= 0
PERF ?= 0
WAVE ?= 0
DIFF_REF_SO ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-so
DIFF_PORT ?= 1234

ifneq ($(filter-out 0 1,$(DIFF)),)
$(error Unsupported DIFF='$(DIFF)'. Expected '0' or '1')
endif
ifneq ($(filter-out 0 1,$(PERF)),)
$(error Unsupported PERF='$(PERF)'. Expected '0' or '1')
endif
ifneq ($(filter-out 0 1,$(WAVE)),)
$(error Unsupported WAVE='$(WAVE)'. Expected '0' or '1')
endif

ifeq ($(DIFF),1)
ifeq ($(strip $(NEMU_HOME)),)
$(error NEMU_HOME is required when DIFF=1)
endif
NPCFLAGS += -d $(DIFF_REF_SO) -p $(DIFF_PORT)
endif

MAINARGS_MAX_LEN = 64
MAINARGS_PLACEHOLDER = the_insert-arg_rule_in_Makefile_will_insert_mainargs_here
CFLAGS += -DMAINARGS_MAX_LEN=$(MAINARGS_MAX_LEN) -DMAINARGS_PLACEHOLDER=$(MAINARGS_PLACEHOLDER)

insert-arg: image
	@python $(AM_HOME)/tools/insert-arg.py $(IMAGE).bin $(MAINARGS_MAX_LEN) $(MAINARGS_PLACEHOLDER) "$(mainargs)"

image: image-dep
	@$(OBJDUMP) -d $(IMAGE).elf > $(IMAGE).txt
	@echo + OBJCOPY "->" $(IMAGE_REL).bin
	@$(OBJCOPY) -S --set-section-flags .bss=alloc,contents -O binary $(IMAGE).elf $(IMAGE).bin

run: insert-arg
	$(MAKE) -C $(AM_HOME)/../npc SIM_MODE=npc DIFF=0 PERF=$(PERF) WAVE=$(WAVE) sim ARGS="$(NPCFLAGS) $(IMAGE).bin"

.PHONY: insert-arg
