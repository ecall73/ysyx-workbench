#include <ioe_diag.h>

static void drain_uart(bool has_uart, bool *quit) {
  if (!has_uart) return;

  for (int i = 0; i < 16; i++) {
    AM_UART_RX_T rx = io_read(AM_UART_RX);
    if (rx.data == (char)-1) break;

    unsigned ch = (unsigned char)rx.data;
    printf("[keyboard-visible][UART_RX] char='%c' hex=0x%02x dec=%u\n",
        (ch >= 32 && ch < 127) ? (char)ch : '.', ch, ch);
    if (rx.data == 'q' || rx.data == 'Q') *quit = true;
  }
}

static void drain_keyboard(bool has_kbd, bool *quit) {
  if (!has_kbd) return;

  for (int i = 0; i < 16; i++) {
    AM_INPUT_KEYBRD_T ev = io_read(AM_INPUT_KEYBRD);
    if (ev.keycode == AM_KEY_NONE) break;

    printf("[keyboard-visible][KBD] %-4s key=%-12s code=%d\n",
        ev.keydown ? "DOWN" : "UP", diag_key_name(ev.keycode), ev.keycode);
    if (ev.keydown && ev.keycode == AM_KEY_ESCAPE) *quit = true;
  }
}

int main(const char *args) {
  (void)args;
  ioe_init();

  AM_UART_CONFIG_T ucfg = io_read(AM_UART_CONFIG);
  AM_INPUT_CONFIG_T icfg = io_read(AM_INPUT_CONFIG);
  printf("[keyboard-visible][CONFIG] uart.present=%d input.present=%d\n",
      ucfg.present, icfg.present);
  printf("[keyboard-visible][EXPECT] press WASD/arrows/Enter/Esc; UART input is shown separately; Esc or UART q exits\n");

  bool quit = false;
  uint32_t idle = 0;
  while (!quit) {
    drain_uart(ucfg.present, &quit);
    drain_keyboard(icfg.present, &quit);

    if ((idle++ & 0x3fffu) == 0) {
      printf("[keyboard-visible][HEARTBEAT] alive uart=%d input=%d idle=%u\n",
          ucfg.present, icfg.present, idle);
    }
    diag_delay(1000u);
  }

  printf("[keyboard-visible][DONE]\n");
  return 0;
}
