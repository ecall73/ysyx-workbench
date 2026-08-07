#ifndef __CPU_DIFFTEST_H__
#define __CPU_DIFFTEST_H__

#include <common.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef CONFIG_DIFFTEST
void difftest_step(vaddr_t pc, vaddr_t dnpc, uint32_t inst,
    uint32_t instruction_length, uint32_t instruction_valid);
void difftest_raise_intr(uint32_t cause, vaddr_t pretrap_pc);
#else
static inline void difftest_step(vaddr_t pc, vaddr_t dnpc, uint32_t inst,
    uint32_t instruction_length, uint32_t instruction_valid) {
  (void)pc;
  (void)dnpc;
  (void)inst;
  (void)instruction_length;
  (void)instruction_valid;
}
static inline void difftest_raise_intr(uint32_t cause, vaddr_t pretrap_pc) {
  (void)cause;
  (void)pretrap_pc;
}
#endif

#ifdef __cplusplus
}
#endif

#endif
