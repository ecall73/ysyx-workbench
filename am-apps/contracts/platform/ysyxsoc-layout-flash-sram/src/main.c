#include <contract.h>

extern char _data_start, _data_end, _data_load_start;
extern char _bss_start, _bss_end;
extern char _heap_start, _heap_end;

static uint32_t data_probe = 0x2468ace0u;
static uint32_t bss_probe;

static void check_range(uintptr_t x, uintptr_t lo, uintptr_t hi, const char *stage) {
  CONTRACT_CHECK(x >= lo && x < hi, stage);
}

int main(const char *args) {
  (void)args;
  contract_begin();

  const uintptr_t sram_lo = 0x0f000000u;
  const uintptr_t sram_hi = 0x0f002000u;
  const uintptr_t flash_lo = 0x30000000u;
  const uintptr_t flash_hi = 0x31000000u;

  check_range((uintptr_t)&_data_start, sram_lo, sram_hi, "data-start");
  check_range((uintptr_t)&_data_end - 1u, sram_lo, sram_hi, "data-end");
  check_range((uintptr_t)&_data_load_start, flash_lo, flash_hi, "data-lma");
  check_range((uintptr_t)&_bss_start, sram_lo, sram_hi, "bss-start");
  check_range((uintptr_t)&_bss_end - 1u, sram_lo, sram_hi, "bss-end");
  check_range((uintptr_t)&_heap_start, sram_lo, sram_hi, "heap-start");
  check_range((uintptr_t)&_heap_end - 1u, sram_lo, sram_hi, "heap-end");

  CONTRACT_CHECK(data_probe == 0x2468ace0u, "data-probe");
  CONTRACT_CHECK(bss_probe == 0, "bss-probe");
  bss_probe = 0x13579bdfu;
  CONTRACT_CHECK(bss_probe == 0x13579bdfu, "bss-write");
  contract_pass();
}
