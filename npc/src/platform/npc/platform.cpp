#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#include "common.h"
#include "memory/paddr.h"
#include "platform/platform.h"
#include "utils.h"

static long img_size = 0;

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

long platform_load_image(const char *img_file) {
  FILE *fp = fopen(img_file, "rb");
  if (fp == NULL) return 0;

  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  int ret = fread(pmem_base(), size, 1, fp);
  assert(ret == 1);
  fclose(fp);

  img_size = size;
  printf("The image is %s, size = %ld\n", img_file, size);
  return size;
}

bool platform_read_word(uint32_t addr, uint32_t *data) {
  uint32_t aligned = addr & ~0x3u;
  if (!in_pmem(aligned)) return false;
  *data = pmem_read_word(aligned);
  return true;
}

bool platform_in_comparable_mem(uint32_t addr) {
  return in_pmem(addr);
}

void platform_difftest_memcpy(void (*ref_memcpy)(uint32_t, void *, size_t, bool), bool direction) {
  if (img_size > 0) {
    ref_memcpy(NPC_PMEM_BASE, pmem_base(), (size_t)img_size, direction);
  } else {
    Log("warning: no pmem image loaded before DiffTest init");
  }
}

void platform_enable_ref_paddr(void (*enable_ysyxsoc_paddr)(void)) {
  (void)enable_ysyxsoc_paddr;
}
