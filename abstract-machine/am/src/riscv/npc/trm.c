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

void putch(char ch) {
  outb(SERIAL_PORT, ch);
}

void halt(int code) {
  asm volatile("ebreak");
  while (1);
}

void _trm_init() {
  uint32_t vendor = 0, arch = 0;
  uint32_t c0 = 0, c1 = 0, c2 = 0;
  asm volatile("csrr %0, mvendorid" : "=r"(vendor));
  asm volatile("csrr %0, marchid" : "=r"(arch));
  asm volatile("csrr %0, mcycle" : "=r"(c0));
  asm volatile("csrr %0, mcycle" : "=r"(c1));
  asm volatile("csrr %0, mcycle" : "=r"(c2));
  printf("CSR mvendorid=0x%08x marchid=%u(0x%08x)\n", vendor, arch, arch);
  printf("CSR mcycle samples: %u -> %u -> %u\n", c0, c1, c2);

  int ret = main(mainargs);
  halt(ret);
}
