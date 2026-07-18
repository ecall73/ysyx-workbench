#include <common.h>
#include "syscall.h"
void do_syscall(Context *c) {
  uintptr_t a[4];
  a[0] = c->GPR1;
  a[1] = c->GPR2;
  a[2] = c->GPR3;
  a[3] = c->GPR4;

#if STRACE
  const char *name;
  switch (a[0]) {
    case SYS_exit:  name = "exit";  break;
    case SYS_yield: name = "yield"; break;
    case SYS_write: name = "write"; break;
    case SYS_brk:   name = "brk";   break;
    default:        name = "unknown";
  }
  Log("strace: %s(%p, %p, %p)", name, (void *)a[1], (void *)a[2], (void *)a[3]);
#endif

  switch (a[0]) {
    case SYS_exit:
      halt((int)a[1]);
      break;
    case SYS_yield:
      yield();
      c->GPRx = 0;
      break;
    case SYS_write:
      assert(a[1] == 1 || a[1] == 2);
      for (size_t i = 0; i < a[3]; i++) {
        putch(((const char *)a[2])[i]);
      }
      c->GPRx = a[3];
      break;
    case SYS_brk:
      c->GPRx = 0;
      break;
    default: panic("Unhandled syscall ID = %d", a[0]);
  }

#if STRACE
  Log("strace: %s -> %p", name, (void *)c->GPRx);
#endif
}
