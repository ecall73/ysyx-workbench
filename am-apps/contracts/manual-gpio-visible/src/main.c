#define CONTRACT_ID "manual-gpio-visible"
#include <contract.h>
#include <klib-macros.h>

int main(const char *args) {
  (void)args;
  contract_begin();

#if !defined(__PLATFORM_YSYXSOC)
  contract_skip("not-ysyxsoc");
#else
  CONTRACT_CHECK(ioe_init(), "ioe-init");
  AM_GPIO_CONFIG_T cfg = io_read(AM_GPIO_CONFIG);
  CONTRACT_CHECK(cfg.present, "gpio-present");

  contract_puts("manual-gpio-visible: LED rotates, SEG shows 0x20260702, set SW=0xec73 to exit\n");
  uint16_t led = 0x0001u;
  while (1) {
    io_write(AM_GPIO_LED, led);
    io_write(AM_GPIO_SEG, 0x20260702u);
    AM_GPIO_SW_T sw = io_read(AM_GPIO_SW);
    if (sw.value == 0xec73u) break;
    led = (uint16_t)((led << 1) | (led >> 15));
    for (volatile uint32_t i = 0; i < 200000u; i++) {
    }
  }
  contract_pass();
#endif
}
