#include <am.h>
#include <nemu.h>
#include <klib.h>

extern char _heap_start;
int main(const char *args);

Area heap = RANGE(&_heap_start, PMEM_END);
static const char mainargs[MAINARGS_MAX_LEN] = TOSTRING(MAINARGS_PLACEHOLDER); // defined in CFLAGS

static bool mainargs_has_nul(void) {
  for (int i = 0; i < MAINARGS_MAX_LEN; i++) {
    if (mainargs[i] == '\0') return true;
  }
  return false;
}

static void check_trm_state(void) {
  assert(heap.start != NULL && heap.end != NULL && heap.start < heap.end);
  assert(((uintptr_t)heap.start % sizeof(uintptr_t)) == 0 &&
         ((uintptr_t)heap.end % sizeof(uintptr_t)) == 0);
  assert(mainargs_has_nul());
}

void putch(char ch) {
  outb(SERIAL_PORT, ch);
}

void halt(int code) {
  nemu_trap(code);

  // should not reach here
  while (1);
}

void _trm_init() {
  check_trm_state();
  int ret = main(mainargs);
  halt(ret);
}
