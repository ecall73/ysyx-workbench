#define CONTRACT_ID "manual-gpu-pattern"
#include <contract.h>
#include <klib-macros.h>

static uint32_t row[640];

static uint32_t rgb(uint8_t r, uint8_t g, uint8_t b) {
  return ((uint32_t)r << 16) | ((uint32_t)g << 8) | b;
}

int main(const char *args) {
  (void)args;
  contract_begin();

#if defined(__PLATFORM_NPC)
  contract_skip("no-gpu");
#else
  CONTRACT_CHECK(ioe_init(), "ioe-init");
  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  CONTRACT_CHECK(cfg.present && cfg.width > 0 && cfg.height > 0 && cfg.width <= 640, "gpu-config");

  for (int y = 0; y < cfg.height; y++) {
    for (int x = 0; x < cfg.width; x++) {
      bool border = x < 8 || y < 8 || x >= cfg.width - 8 || y >= cfg.height - 8;
      bool cross = (x >= cfg.width / 2 - 3 && x <= cfg.width / 2 + 3)
                || (y >= cfg.height / 2 - 3 && y <= cfg.height / 2 + 3);
      bool checker = ((x / 32) ^ (y / 32)) & 1;
      row[x] = border ? rgb(255, 255, 255)
             : cross ? rgb(255, 0, 0)
             : checker ? rgb(0, 160, 255)
             : rgb(20, 20, 20);
    }
    io_write(AM_GPU_FBDRAW, 0, y, row, cfg.width, 1, y == cfg.height - 1);
  }

  contract_puts("manual-gpu-pattern: press ESC to exit\n");
  while (1) {
    AM_INPUT_KEYBRD_T ev = io_read(AM_INPUT_KEYBRD);
    if (ev.keydown && ev.keycode == AM_KEY_ESCAPE) break;
  }
  contract_pass();
#endif
}
