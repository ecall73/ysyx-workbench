#ifndef __ISA_RISCV_H__
#define __ISA_RISCV_H__

#include <common.h>

typedef struct {
  word_t gpr[32];
  vaddr_t pc;
  // Architecturally committed state projected into the RV32IMAC DiffTest ABI.
  word_t priv;
  word_t mstatus, mtvec, mepc, mcause, mtval;
  word_t medeleg, mideleg, mie;
  word_t stvec, sepc, scause, stval, sscratch, satp;
  word_t mscratch, menvcfgh, mcounteren, scounteren, mcountinhibit;
} riscv32_CPU_state;

// decode
typedef struct {
  uint32_t inst;
} riscv32_ISADecodeInfo;

#endif
