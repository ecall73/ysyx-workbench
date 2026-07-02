#define CONTRACT_ID "14-gpu-config"
#include <contract.h>
#include <klib-macros.h>

int main(const char *args) {
  (void)args;
  contract_begin();

#if defined(__PLATFORM_NPC)
  contract_skip("no-gpu");
#endif

  CONTRACT_CHECK(ioe_init(), "ioe-init");
  AM_GPU_CONFIG_T cfg = io_read(AM_GPU_CONFIG);
  CONTRACT_CHECK(cfg.present, "gpu-present");
  CONTRACT_CHECK(cfg.width > 0 && cfg.height > 0, "gpu-size");

#if defined(__PLATFORM_YSYXSOC)
  CONTRACT_CHECK(cfg.width == 640 && cfg.height == 480, "ysyxsoc-size");
#endif

  contract_pass();
}
