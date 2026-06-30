#ifndef __NPC_CPU_DIFFTEST_INTERNAL_H__
#define __NPC_CPU_DIFFTEST_INTERNAL_H__

#include <stddef.h>
#include <stdint.h>

#include "cpu/cpu.h"

enum { DIFFTEST_TO_DUT = 0, DIFFTEST_TO_REF = 1 };

typedef struct {
  uint32_t gpr[32];
  uint32_t pc;
  // Keep this order in sync with nemu/src/isa/riscv32/include/isa-def.h.
  uint32_t mstatus;
  uint32_t mtvec;
  uint32_t mepc;
  uint32_t mcause;
} RefCPUState;

extern bool difftest_enabled;
extern void (*ref_difftest_memcpy)(uint32_t addr, void *buf, size_t n, bool direction);
extern void (*ref_difftest_regcpy)(void *dut, bool direction);
extern void (*ref_difftest_exec)(uint64_t n);
extern void (*ref_difftest_raise_intr)(uint64_t NO);

void difftest_init_ref_regs();

#endif
