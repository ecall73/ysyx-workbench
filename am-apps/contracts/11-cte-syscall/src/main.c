#define CONTRACT_ID "11-cte-syscall"
#include <contract.h>

static volatile int syscall_count = 0;

static Context *handler(Event ev, Context *ctx) {
  CONTRACT_CHECK(ev.event == EVENT_SYSCALL, "event-syscall");
  syscall_count++;
  return ctx;
}

static inline void do_syscall_ecall(void) {
#ifdef __riscv_e
  asm volatile("li a5, 1; ecall" ::: "a5", "memory");
#else
  asm volatile("li a7, 1; ecall" ::: "a7", "memory");
#endif
}

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(cte_init(handler), "cte-init");
  do_syscall_ecall();
  CONTRACT_CHECK(syscall_count == 1, "syscall-return");
  contract_pass();
}
