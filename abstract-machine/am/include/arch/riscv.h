#ifndef ARCH_H__
#define ARCH_H__

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
#define AM_RISCV_STATIC_ASSERT(cond, msg) static_assert(cond, msg)
#else
#define AM_RISCV_STATIC_ASSERT(cond, msg) _Static_assert(cond, msg)
#endif

#ifdef __riscv_e
#define NR_REGS 16
#else
#define NR_REGS 32
#endif

struct Context {
  // Must match abstract-machine/am/src/riscv/{nemu,npc,ysyxsoc}/trap.S.
  uintptr_t gpr[NR_REGS], mcause, mstatus, mepc;
  void *pdir;
};

AM_RISCV_STATIC_ASSERT(offsetof(struct Context, gpr) == 0,
    "RISC-V Context ABI mismatch: gpr");
AM_RISCV_STATIC_ASSERT(offsetof(struct Context, mcause) == NR_REGS * sizeof(uintptr_t),
    "RISC-V Context ABI mismatch: mcause");
AM_RISCV_STATIC_ASSERT(offsetof(struct Context, mstatus) == (NR_REGS + 1) * sizeof(uintptr_t),
    "RISC-V Context ABI mismatch: mstatus");
AM_RISCV_STATIC_ASSERT(offsetof(struct Context, mepc) == (NR_REGS + 2) * sizeof(uintptr_t),
    "RISC-V Context ABI mismatch: mepc");
AM_RISCV_STATIC_ASSERT(offsetof(struct Context, pdir) == (NR_REGS + 3) * sizeof(uintptr_t),
    "RISC-V Context ABI mismatch: pdir");
AM_RISCV_STATIC_ASSERT(sizeof(struct Context) == (NR_REGS + 4) * sizeof(uintptr_t),
    "RISC-V Context ABI mismatch: size");

#undef AM_RISCV_STATIC_ASSERT

#ifdef __riscv_e
#define GPR1 gpr[15] // a5
#else
#define GPR1 gpr[17] // a7
#endif

#define GPR2 gpr[0]
#define GPR3 gpr[0]
#define GPR4 gpr[0]
#define GPRx gpr[0]

#endif
