#include <am.h>
#include <stdint.h>

#ifndef FLASH_BASE
#define FLASH_BASE 0x30000000u
#endif

static inline uint32_t flash_pattern_word(uint32_t word_index) {
  return 0x31415926u ^ (word_index * 0x9e3779b9u);
}

static inline uint8_t expected_u8(uint32_t offset) {
  uint32_t word = flash_pattern_word(offset >> 2);
  return (uint8_t)((word >> ((offset & 0x3u) * 8u)) & 0xffu);
}

static inline uint16_t expected_u16(uint32_t offset) {
  uint32_t word = flash_pattern_word(offset >> 2);
  return (uint16_t)((word >> ((offset & 0x2u) * 8u)) & 0xffffu);
}

static inline uint32_t expected_u32(uint32_t offset) {
  return flash_pattern_word(offset >> 2);
}

int main(void) {
  volatile uint8_t *flash8 = (volatile uint8_t *)(uintptr_t)FLASH_BASE;
  volatile uint16_t *flash16 = (volatile uint16_t *)(uintptr_t)FLASH_BASE;
  volatile uint32_t *flash32 = (volatile uint32_t *)(uintptr_t)FLASH_BASE;

  for (uint32_t off = 0; off < 64; off++) {
    uint8_t got = flash8[off];
    uint8_t exp = expected_u8(off);
    if (got != exp) halt(1);
  }

  for (uint32_t off = 0; off < 64; off += 2) {
    uint16_t got = flash16[off >> 1];
    uint16_t exp = expected_u16(off);
    if (got != exp) halt(1);
  }

  for (uint32_t off = 0; off < 64; off += 4) {
    uint32_t got = flash32[off >> 2];
    uint32_t exp = expected_u32(off);
    if (got != exp) halt(1);
  }

  return 0;
}
