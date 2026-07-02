#include <contract.h>
#include <klib-macros.h>

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(ioe_init(), "ioe-init");

  AM_UART_CONFIG_T uart = io_read(AM_UART_CONFIG);
#if defined(__PLATFORM_YSYXSOC)
  CONTRACT_CHECK(uart.present, "ysyxsoc-uart-present");
#else
  CONTRACT_CHECK(!uart.present, "uart-absent");
  AM_UART_RX_T rx = io_read(AM_UART_RX);
  CONTRACT_CHECK(rx.data == (char)0xff, "uart-rx-idle");
#endif

  contract_pass();
}
