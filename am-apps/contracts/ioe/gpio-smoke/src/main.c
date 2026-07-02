#include <contract.h>
#include <klib-macros.h>

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(ioe_init(), "ioe-init");
  AM_GPIO_CONFIG_T cfg = io_read(AM_GPIO_CONFIG);
  CONTRACT_CHECK(cfg.present, "gpio-present");

  io_write(AM_GPIO_LED, 0xa55au);
  io_write(AM_GPIO_SEG, 0x20260702u);
  AM_GPIO_SW_T sw = io_read(AM_GPIO_SW);
  (void)sw;

  contract_pass();
}
