#include <isa.h>
#include "../local-include/exception.h"

jmp_buf riscv_exception_env;

static bool exception_active;
static vaddr_t exception_epc;
static word_t faulting_instruction_bits;
static riscv_exception_t current_exception;

void riscv_exception_begin(vaddr_t epc) {
  Assert(!exception_active, "nested RISC-V exception boundary at pc=" FMT_WORD, epc);
  exception_active = true;
  exception_epc = epc;
  faulting_instruction_bits = 0;
  current_exception = (riscv_exception_t){};
}

void riscv_exception_set_instruction(word_t instruction_bits) {
  Assert(exception_active, "RISC-V instruction outside an exception boundary");
  faulting_instruction_bits = instruction_bits;
}

void riscv_exception_end(void) {
  exception_active = false;
}

const riscv_exception_t *riscv_exception_current(void) {
  Assert(exception_active, "RISC-V exception queried outside an exception boundary");
  return &current_exception;
}

void riscv_raise_exception(word_t cause, word_t tval, int access_type) {
  Assert(exception_active,
      "RISC-V exception outside an architecture step: cause=%u tval=" FMT_WORD,
      cause, tval);
  current_exception = (riscv_exception_t) {
    .cause = cause,
    .epc = exception_epc,
    .tval = tval,
    .access_type = access_type,
  };
  longjmp(riscv_exception_env, 1);
}

void riscv_raise_memory_fault(vaddr_t addr, int type, bool page_fault) {
  word_t cause;
  switch (type) {
    case MEM_TYPE_IFETCH: cause = page_fault ? 12 : 1; break;
    case MEM_TYPE_READ:   cause = page_fault ? 13 : 5; break;
    case MEM_TYPE_WRITE:  cause = page_fault ? 15 : 7; break;
    default: panic("invalid RISC-V memory fault type: %d", type);
  }
  riscv_raise_exception(cause, addr, type);
}

void riscv_raise_illegal_instruction(void) {
  riscv_raise_exception(2, faulting_instruction_bits, MEM_TYPE_NONE);
}

static bool panic_on_exception(word_t cause) {
#ifndef CONFIG_RISCV_EXCEPTION_PANIC
  (void)cause;
  return false;
#else
  switch (cause) {
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_1_INSTRUCTION_ACCESS_FAULT
    case 1: return true;
#endif
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_2_ILLEGAL_INSTRUCTION
    case 2: return true;
#endif
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_4_LOAD_ADDRESS_MISALIGNED
    case 4: return true;
#endif
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_5_LOAD_ACCESS_FAULT
    case 5: return true;
#endif
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_6_STORE_AMO_ADDRESS_MISALIGNED
    case 6: return true;
#endif
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_7_STORE_AMO_ACCESS_FAULT
    case 7: return true;
#endif
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_8_ECALL_FROM_U_MODE
    case 8: return true;
#endif
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_9_ECALL_FROM_S_MODE
    case 9: return true;
#endif
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_11_ECALL_FROM_M_MODE
    case 11: return true;
#endif
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_12_INSTRUCTION_PAGE_FAULT
    case 12: return true;
#endif
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_13_LOAD_PAGE_FAULT
    case 13: return true;
#endif
#ifdef CONFIG_EXCEPTION_PANIC_CAUSE_15_STORE_AMO_PAGE_FAULT
    case 15: return true;
#endif
    default: return false;
  }
#endif
}

vaddr_t riscv_deliver_exception(const riscv_exception_t *exception) {
  Assert(exception != NULL, "null RISC-V exception");
  if (panic_on_exception(exception->cause)) {
    panic("configured RISC-V exception panic: cause=%u epc=" FMT_WORD
        " tval=" FMT_WORD " access_type=%d", exception->cause, exception->epc,
        exception->tval, exception->access_type);
  }
  return riscv_take_trap(exception->cause, exception->epc, exception->tval);
}
