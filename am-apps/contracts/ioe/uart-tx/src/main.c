#include <contract.h>
#include <klib-macros.h>

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(ioe_init(), "ioe-init");
  AM_UART_CONFIG_T cfg = io_read(AM_UART_CONFIG);
  CONTRACT_CHECK(cfg.present, "uart-present");

  const char *token = "UART_TX_TOKEN\n";
  for (const char *p = token; *p; p++) {
    io_write(AM_UART_TX, *p);
  }

  contract_pass();
}
