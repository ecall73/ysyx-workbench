#ifndef __RISCV32_EXCEPTION_H__
#define __RISCV32_EXCEPTION_H__

#include <isa.h>
#include <setjmp.h>

typedef struct {
  word_t cause;
  vaddr_t epc;
  word_t tval;
  int access_type;
} riscv_exception_t;

extern jmp_buf riscv_exception_env;

void riscv_exception_begin(vaddr_t epc);
void riscv_exception_set_instruction(word_t instruction_bits);
void riscv_exception_end(void);
const riscv_exception_t *riscv_exception_current(void);
vaddr_t riscv_deliver_exception(const riscv_exception_t *exception);
vaddr_t riscv_take_trap(word_t cause, vaddr_t epc, word_t tval);

#endif
