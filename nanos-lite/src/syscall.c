#include <common.h>
#include "syscall.h"

static const char *syscall_name(uintptr_t no) {
  switch (no) {
    case SYS_exit: return "exit";
    case SYS_yield: return "yield";
    default: return "unknown";
  }
}

void do_syscall(Context *c) {
  uintptr_t a[4];
  a[0] = c->GPR1;
  a[1] = c->GPR2;
  a[2] = c->GPR3;
  a[3] = c->GPR4;

  const char *name = syscall_name(a[0]);
  Log("strace: %s(%p, %p, %p)", name, (void *)a[1], (void *)a[2],
      (void *)a[3]);

  switch (a[0]) {
    case SYS_exit:
      halt((int)a[1]);
      break;
    case SYS_yield:
      yield();
      c->GPRx = 0;
      break;
    default: panic("Unhandled syscall ID = %d", a[0]);
  }

  Log("strace: %s -> %p", name, (void *)c->GPRx);
}
