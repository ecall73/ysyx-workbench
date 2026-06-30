#include <stdint.h>

#include "memory/paddr.h"
#include "platform/platform.h"

void platform_init() {}

void platform_cleanup() {}

void platform_update() {}

void platform_set_external_idle(SimTop *top) {
  (void)top;
}

const char *platform_device_name(uint32_t addr) {
  if (addr == SERIAL_PORT) return "uart";
  if (addr == RTC_ADDR || addr == RTC_ADDR + 4) return "rtc";
  return NULL;
}

uint32_t platform_reset_pc() {
  return NPC_RESET_PC_NPC;
}

void platform_enable_ref_paddr(void (*enable_ysyxsoc_paddr)(void)) {
  (void)enable_ysyxsoc_paddr;
}
