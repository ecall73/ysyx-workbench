#include <isa.h>
#include <cpu/difftest.h>
#include "../local-include/csr.h"
#include "../local-include/timer.h"

#define CLINT_BASE            0x02000000u
#define CLINT_SIZE            0x10000u
#define CLINT_MSIP_OFFSET     0x0000u
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

bool riscv_clint_access_valid(paddr_t addr, int len) {
  if (!in_clint(addr) || len != 4) return false;
  uint32_t offset = addr - CLINT_BASE;
  return offset == CLINT_MSIP_OFFSET ||
      (offset & ~4u) == CLINT_MTIMECMP_OFFSET ||
      (offset & ~4u) == CLINT_MTIME_OFFSET;
}

bool riscv_clint_read(paddr_t addr, int len, word_t *data) {
  if (!riscv_clint_access_valid(addr, len)) return false;
  uint32_t offset = addr - CLINT_BASE;
  bool upper = offset & 4;
  switch (offset & ~4u) {
    case CLINT_MSIP_OFFSET:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_PENDING_OWNED);
      *data = cpu.msip;
      break;
    case CLINT_MTIMECMP_OFFSET:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_TIMER_OWNED);
      *data = upper ? upper_half(cpu.mtimecmp) : lower_half(cpu.mtimecmp);
      break;
    case CLINT_MTIME_OFFSET:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_TIMER_OWNED);
      *data = upper ? upper_half(cpu.mtime) : lower_half(cpu.mtime);
      break;
    default: return false;
  }
  return true;
}

bool riscv_clint_write(paddr_t addr, int len, word_t data) {
  if (!riscv_clint_access_valid(addr, len)) return false;
  uint32_t offset = addr - CLINT_BASE;
  bool upper = offset & 4;
  switch (offset & ~4u) {
    case CLINT_MSIP_OFFSET:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_PENDING_OWNED);
      cpu.msip = data & 1;
      break;
    case CLINT_MTIMECMP_OFFSET:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_TIMER_OWNED);
      cpu.mtimecmp = replace_half(cpu.mtimecmp, data, upper);
      break;
    case CLINT_MTIME_OFFSET:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_TIMER_OWNED);
      cpu.mtime = replace_half(cpu.mtime, data, upper);
      break;
    default: return false;
  }
  return true;
}
