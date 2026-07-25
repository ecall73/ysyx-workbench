#include <isa.h>
#include <cpu/difftest.h>
#include "../local-include/csr.h"
#include "../local-include/timer.h"

#define CLINT_BASE            0x02000000u
#define CLINT_SIZE            0x10000u
#define CLINT_MTIMECMP_OFFSET 0x4000u
#define CLINT_MTIME_OFFSET    0xbff8u

static uint32_t lower_half(uint64_t value) {
  return (uint32_t)value;
}

static uint32_t upper_half(uint64_t value) {
  return (uint32_t)(value >> 32);
}

static uint64_t replace_half(uint64_t old, uint32_t value, bool upper) {
  return upper ? ((uint64_t)value << 32) | lower_half(old)
               : ((uint64_t)upper_half(old) << 32) | value;
}

static bool in_clint(paddr_t addr) {
  return addr >= CLINT_BASE && addr < CLINT_BASE + CLINT_SIZE;
}

bool riscv_clint_read(paddr_t addr, int len, word_t *data) {
  if (!in_clint(addr)) return false;
  Assert(len == 4, "CLINT only supports 32-bit accesses: addr=" FMT_PADDR " len=%d",
      addr, len);
  difftest_skip_ref();

  uint32_t offset = addr - CLINT_BASE;
  bool upper = offset & 4;
  switch (offset & ~4u) {
    case CLINT_MTIMECMP_OFFSET:
      *data = upper ? upper_half(cpu.mtimecmp) : lower_half(cpu.mtimecmp);
      break;
    case CLINT_MTIME_OFFSET:
      *data = upper ? upper_half(cpu.mtime) : lower_half(cpu.mtime);
      break;
    default:
      panic("unsupported CLINT read: addr=" FMT_PADDR " len=%d", addr, len);
  }
  return true;
}

bool riscv_clint_write(paddr_t addr, int len, word_t data) {
  if (!in_clint(addr)) return false;
  Assert(len == 4, "CLINT only supports 32-bit accesses: addr=" FMT_PADDR " len=%d",
      addr, len);
  difftest_skip_ref();

  uint32_t offset = addr - CLINT_BASE;
  bool upper = offset & 4;
  switch (offset & ~4u) {
    case CLINT_MTIMECMP_OFFSET:
      cpu.mtimecmp = replace_half(cpu.mtimecmp, data, upper);
      break;
    case CLINT_MTIME_OFFSET:
      cpu.mtime = replace_half(cpu.mtime, data, upper);
      break;
    default:
      panic("unsupported CLINT write: addr=" FMT_PADDR " len=%d data=" FMT_WORD,
          addr, len, data);
  }
  return true;
}
