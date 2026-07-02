#define CONTRACT_ID "manual-input-keyboard"
#include <contract.h>
#include <klib-macros.h>

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(ioe_init(), "ioe-init");
  AM_INPUT_CONFIG_T cfg = io_read(AM_INPUT_CONFIG);
  CONTRACT_CHECK(cfg.present, "input-config");

  contract_puts("manual-input-keyboard: press arrows/WASD/Enter/Esc; ESC exits\n");
  while (1) {
    AM_INPUT_KEYBRD_T ev = io_read(AM_INPUT_KEYBRD);
    if (ev.keycode != AM_KEY_NONE) {
      contract_puts("KEY ");
      contract_puts(ev.keydown ? "DOWN " : "UP ");
      contract_putu64((uint64_t)ev.keycode);
      contract_puts("\n");
      if (ev.keydown && ev.keycode == AM_KEY_ESCAPE) break;
    }
  }
  contract_pass();
}
