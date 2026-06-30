#include <memory/paddr.h>
#include <isa.h>
#include <platform/platform.h>

void init_mem() {
  platform_log_memory();
}

word_t paddr_read(paddr_t addr, int len) {
  word_t data = 0;
  if (likely(platform_read(addr, len, &data))) {
    return data;
  }
  platform_out_of_bound(addr);
  return 0;
}

void paddr_write(paddr_t addr, int len, word_t data) {
  if (likely(platform_write(addr, len, data))) {
    return;
  }
  platform_out_of_bound(addr);
}
