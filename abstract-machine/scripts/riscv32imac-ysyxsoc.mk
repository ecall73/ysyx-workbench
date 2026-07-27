include $(AM_HOME)/scripts/isa/riscv.mk
include $(AM_HOME)/scripts/platform/ysyxsoc.mk
ISA := riscv32
COMMON_CFLAGS += -march=rv32imac_zicsr_zifencei -mabi=ilp32
LDFLAGS       += -melf32lriscv
KLIB_PICOLIBC_MULTILIB := rv32imac/ilp32

AM_SRCS += riscv/npc/libgcc/div.S \
           riscv/npc/libgcc/muldi3.S \
           riscv/npc/libgcc/multi3.c \
           riscv/npc/libgcc/ashldi3.c \
           riscv/npc/libgcc/unused.c
