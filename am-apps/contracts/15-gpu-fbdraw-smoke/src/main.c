#define CONTRACT_ID "15-gpu-fbdraw-smoke"
#include <contract.h>
#include <klib-macros.h>

static uint32_t pixels[16 * 16];

static void fill(uint32_t base) {
  for (int i = 0; i < 16 * 16; i++) {
    uint32_t x = base + (uint32_t)i;
    pixels[i] = ((x * 17u) & 0xffu) << 16
              | ((x * 29u) & 0xffu) << 8
              | ((x * 43u) & 0xffu);
  }
}

int main(const char *args) {
  (void)args;
  contract_begin();

#if defined(__PLATFORM_NPC)
  contract_skip("no-gpu");
#endif

  CONTRACT_CHECK(ioe_init(), "ioe-init");
  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  CONTRACT_CHECK(cfg.present && cfg.width >= 64 && cfg.height >= 64, "gpu-config");

  fill(0x10u);
  io_write(AM_GPU_FBDRAW, 0, 0, pixels, 16, 16, false);
  fill(0x20u);
  io_write(AM_GPU_FBDRAW, cfg.width - 16, 0, pixels, 16, 16, false);
  fill(0x30u);
  io_write(AM_GPU_FBDRAW, 0, cfg.height - 16, pixels, 16, 16, false);
  fill(0x40u);
  io_write(AM_GPU_FBDRAW, cfg.width - 16, cfg.height - 16, pixels, 16, 16, true);

  AM_GPU_STATUS_T st = io_read(AM_GPU_STATUS);
  CONTRACT_CHECK(st.ready, "gpu-status");
  contract_pass();
}
