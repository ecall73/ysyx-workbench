#include <am.h>
#include <stdint.h>

#define FLASH_BASE               0x30000000u
#define FLASH_PAYLOAD_OFF        0x1000u
#define FLASH_PAYLOAD_MAGIC      0x43485254u
#define FLASH_PAYLOAD_HDR_SIZE   12u

static inline uint32_t flash_u32(uint32_t off) {
  return *(volatile uint32_t *)(uintptr_t)(FLASH_BASE + off);
}

int main(void) {
  uint32_t magic = flash_u32(FLASH_PAYLOAD_OFF + 0u);
  uint32_t size_bytes = flash_u32(FLASH_PAYLOAD_OFF + 4u);
  uint32_t entry_off = flash_u32(FLASH_PAYLOAD_OFF + 8u);

  if (magic != FLASH_PAYLOAD_MAGIC) {
    halt(1);
  }
  if (size_bytes == 0u) {
    halt(1);
  }
  if (entry_off >= size_bytes) {
    halt(1);
  }

  uintptr_t entry_addr = (uintptr_t)FLASH_BASE +
                         (uintptr_t)FLASH_PAYLOAD_OFF +
                         (uintptr_t)FLASH_PAYLOAD_HDR_SIZE +
                         (uintptr_t)entry_off;

  void (*entry)(void) = (void (*)(void))entry_addr;
  asm volatile("mv a0, zero" ::: "a0");
  entry();

  halt(1);
  return 0;
}
