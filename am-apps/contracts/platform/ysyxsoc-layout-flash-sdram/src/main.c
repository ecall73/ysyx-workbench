#include <contract.h>

extern char _data_start, _data_end, _data_load_start;
extern char _bss_start, _bss_end;
extern char _heap_start, _heap_end;
extern char _ssbl_vma_start, _ssbl_vma_end, _ssbl_lma_start;

static uint32_t data_probe = 0x10203040u;
static uint32_t bss_probe;

static void check_range(uintptr_t x, uintptr_t lo, uintptr_t hi, const char *stage) {
  CONTRACT_CHECK(x >= lo && x < hi, stage);
}

int main(const char *args) {
  (void)args;
  contract_begin();

  const uintptr_t sdram_lo = 0xa0000000u;
  const uintptr_t sdram_hi = 0xa2000000u;
  const uintptr_t flash_lo = 0x30000000u;
  const uintptr_t flash_hi = 0x31000000u;
  const uintptr_t sram_lo = 0x0f000000u;
  const uintptr_t sram_hi = 0x0f002000u;

  check_range((uintptr_t)&_ssbl_vma_start, sram_lo, sram_hi, "ssbl-start");
  check_range((uintptr_t)&_ssbl_vma_end - 1u, sram_lo, sram_hi, "ssbl-end");
  check_range((uintptr_t)&_ssbl_lma_start, flash_lo, flash_hi, "ssbl-lma");
  check_range((uintptr_t)&_data_start, sdram_lo, sdram_hi, "data-start");
  check_range((uintptr_t)&_data_end - 1u, sdram_lo, sdram_hi, "data-end");
  check_range((uintptr_t)&_data_load_start, flash_lo, flash_hi, "data-lma");
  check_range((uintptr_t)&_bss_start, sdram_lo, sdram_hi, "bss-start");
  check_range((uintptr_t)&_bss_end - 1u, sdram_lo, sdram_hi, "bss-end");
  check_range((uintptr_t)&_heap_start, sdram_lo, sdram_hi, "heap-start");
  check_range((uintptr_t)&_heap_end - 1u, sdram_lo, sdram_hi, "heap-end");

  CONTRACT_CHECK(data_probe == 0x10203040u, "data-probe");
  CONTRACT_CHECK(bss_probe == 0, "bss-probe");
  bss_probe = 0x50607080u;
  CONTRACT_CHECK(bss_probe == 0x50607080u, "bss-write");
  contract_pass();
}
