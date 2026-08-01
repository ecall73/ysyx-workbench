#ifndef __ISA_RISCV_H__
#define __ISA_RISCV_H__

#include <common.h>

typedef struct {
  word_t gpr[32];
  vaddr_t pc;
  // Committed RTL state. DiffTest projects it into the versioned RV32E ABI.
  word_t mstatus, mtvec, mepc, mcause, satp;
} riscv32_CPU_state;

// decode
typedef struct {
  uint32_t inst;
} riscv32_ISADecodeInfo;

#endif
