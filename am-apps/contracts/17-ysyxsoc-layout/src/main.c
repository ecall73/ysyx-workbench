#define CONTRACT_ID "17-ysyxsoc-layout"
#include <contract.h>

#if defined(__PLATFORM_YSYXSOC)
extern char _ssbl_vma_start, _ssbl_vma_end, _ssbl_lma_start;
extern char _data_start, _data_end, _data_load_start;
extern char _bss_start, _bss_end;
extern char _heap_start, _heap_end;

static inline uintptr_t read_sp(void) {
  uintptr_t sp;
  asm volatile("mv %0, sp" : "=r"(sp));
  return sp;
}

static void check_range(uintptr_t x, uintptr_t lo, uintptr_t hi, const char *stage) {
  CONTRACT_CHECK(x >= lo && x < hi, stage);
}

static void check_window(uintptr_t base, const char *stage) {
  volatile uint32_t *p = (volatile uint32_t *)base;
  for (int i = 0; i < 16; i++) p[i] = 0x5a5a0000u + (uint32_t)i;
  for (int i = 0; i < 16; i++) CONTRACT_CHECK(p[i] == 0x5a5a0000u + (uint32_t)i, stage);
}
#endif

int main(const char *args) {
  (void)args;
  contract_begin();

#if !defined(__PLATFORM_YSYXSOC)
  contract_skip("not-ysyxsoc");
#else
  const uintptr_t sram_lo = 0x0f000000u;
  const uintptr_t sram_hi = 0x0f002000u;
  const uintptr_t flash_lo = 0x30000000u;
  const uintptr_t flash_hi = 0x31000000u;
  const uintptr_t sdram_lo = 0xa0000000u;
  const uintptr_t sdram_hi = 0xa2000000u;

  uintptr_t ssbl_start = (uintptr_t)&_ssbl_vma_start;
  uintptr_t ssbl_end = (uintptr_t)&_ssbl_vma_end;
  uintptr_t ssbl_lma = (uintptr_t)&_ssbl_lma_start;
  uintptr_t data_start = (uintptr_t)&_data_start;
  uintptr_t data_end = (uintptr_t)&_data_end;
  uintptr_t data_lma = (uintptr_t)&_data_load_start;
  uintptr_t bss_start = (uintptr_t)&_bss_start;
  uintptr_t bss_end = (uintptr_t)&_bss_end;
  uintptr_t heap_start = (uintptr_t)&_heap_start;
  uintptr_t heap_end = (uintptr_t)&_heap_end;
  uintptr_t sp = read_sp();

  check_range(ssbl_start, sram_lo, sram_hi, "ssbl-start");
  check_range(ssbl_end - 1u, sram_lo, sram_hi, "ssbl-end");
  check_range(ssbl_lma, flash_lo, flash_hi, "ssbl-lma");
  check_range(data_start, sdram_lo, sdram_hi, "data-start");
  check_range(data_end - 1u, sdram_lo, sdram_hi, "data-end");
  check_range(data_lma, flash_lo, flash_hi, "data-lma");
  check_range(bss_start, sdram_lo, sdram_hi, "bss-start");
  check_range(bss_end - 1u, sdram_lo, sdram_hi, "bss-end");
  check_range(heap_start, sdram_lo, sdram_hi, "heap-start");
  check_range(heap_end - 1u, sdram_lo, sdram_hi, "heap-end");
  check_range(sp, sram_lo, sram_hi, "stack-pointer");

  CONTRACT_CHECK(ssbl_start < ssbl_end, "ssbl-order");
  CONTRACT_CHECK(data_start < data_end, "data-order");
  CONTRACT_CHECK(data_end <= bss_start && bss_start <= bss_end, "data-bss-order");
  CONTRACT_CHECK(bss_end <= heap_start && heap_start < heap_end, "heap-order");

  check_window(heap_start, "heap-head-write");
  check_window((heap_end - 128u) & ~(uintptr_t)0x3u, "heap-tail-write");
  contract_pass();
#endif
}
