#include <contract.h>

static void write_pattern(uintptr_t base, size_t n, uint8_t seed) {
  volatile uint8_t *p = (volatile uint8_t *)base;
  for (size_t i = 0; i < n; i++) {
    p[i] = (uint8_t)(seed + i * 13u);
  }
}

static void check_pattern(uintptr_t base, size_t n, uint8_t seed, const char *stage) {
  volatile uint8_t *p = (volatile uint8_t *)base;
  for (size_t i = 0; i < n; i++) {
    CONTRACT_CHECK(p[i] == (uint8_t)(seed + i * 13u), stage);
  }
}

int main(const char *args) {
  (void)args;
  contract_begin();

  uintptr_t start = (uintptr_t)heap.start;
  uintptr_t end = (uintptr_t)heap.end;
  CONTRACT_CHECK(start != 0 && end > start, "heap-range");
  CONTRACT_CHECK((start & 0x3u) == 0 && (end & 0x3u) == 0, "heap-align");
  CONTRACT_CHECK(end - start >= 4096, "heap-size");

  uintptr_t head = start;
  uintptr_t mid = (start + (end - start) / 2u) & ~(uintptr_t)0x3u;
  uintptr_t tail = (end - 512u) & ~(uintptr_t)0x3u;

  CONTRACT_CHECK(head + 256 <= mid && mid + 256 <= tail && tail + 256 <= end, "heap-windows");
  write_pattern(head, 256, 0x10);
  write_pattern(mid, 256, 0x40);
  write_pattern(tail, 256, 0x80);
  check_pattern(head, 256, 0x10, "heap-head");
  check_pattern(mid, 256, 0x40, "heap-mid");
  check_pattern(tail, 256, 0x80, "heap-tail");

  contract_pass();
}
