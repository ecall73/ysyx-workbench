#include <am.h>
#include "include/npc.h"
#include <klib.h>
#include <klib-macros.h>

extern char _heap_start;
int main(const char *args);

extern char _pmem_start;
#define PMEM_SIZE (128 * 1024 * 1024)
#define PMEM_END  ((uintptr_t)&_pmem_start + PMEM_SIZE)

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
  asm volatile("ebreak");
  while (1);
}

void _trm_init() {
  uint32_t vendor = 0, arch = 0;
  uint32_t t0 = 0, t1 = 0, t2 = 0;
  asm volatile("csrr %0, mvendorid" : "=r"(vendor));
  asm volatile("csrr %0, marchid" : "=r"(arch));
  t0 = inl(CLINT_MTIME);
  t1 = inl(CLINT_MTIME);
  t2 = inl(CLINT_MTIME);
  check_trm_state();
  assert(t0 <= t1 && t1 <= t2);
  printf("CSR mvendorid=0x%08x marchid=%u(0x%08x)\n", vendor, arch, arch);
  printf("CLINT mtime samples: %u -> %u -> %u\n", t0, t1, t2);

  int ret = main(mainargs);
  halt(ret);
}
