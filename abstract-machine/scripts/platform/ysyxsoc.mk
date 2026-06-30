AM_SRCS := riscv/ysyxsoc/start.S \
           riscv/ysyxsoc/trm.c \
           riscv/ysyxsoc/ioe.c \
           riscv/ysyxsoc/gpu.c \
           riscv/ysyxsoc/timer.c \
           riscv/ysyxsoc/input.c \
           riscv/ysyxsoc/cte.c \
           riscv/ysyxsoc/trap.S \
           riscv/ysyxsoc/vme.c \
           riscv/ysyxsoc/mpe.c

CFLAGS    += -fdata-sections -ffunction-sections
LDSCRIPTS += $(AM_HOME)/scripts/linker-ysyxsoc.ld
LDFLAGS   += --defsym=_pmem_start=0x30000000 --defsym=_entry_offset=0x0
LDFLAGS   += --gc-sections -e _start

YSYXSOCFLAGS += -l $(shell dirname $(IMAGE).elf)/npc-log.txt
YSYXSOCFLAGS += -f $(IMAGE).elf
YSYXSOCFLAGS += -F $(shell dirname $(IMAGE).elf)/npc-ftrace.txt
YSYXSOCFLAGS += -E $(shell dirname $(IMAGE).elf)/npc-etrace.txt
YSYXSOCFLAGS += -M $(shell dirname $(IMAGE).elf)/npc-mtrace.txt
YSYXSOCFLAGS += -D $(shell dirname $(IMAGE).elf)/npc-dtrace.txt
BATCH ?= 1
ifneq ($(filter 1 y yes true,$(BATCH)),)
YSYXSOCFLAGS += -b
endif

DIFF ?= 0
PERF ?= 0
WAVE ?= 0
DEBUG ?= 0
DIFF_REF_SO ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-so
DIFF_PORT ?= 1234
YSYXSOC_TRACE_VARS :=
ifneq ($(origin TRACE),undefined)
YSYXSOC_TRACE_VARS += TRACE=$(TRACE)
endif
ifneq ($(origin ITRACE),undefined)
YSYXSOC_TRACE_VARS += ITRACE=$(ITRACE)
endif
ifneq ($(origin FTRACE),undefined)
YSYXSOC_TRACE_VARS += FTRACE=$(FTRACE)
endif
ifneq ($(origin MTRACE),undefined)
YSYXSOC_TRACE_VARS += MTRACE=$(MTRACE)
endif
ifneq ($(origin DTRACE),undefined)
YSYXSOC_TRACE_VARS += DTRACE=$(DTRACE)
endif
ifneq ($(origin ETRACE),undefined)
YSYXSOC_TRACE_VARS += ETRACE=$(ETRACE)
endif

MAINARGS_MAX_LEN = 64
MAINARGS_PLACEHOLDER = the_insert-arg_rule_in_Makefile_will_insert_mainargs_here
CFLAGS += -DMAINARGS_MAX_LEN=$(MAINARGS_MAX_LEN) -DMAINARGS_PLACEHOLDER=$(MAINARGS_PLACEHOLDER)

insert-arg: image
	@python $(AM_HOME)/tools/insert-arg.py $(IMAGE).bin $(MAINARGS_MAX_LEN) $(MAINARGS_PLACEHOLDER) "$(mainargs)"

image: image-dep
	@$(OBJDUMP) -d $(IMAGE).elf > $(IMAGE).txt
	@echo + OBJCOPY "->" $(IMAGE_REL).bin
	@$(OBJCOPY) -S -O binary $(IMAGE).elf $(IMAGE).bin

run: insert-arg
	$(MAKE) -C $(AM_HOME)/../npc SIM_MODE=ysyxsoc DIFF=$(DIFF) PERF=$(PERF) WAVE=$(WAVE) DEBUG=$(DEBUG) BATCH=$(BATCH) $(YSYXSOC_TRACE_VARS) DIFF_REF_SO=$(DIFF_REF_SO) DIFF_PORT=$(DIFF_PORT) sim ARGS="$(YSYXSOCFLAGS)" IMG="$(IMAGE).bin"

.PHONY: insert-arg
