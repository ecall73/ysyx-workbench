include $(AM_HOME)/scripts/isa/riscv.mk
include $(AM_HOME)/scripts/platform/nemu.mk
CFLAGS  += -DISA_H=\"riscv/riscv.h\"
COMMON_CFLAGS += -march=rv32gc -mabi=ilp32d # overwrite
ASFLAGS       += -DFLEN=64
LDFLAGS       += -melf32lriscv                     # overwrite
KLIB_PICOLIBC_MULTILIB := rv32imafdc/ilp32d

AM_SRCS += riscv/nemu/start.S \
           riscv/nemu/cte.c \
           riscv/nemu/trap.S \
           riscv/nemu/vme.c
