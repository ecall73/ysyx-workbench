#include <am.h>
#include <amdev.h>
#include <klib.h>
#include <klib-macros.h>
#include <stdint.h>

#ifndef GPIO_PASSCODE
#define GPIO_PASSCODE 0xec73u
#endif

#define LED_STEPS 128u
#define PHASECYCLES 400000u

static uint32_t pack_hex_nibbles(uint32_t x) {
  uint32_t v = 0;
  for (int i = 0; i < 8; i++) {
    uint32_t nib = (x >> (i * 4)) & 0xfu;
    v |= (nib << (i * 4));
  }
  return v;
}

int main(void) {
  AM_GPIO_CONFIG_T cfg = io_read(AM_GPIO_CONFIG);
  if (!cfg.present) {
    printf("[gpio-ioe-test] GPIO not present\n");
    return 1;
  }

  printf("[gpio-ioe-test] passcode=0x%04x\n", (unsigned)GPIO_PASSCODE);
  printf("[gpio-ioe-test] phase A: running LED + polling SW\n");

  uint16_t led = GPIO_PASSCODE;
  uint32_t steps = 0;
  while (1) {
    io_write(AM_GPIO_LED, led);

    AM_GPIO_SW_T sw = io_read(AM_GPIO_SW);
    if (sw.value == (uint16_t)GPIO_PASSCODE) {
      break;
    }

    for (volatile uint32_t d = 0; d < PHASECYCLES; d++) {
    }

    led = (uint16_t)((led << 1) | (led >> 15));
    if ((++steps % LED_STEPS) == 0) {
      printf("[gpio-ioe-test] waiting passcode, sw=0x%04x\n", sw.value);
    }
  }

  printf("[gpio-ioe-test] phase B: passcode matched\n");

  uint32_t marchid = 0;
  asm volatile("csrr %0, marchid" : "=r"(marchid));
  uint32_t seg_val = pack_hex_nibbles(marchid);

  printf("[gpio-ioe-test] phase C: marchid=%u (0x%08x)\n", marchid, marchid);
  io_write(AM_GPIO_SEG, seg_val);

  // Keep LED on and stay observable for a while.
  io_write(AM_GPIO_LED, 0xffffu);
  printf("[gpio-ioe-test] phase D: display latched, exiting\n");

  for (volatile uint32_t d = 0; d < 2000000u; d++) {
  }

  return 0;
}
