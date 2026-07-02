#define CONTRACT_ID "02-heap-window"
#include <contract.h>

static void check_window(uintptr_t base, uint32_t seed) {
  volatile uint8_t *p = (volatile uint8_t *)base;
  for (int i = 0; i < 64; i++) {
    p[i] = (uint8_t)(seed + (uint32_t)i * 17u);
  }
  for (int i = 0; i < 64; i++) {
    CONTRACT_CHECK(p[i] == (uint8_t)(seed + (uint32_t)i * 17u), "heap-window");
  }
}

int main(const char *args) {
  (void)args;
  contract_begin();

  uintptr_t start = (uintptr_t)heap.start;
  uintptr_t end = (uintptr_t)heap.end;
  CONTRACT_CHECK(start != 0 && end > start, "heap-range");
  CONTRACT_CHECK(end - start >= 1024, "heap-size");

  uintptr_t mid = start + ((end - start) / 2u);
  mid &= ~(uintptr_t)0x3u;
  uintptr_t tail = (end - 128u) & ~(uintptr_t)0x3u;

  check_window(start, 0x11);
  check_window(mid, 0x33);
  check_window(tail, 0x55);
  contract_pass();
}
