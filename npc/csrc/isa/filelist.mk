INC_PATH += $(NPC_HOME)/csrc/isa/$(GUEST_ISA)/include
INC_PATH += $(NEMU_HOME)/include
DIRS-y += csrc/isa/$(GUEST_ISA)
RISCV_DIFFTEST_HEADER := $(NEMU_HOME)/include/riscv-difftest.h
