include $(AM_HOME)/scripts/isa/riscv.mk
include $(AM_HOME)/scripts/platform/nemu.mk

# Keep the established NEMU RISC-V backend while giving software an explicit
# RV32IMAC/ILP32 build profile distinct from riscv32-nemu's RV32GC/ILP32D.
ISA := riscv32
CFLAGS  += -DISA_H=\"riscv/riscv.h\"
COMMON_CFLAGS += -march=rv32imac_zicsr_zifencei -mabi=ilp32
LDFLAGS       += -melf32lriscv
KLIB_PICOLIBC_MULTILIB := rv32imac/ilp32

AM_SRCS += riscv/nemu/start.S \
           riscv/nemu/cte.c \
           riscv/nemu/trap.S \
           riscv/nemu/vme.c
