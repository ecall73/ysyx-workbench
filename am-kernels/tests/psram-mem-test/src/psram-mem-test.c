#include <am.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

#define PSRAM_BASE 0x80000000u
#define PSRAM_SIZE 0x00400000u
#define PROGRESS_STEP 0x00080000u

static inline uintptr_t align_up(uintptr_t x, uintptr_t a) {
  return (x + (a - 1)) & ~(a - 1);
}

static inline uintptr_t align_down(uintptr_t x, uintptr_t a) {
  return x & ~(a - 1);
}

static inline uintptr_t min_u(uintptr_t a, uintptr_t b) {
  return a < b ? a : b;
}

static void report_progress(const char *phase, uintptr_t begin, uintptr_t addr, uintptr_t end) {
  (void)end;
  printf("[%s] progress: 0x%08x / 0x%08x\n", phase, (uint32_t)(addr - begin), PSRAM_SIZE);
}

int main(void) {
  uintptr_t start = (uintptr_t)PSRAM_BASE;
  uintptr_t end = (uintptr_t)(PSRAM_BASE + PSRAM_SIZE);
  printf("[psram-mem-test] full range: [0x%08x, 0x%08x)\n", (uint32_t)start, (uint32_t)end);

  {
    uintptr_t lo = align_up(start, 1);
    uintptr_t hi = align_down(end, 1);
    for (uintptr_t blk = lo; blk < hi; blk += PROGRESS_STEP) {
      uintptr_t blk_end = min_u(blk + PROGRESS_STEP, hi);
      report_progress("byte-write", lo, blk, hi);
      for (uintptr_t addr = blk; addr < blk_end; addr += 1) {
        *(volatile uint8_t *)addr = (uint8_t)(addr & 0xffu);
      }
    }
    for (uintptr_t blk = lo; blk < hi; blk += PROGRESS_STEP) {
      uintptr_t blk_end = min_u(blk + PROGRESS_STEP, hi);
      report_progress("byte-read", lo, blk, hi);
      for (uintptr_t addr = blk; addr < blk_end; addr += 1) {
        uint8_t expected = (uint8_t)(addr & 0xffu);
        uint8_t got = *(volatile uint8_t *)addr;
        if (got != expected) {
          printf("BYTE mismatch @0x%08x exp=0x%02x got=0x%02x\n", (uint32_t)addr, expected, got);
          halt(1);
        }
      }
    }
    printf("[psram-mem-test] byte pass\n");
  }

  {
    uintptr_t lo = align_up(start, 2);
    uintptr_t hi = align_down(end, 2);
    for (uintptr_t blk = lo; blk < hi; blk += PROGRESS_STEP) {
      uintptr_t blk_end = min_u(blk + PROGRESS_STEP, hi);
      report_progress("half-write", lo, blk, hi);
      for (uintptr_t addr = blk; addr < blk_end; addr += 2) {
        *(volatile uint16_t *)addr = (uint16_t)(addr & 0xffffu);
      }
    }
    for (uintptr_t blk = lo; blk < hi; blk += PROGRESS_STEP) {
      uintptr_t blk_end = min_u(blk + PROGRESS_STEP, hi);
      report_progress("half-read", lo, blk, hi);
      for (uintptr_t addr = blk; addr < blk_end; addr += 2) {
        uint16_t expected = (uint16_t)(addr & 0xffffu);
        uint16_t got = *(volatile uint16_t *)addr;
        if (got != expected) {
          printf("HALF mismatch @0x%08x exp=0x%04x got=0x%04x\n", (uint32_t)addr, expected, got);
          halt(1);
        }
      }
    }
    printf("[psram-mem-test] half pass\n");
  }

  {
    uintptr_t lo = align_up(start, 4);
    uintptr_t hi = align_down(end, 4);
    for (uintptr_t blk = lo; blk < hi; blk += PROGRESS_STEP) {
      uintptr_t blk_end = min_u(blk + PROGRESS_STEP, hi);
      report_progress("word-write", lo, blk, hi);
      for (uintptr_t addr = blk; addr < blk_end; addr += 4) {
        *(volatile uint32_t *)addr = (uint32_t)addr;
      }
    }
    for (uintptr_t blk = lo; blk < hi; blk += PROGRESS_STEP) {
      uintptr_t blk_end = min_u(blk + PROGRESS_STEP, hi);
      report_progress("word-read", lo, blk, hi);
      for (uintptr_t addr = blk; addr < blk_end; addr += 4) {
        uint32_t expected = (uint32_t)addr;
        uint32_t got = *(volatile uint32_t *)addr;
        if (got != expected) {
          printf("WORD mismatch @0x%08x exp=0x%08x got=0x%08x\n", (uint32_t)addr, expected, got);
          halt(1);
        }
      }
    }
    printf("[psram-mem-test] word pass\n");
  }

  {
    uintptr_t lo = align_up(start, 8);
    uintptr_t hi = align_down(end, 8);
    for (uintptr_t blk = lo; blk < hi; blk += PROGRESS_STEP) {
      uintptr_t blk_end = min_u(blk + PROGRESS_STEP, hi);
      report_progress("dword-write", lo, blk, hi);
      for (uintptr_t addr = blk; addr < blk_end; addr += 8) {
        *(volatile uint64_t *)addr = (uint64_t)addr;
      }
    }
    for (uintptr_t blk = lo; blk < hi; blk += PROGRESS_STEP) {
      uintptr_t blk_end = min_u(blk + PROGRESS_STEP, hi);
      report_progress("dword-read", lo, blk, hi);
      for (uintptr_t addr = blk; addr < blk_end; addr += 8) {
        uint64_t expected = (uint64_t)addr;
        uint64_t got = *(volatile uint64_t *)addr;
        if (got != expected) {
          printf("DWORD mismatch @0x%08x exp=0x%08x%08x got=0x%08x%08x\n",
                 (uint32_t)addr,
                 (uint32_t)(expected >> 32), (uint32_t)expected,
                 (uint32_t)(got >> 32), (uint32_t)got);
          halt(1);
        }
      }
    }
    printf("[psram-mem-test] dword pass\n");
  }

  printf("[psram-mem-test] full 4MB pass\n");
  return 0;
}
