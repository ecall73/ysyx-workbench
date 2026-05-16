#include <am.h>
#include <stdint.h>

#define FLASH_BASE 0x30000000u

static inline uint32_t flash_pattern_word(uint32_t word_index) {
  return 0x31415926u ^ (word_index * 0x9e3779b9u);
}

int main(void) {
  volatile uint32_t *flash32 = (volatile uint32_t *)FLASH_BASE;
  volatile uint16_t *flash16 = (volatile uint16_t *)FLASH_BASE;
  volatile uint8_t *flash8 = (volatile uint8_t *)FLASH_BASE;

  for (uint32_t i = 0; i < 64; i += 4) {
    uint32_t idx = i >> 2;
    uint32_t exp = flash_pattern_word(idx);
    uint32_t got = flash32[idx];
    if (got != exp) {
      halt(1);
    }
  }

  for (uint32_t i = 0; i < 64; i += 2) {
    uint32_t w = flash_pattern_word(i >> 2);
    uint16_t exp = (uint16_t)((i & 0x2u) ? (w >> 16) : (w & 0xffffu));
    uint16_t got = flash16[i >> 1];
    if (got != exp) {
      halt(1);
    }
  }

  for (uint32_t i = 0; i < 64; i++) {
    uint32_t w = flash_pattern_word(i >> 2);
    uint8_t exp = (uint8_t)(w >> ((i & 0x3u) * 8));
    uint8_t got = flash8[i];
    if (got != exp) {
      halt(1);
    }
  }

  return 0;
}
