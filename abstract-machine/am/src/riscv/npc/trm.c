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

static inline uint64_t read_mtime() {
  uint32_t hi1, lo, hi2;
  do {
    hi1 = inl(CLINT_MTIMEH);
    lo = inl(CLINT_MTIME);
    hi2 = inl(CLINT_MTIMEH);
  } while (hi1 != hi2);
  return ((uint64_t)hi1 << 32) | lo;
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
  uint64_t t0 = 0, t1 = 0, t2 = 0;
  asm volatile("csrr %0, mvendorid" : "=r"(vendor));
  asm volatile("csrr %0, marchid" : "=r"(arch));
  t0 = read_mtime();
  t1 = read_mtime();
  t2 = read_mtime();
  printf("CSR mvendorid=0x%08x marchid=%u(0x%08x)\n", vendor, arch, arch);
  printf("CLINT mtime samples: 0x%08x%08x -> 0x%08x%08x -> 0x%08x%08x\n",
      (uint32_t)(t0 >> 32), (uint32_t)t0,
      (uint32_t)(t1 >> 32), (uint32_t)t1,
      (uint32_t)(t2 >> 32), (uint32_t)t2);

  int ret = main(mainargs);
  halt(ret);
}
