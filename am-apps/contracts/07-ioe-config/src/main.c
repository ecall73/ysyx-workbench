#define CONTRACT_ID "07-ioe-config"
#include <contract.h>
#include <klib-macros.h>

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(ioe_init(), "ioe-init");

  AM_TIMER_CONFIG_T timer = io_read(AM_TIMER_CONFIG);
  CONTRACT_CHECK(timer.present, "timer-config");

  AM_INPUT_CONFIG_T input = io_read(AM_INPUT_CONFIG);
  CONTRACT_CHECK(input.present, "input-config");

  AM_UART_CONFIG_T uart = io_read(AM_UART_CONFIG);
#if defined(__PLATFORM_YSYXSOC)
  CONTRACT_CHECK(uart.present, "uart-config");
  AM_GPU_CONFIG_T gpu = io_read(AM_GPU_CONFIG);
  CONTRACT_CHECK(gpu.present, "gpu-config");
  AM_GPIO_CONFIG_T gpio = io_read(AM_GPIO_CONFIG);
  CONTRACT_CHECK(gpio.present, "gpio-config");
#elif defined(__PLATFORM_NEMU)
  CONTRACT_CHECK(!uart.present, "uart-config");
  AM_GPU_CONFIG_T gpu = io_read(AM_GPU_CONFIG);
  CONTRACT_CHECK(gpu.present, "gpu-config");
#else
  CONTRACT_CHECK(!uart.present, "uart-config");
#endif

  contract_pass();
}
