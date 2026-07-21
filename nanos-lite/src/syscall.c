#include <common.h>
#include <fs.h>
#include <proc.h>
#include <sys/time.h>
#include "syscall.h"

static int sys_execve(const char *filename, char *const argv[], char *const envp[]) {
  int fd = fs_open(filename, 0, 0);
  if (fd < 0) {
    return -2;
  }
  fs_close(fd);

  context_uload(current, filename, argv, envp);
  switch_boot_pcb();
  yield();
  panic("execve returned unexpectedly");
}

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
    case SYS_open:  name = "open";  break;
    case SYS_read:  name = "read";  break;
    case SYS_write: name = "write"; break;
    case SYS_close: name = "close"; break;
    case SYS_lseek: name = "lseek"; break;
    case SYS_brk:   name = "brk";   break;
    case SYS_gettimeofday: name = "gettimeofday"; break;
    case SYS_execve: name = "execve"; break;
    default:        name = "unknown";
  }
  switch (a[0]) {
    case SYS_open:
      Log("strace: open(%s, %p, %p)", (const char *)a[1], (void *)a[2], (void *)a[3]);
      break;
    case SYS_read:
    case SYS_write:
    case SYS_lseek:
      Log("strace: %s(%s, %p, %p)", name, fs_file_name((int)a[1]), (void *)a[2], (void *)a[3]);
      break;
    case SYS_close:
      Log("strace: close(%s)", fs_file_name((int)a[1]));
      break;
    default:
      Log("strace: %s(%p, %p, %p)", name, (void *)a[1], (void *)a[2], (void *)a[3]);
  }
#endif

  switch (a[0]) {
    case SYS_yield:
      yield();
      c->GPRx = 0;
      break;
    case SYS_open:
      c->GPRx = fs_open((const char *)a[1], a[2], a[3]);
      break;
    case SYS_read:
      c->GPRx = fs_read(a[1], (void *)a[2], a[3]);
      break;
    case SYS_write:
      c->GPRx = fs_write(a[1], (const void *)a[2], a[3]);
      break;
    case SYS_close:
      c->GPRx = fs_close(a[1]);
      break;
    case SYS_lseek:
      c->GPRx = fs_lseek(a[1], a[2], a[3]);
      break;
    case SYS_brk:
      c->GPRx = 0;
      break;
    case SYS_gettimeofday: {
      AM_TIMER_UPTIME_T uptime = io_read(AM_TIMER_UPTIME);
      struct timeval *tv = (struct timeval *)a[1];
      struct timezone *tz = (struct timezone *)a[2];
      if (tv != NULL) {
        tv->tv_sec = uptime.us / 1000000;
        tv->tv_usec = uptime.us % 1000000;
      }
      if (tz != NULL) {
        tz->tz_minuteswest = 0;
        tz->tz_dsttime = 0;
      }
      c->GPRx = 0;
      break;
    }
    case SYS_exit: {
      char *const argv[] = { "/bin/nterm", NULL };
      char *const envp[] = { NULL };
      sys_execve("/bin/nterm", argv, envp);
      return;
    }
    case SYS_execve:
      c->GPRx = sys_execve((const char *)a[1], (char *const *)a[2], (char *const *)a[3]);
      break;
    default: panic("Unhandled syscall ID = %d", a[0]);
  }

#if STRACE
  if (a[0] == SYS_open) {
    Log("strace: open -> %s", fs_file_name((int)c->GPRx));
  } else {
    Log("strace: %s -> %p", name, (void *)c->GPRx);
  }
#endif
}
