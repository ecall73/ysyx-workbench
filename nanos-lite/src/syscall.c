#include <common.h>
#include "syscall.h"
void do_syscall(Context *c) {
  uintptr_t a[4];
  a[0] = c->GPR1;
  a[1] = c->GPR2;
  a[2] = c->GPR3;
  a[3] = c->GPR4;

  switch (a[0]) {
    case SYS_exit:
#if STRACE
      Log("strace: exit(%p, %p, %p)", (void *)a[1], (void *)a[2], (void *)a[3]);
#endif
      halt((int)a[1]);
      break;
    case SYS_yield:
#if STRACE
      Log("strace: yield(%p, %p, %p)", (void *)a[1], (void *)a[2], (void *)a[3]);
#endif
      yield();
      c->GPRx = 0;
#if STRACE
      Log("strace: yield -> %p", (void *)c->GPRx);
#endif
      break;
    case SYS_write:
#if STRACE
      Log("strace: write(%p, %p, %p)", (void *)a[1], (void *)a[2], (void *)a[3]);
#endif
      assert(a[1] == 1 || a[1] == 2);
      for (size_t i = 0; i < a[3]; i++) {
        putch(((const char *)a[2])[i]);
      }
      c->GPRx = a[3];
#if STRACE
      Log("strace: write -> %p", (void *)c->GPRx);
#endif
      break;
    default: panic("Unhandled syscall ID = %d", a[0]);
  }
}
