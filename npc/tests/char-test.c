#define UART_BASE 0x10000000u
#define UART_TX   0x0u

void _start(void) {
  *(volatile char *)(UART_BASE + UART_TX) = 'A';
  *(volatile char *)(UART_BASE + UART_TX) = '\n';

  while (1) {
    asm volatile("ebreak");
  }
}
