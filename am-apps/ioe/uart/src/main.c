#include <ioe_diag.h>

int main(const char *args) {
  (void)args;
  ioe_init();

  AM_UART_CONFIG_T cfg = io_read(AM_UART_CONFIG);
  printf("[uart][CONFIG] uart.present=%d\n", cfg.present);
  if (!cfg.present) {
    printf("[uart][SKIP] UART AM device is not present on this platform\n");
    return 0;
  }

  printf("[uart][TX] token=UART_TX_TOKEN\n");
  const char *msg = "UART_TX_TOKEN 0123456789 abcdef\n";
  for (const char *p = msg; *p; p++) {
    io_write(AM_UART_TX, *p);
  }

  printf("[uart][RX] type characters; q exits\n");
  uint32_t idle = 0;
  while (1) {
    bool got = false;
    for (int i = 0; i < 16; i++) {
      AM_UART_RX_T rx = io_read(AM_UART_RX);
      if (rx.data == (char)-1) break;
      got = true;
      unsigned ch = (unsigned char)rx.data;
      printf("[uart][RX] char='%c' hex=0x%02x dec=%u\n",
          (ch >= 32 && ch < 127) ? (char)ch : '.', ch, ch);
      io_write(AM_UART_TX, rx.data);
      if (rx.data == 'q' || rx.data == 'Q') {
        printf("[uart][DONE]\n");
        return 0;
      }
    }
    if (!got && (idle++ & 0x7fffu) == 0) {
      printf("[uart][HEARTBEAT] waiting rx idle=%u\n", idle);
    }
    diag_delay(1000u);
  }
}
