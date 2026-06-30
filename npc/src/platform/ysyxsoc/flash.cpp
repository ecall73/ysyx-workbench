#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include <nvboard.h>

#include "common.h"
#include "memory/paddr.h"
#include "platform/platform.h"
#include "utils.h"

void nvboard_bind_all_pins(SimTop *top);

static uint8_t flash_image[NPC_FLASH_SIZE];
static bool flash_initialized = false;
static bool flash_oob_warned = false;
static bool flash_boot_loaded = false;
static size_t flash_boot_size = 0;

static bool in_flash(uint32_t addr) {
  return addr >= NPC_FLASH_BASE && addr < NPC_FLASH_BASE + NPC_FLASH_SIZE;
}

void platform_init() {
  nvboard_bind_all_pins(g_top);
  nvboard_init();
}

void platform_cleanup() {
  nvboard_quit();
}

void platform_update() {
  nvboard_update();
}

void platform_set_external_idle(SimTop *top) {
  top->externalPins_ps2_clk = 1;
  top->externalPins_ps2_data = 1;
  top->externalPins_uart_rx = 1;
}

long platform_load_image(const char *img_file) {
  memset(flash_image, 0xff, sizeof(flash_image));
  flash_initialized = true;
  flash_oob_warned = false;
  flash_boot_loaded = false;
  flash_boot_size = 0;
  printf("Flash image initialized: erased state(0xFF), size = %u\n", NPC_FLASH_SIZE);

  FILE *fp = fopen(img_file, "rb");
  if (fp == NULL) {
    fprintf(stderr, "flash: failed to open %s\n", img_file);
    return 0;
  }

  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  if (size < 0 || (uint32_t)size > NPC_FLASH_SIZE) {
    fclose(fp);
    fprintf(stderr, "flash: bad image size %ld for %s\n", size, img_file);
    return 0;
  }

  size_t nread = fread(flash_image, 1, (size_t)size, fp);
  fclose(fp);
  if (nread != (size_t)size) {
    fprintf(stderr, "flash: read size mismatch for %s\n", img_file);
    return 0;
  }

  flash_boot_loaded = true;
  flash_boot_size = (size_t)size;
  printf("Flash boot image loaded: %s, size = %ld, base = 0x%08x\n",
         img_file, size, NPC_FLASH_BASE);
  return size;
}

bool platform_read_word(uint32_t addr, uint32_t *data) {
  uint32_t aligned = addr & ~0x3u;
  if (!in_flash(aligned) || aligned > NPC_FLASH_BASE + NPC_FLASH_SIZE - 4) return false;
  uint32_t off = aligned - NPC_FLASH_BASE;
  *data = ((uint32_t)flash_image[off + 0]) |
          ((uint32_t)flash_image[off + 1] << 8) |
          ((uint32_t)flash_image[off + 2] << 16) |
          ((uint32_t)flash_image[off + 3] << 24);
  return true;
}

bool platform_in_comparable_mem(uint32_t addr) {
  return in_flash(addr) ||
         (addr >= NPC_SRAM_BASE && addr < NPC_SRAM_BASE + NPC_SRAM_SIZE) ||
         (addr >= NPC_SDRAM_BASE && addr < NPC_SDRAM_BASE + NPC_SDRAM_SIZE);
}

const char *platform_device_name(uint32_t addr) {
  if (addr >= 0x02000000u && addr <= 0x0200ffffu) return "clint";
  if (addr >= 0x10000000u && addr <= 0x10000fffu) return "uart16550";
  if (addr >= 0x10001000u && addr <= 0x10001fffu) return "spi";
  if (addr >= 0x10002000u && addr <= 0x1000200fu) return "gpio";
  if (addr >= 0x10011000u && addr <= 0x10011007u) return "ps2";
  if (addr >= 0x20000000u && addr <= 0x20000fffu) return "mrom";
  if (addr >= 0x21000000u && addr <= 0x211fffffu) return "vga";
  if (addr >= NPC_FLASH_BASE && addr < NPC_FLASH_BASE + NPC_FLASH_SIZE) return "flash";
  return NULL;
}

uint32_t platform_reset_pc() {
  return NPC_RESET_PC_YSYXSOC;
}

void platform_difftest_memcpy(void (*ref_memcpy)(uint32_t, void *, size_t, bool), bool direction) {
  if (flash_boot_loaded && flash_boot_size > 0) {
    ref_memcpy(NPC_FLASH_BASE, flash_image, flash_boot_size, direction);
  } else {
    Log("warning: no flash boot image loaded before DiffTest init");
  }
}

void platform_enable_ref_paddr(void (*enable_ysyxsoc_paddr)(void)) {
  assert(enable_ysyxsoc_paddr);
  enable_ysyxsoc_paddr();
}

extern "C" void flash_read(int32_t addr, int32_t *data) {
  assert(data != nullptr);
  if (!flash_initialized) {
    memset(flash_image, 0xff, sizeof(flash_image));
    flash_initialized = true;
  }

  uint32_t off = (uint32_t)addr & ~0x3u;
  if (off > NPC_FLASH_SIZE - 4u) {
    if (!flash_oob_warned) {
      fprintf(stderr, "flash_read: address out of range: 0x%08x\n", (uint32_t)addr);
      flash_oob_warned = true;
    }
    *data = -1;
    return;
  }

  *data = (int32_t)(((uint32_t)flash_image[off + 0]) |
                    ((uint32_t)flash_image[off + 1] << 8) |
                    ((uint32_t)flash_image[off + 2] << 16) |
                    ((uint32_t)flash_image[off + 3] << 24));
}

extern "C" void mrom_read(int32_t addr, int32_t *data) {
  (void)addr;
  assert(data != nullptr);
  *data = 0x00000013;
}
