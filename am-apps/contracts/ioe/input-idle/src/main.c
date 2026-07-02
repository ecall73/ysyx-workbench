#include <contract.h>
#include <klib-macros.h>

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(ioe_init(), "ioe-init");
  AM_INPUT_CONFIG_T cfg = io_read(AM_INPUT_CONFIG);
  CONTRACT_CHECK(cfg.present, "input-config");

  for (int i = 0; i < 128; i++) {
    AM_INPUT_KEYBRD_T ev = io_read(AM_INPUT_KEYBRD);
    CONTRACT_CHECK(ev.keycode >= AM_KEY_NONE && ev.keycode <= AM_KEY_PAGEDOWN, "key-range");
  }

  contract_pass();
}
