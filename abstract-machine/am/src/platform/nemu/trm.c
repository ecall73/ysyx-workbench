#include <am.h>
#include <nemu.h>

extern char _heap_start;
int main(const char *args);

Area heap = RANGE(&_heap_start, PMEM_END);
static const char mainargs[MAINARGS_MAX_LEN] = TOSTRING(MAINARGS_PLACEHOLDER); // defined in CFLAGS

_Static_assert(MAINARGS_MAX_LEN > 0, "MAINARGS_MAX_LEN must be positive");
_Static_assert(sizeof(TOSTRING(MAINARGS_PLACEHOLDER)) <= MAINARGS_MAX_LEN,
    "mainargs placeholder exceeds MAINARGS_MAX_LEN");

void putch(char ch) {
  outb(SERIAL_PORT, ch);
}

void halt(int code) {
  nemu_trap(code);

  // should not reach here
  while (1);
}

void _trm_init() {
  int ret = main(mainargs);
  halt(ret);
}
