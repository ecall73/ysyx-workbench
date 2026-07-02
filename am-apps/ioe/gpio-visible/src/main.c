#include <ioe_diag.h>

#ifndef GPIO_PASSCODE
#define GPIO_PASSCODE 0xec73u
#endif

#define LED_PHASE_DELAY 200000u

static uint32_t pack_hex_nibbles(uint32_t x) {
  uint32_t v = 0;
  for (int i = 0; i < 8; i++) {
    uint32_t nib = (x >> (i * 4)) & 0xfu;
    v |= nib << (i * 4);
  }
  return v;
}

static uint32_t read_marchid(void) {
  uint32_t marchid = 0;
  asm volatile("csrr %0, marchid" : "=r"(marchid));
  return marchid;
}

int main(const char *args) {
  (void)args;
  ioe_init();

  AM_GPIO_CONFIG_T cfg = io_read(AM_GPIO_CONFIG);
  printf("[gpio-visible][CONFIG] gpio.present=%d passcode=0x%04x\n",
      cfg.present, (unsigned)GPIO_PASSCODE);
  if (!cfg.present) {
    printf("[gpio-visible][SKIP] GPIO AM device is not present on this platform\n");
    return 0;
  }

  printf("[gpio-visible][PHASE led] LED rotates; SW value is printed periodically\n");
  uint16_t led = 0x0001u;
  for (uint32_t step = 0; step < 64; step++) {
    io_write(AM_GPIO_LED, led);
    AM_GPIO_SW_T sw = io_read(AM_GPIO_SW);
    if ((step & 0x7u) == 0) {
      printf("[gpio-visible][LED] step=%u led=0x%04x sw=0x%04x\n",
          step, led, sw.value);
    }
    led = (uint16_t)((led << 1) | (led >> 15));
    diag_delay(LED_PHASE_DELAY);
  }

  printf("[gpio-visible][PHASE seg-fixed] SEG should show 0x20260702, LED=0xa55a\n");
  io_write(AM_GPIO_LED, 0xa55au);
  io_write(AM_GPIO_SEG, 0x20260702u);
  for (volatile uint32_t d = 0; d < 2000000u; d++) {
  }

  uint32_t marchid = read_marchid();
  uint32_t seg_marchid = pack_hex_nibbles(marchid);
  printf("[gpio-visible][PHASE seg-marchid] marchid=%u raw=0x%08x seg=0x%08x\n",
      marchid, marchid, seg_marchid);
  io_write(AM_GPIO_SEG, seg_marchid);

  printf("[gpio-visible][PHASE sw-exit] set SW=0x%04x to exit; LED rotates from passcode\n",
      (unsigned)GPIO_PASSCODE);
  led = GPIO_PASSCODE;
  uint32_t polls = 0;
  while (1) {
    io_write(AM_GPIO_LED, led);
    AM_GPIO_SW_T sw = io_read(AM_GPIO_SW);
    if (sw.value == (uint16_t)GPIO_PASSCODE) break;
    if ((polls++ & 0x3fu) == 0) {
      printf("[gpio-visible][SW] waiting sw=0x%04x expected=0x%04x led=0x%04x\n",
          sw.value, (unsigned)GPIO_PASSCODE, led);
    }
    led = (uint16_t)((led << 1) | (led >> 15));
    diag_delay(LED_PHASE_DELAY);
  }

  io_write(AM_GPIO_LED, 0xffffu);
  printf("[gpio-visible][DONE] passcode matched; LED=0xffff\n");
  return 0;
}
