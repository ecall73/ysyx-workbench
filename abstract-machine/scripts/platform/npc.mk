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
NPCFLAGS += -f $(IMAGE).elf
NPCFLAGS += -F $(shell dirname $(IMAGE).elf)/npc-ftrace.txt
NPCFLAGS += -E $(shell dirname $(IMAGE).elf)/npc-etrace.txt
NPCFLAGS += -M $(shell dirname $(IMAGE).elf)/npc-mtrace.txt
NPCFLAGS += -D $(shell dirname $(IMAGE).elf)/npc-dtrace.txt
BATCH ?= 1
ifneq ($(filter 1 y yes true,$(BATCH)),)
NPCFLAGS += -b
endif

DIFF ?= 0
PERF ?= 0
WAVE ?= 0
DEBUG ?= 0
DIFF_REF_SO ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-so
DIFF_PORT ?= 1234
NPC_TRACE_VARS :=
ifneq ($(origin TRACE),undefined)
NPC_TRACE_VARS += TRACE=$(TRACE)
endif
ifneq ($(origin ITRACE),undefined)
NPC_TRACE_VARS += ITRACE=$(ITRACE)
endif
ifneq ($(origin FTRACE),undefined)
NPC_TRACE_VARS += FTRACE=$(FTRACE)
endif
ifneq ($(origin MTRACE),undefined)
NPC_TRACE_VARS += MTRACE=$(MTRACE)
endif
ifneq ($(origin DTRACE),undefined)
NPC_TRACE_VARS += DTRACE=$(DTRACE)
endif
ifneq ($(origin ETRACE),undefined)
NPC_TRACE_VARS += ETRACE=$(ETRACE)
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
	$(MAKE) -C $(AM_HOME)/../npc SIM_MODE=npc DIFF=$(DIFF) PERF=$(PERF) WAVE=$(WAVE) DEBUG=$(DEBUG) BATCH=$(BATCH) $(NPC_TRACE_VARS) DIFF_REF_SO=$(DIFF_REF_SO) DIFF_PORT=$(DIFF_PORT) sim ARGS="$(NPCFLAGS)" IMG="$(IMAGE).bin"

.PHONY: insert-arg
