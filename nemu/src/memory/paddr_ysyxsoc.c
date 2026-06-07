#include <device/mmio.h>
#include <isa.h>
#include <string.h>

#include "paddr_backend.h"

#define FLASH_BASE 0x30000000u
#define FLASH_SIZE (16u * 1024u * 1024u)
#define FLASH_RIGHT (FLASH_BASE + FLASH_SIZE - 1)
#define SRAM_BASE 0x0f000000u
#define SRAM_SIZE 0x2000u
#define SRAM_RIGHT (SRAM_BASE + SRAM_SIZE - 1)
#define SDRAM_BASE 0xa0000000u
#define SDRAM_SIZE (32u * 1024u * 1024u)
#define SDRAM_RIGHT (SDRAM_BASE + SDRAM_SIZE - 1)

static uint8_t flash[FLASH_SIZE] = {};
static uint8_t sram[SRAM_SIZE] = {};
static uint8_t sdram[SDRAM_SIZE] = {};

static void ysyxsoc_init(void) {
  memset(flash, 0, sizeof(flash));
  memset(sram, 0, sizeof(sram));
  memset(sdram, 0, sizeof(sdram));
}

static bool ysyxsoc_read(paddr_t addr, int len, word_t *data) {
  if (nemu_in_region_range(addr, len, FLASH_BASE, FLASH_SIZE)) {
    *data = nemu_host_read_region(flash, addr, FLASH_BASE, len);
    return true;
  }
  if (nemu_in_region_range(addr, len, SRAM_BASE, SRAM_SIZE)) {
    *data = nemu_host_read_region(sram, addr, SRAM_BASE, len);
    return true;
  }
  if (nemu_in_region_range(addr, len, SDRAM_BASE, SDRAM_SIZE)) {
    *data = nemu_host_read_region(sdram, addr, SDRAM_BASE, len);
    return true;
  }
  IFDEF(CONFIG_DEVICE, {
    *data = mmio_read(addr, len);
    return true;
  });
  return false;
}

static bool ysyxsoc_write(paddr_t addr, int len, word_t data) {
  if (nemu_in_region_range(addr, len, FLASH_BASE, FLASH_SIZE)) {
    nemu_host_write_region(flash, addr, FLASH_BASE, len, data);
    return true;
  }
  if (nemu_in_region_range(addr, len, SRAM_BASE, SRAM_SIZE)) {
    nemu_host_write_region(sram, addr, SRAM_BASE, len, data);
    return true;
  }
  if (nemu_in_region_range(addr, len, SDRAM_BASE, SDRAM_SIZE)) {
    nemu_host_write_region(sdram, addr, SDRAM_BASE, len, data);
    return true;
  }
  IFDEF(CONFIG_DEVICE, {
    mmio_write(addr, len, data);
    return true;
  });
  return false;
}

static void ysyxsoc_log_ranges(void) {
  Log("FLASH area [0x%08x, 0x%08x]", FLASH_BASE, FLASH_RIGHT);
  Log("SRAM area [0x%08x, 0x%08x]", SRAM_BASE, SRAM_RIGHT);
  Log("SDRAM area [0x%08x, 0x%08x]", SDRAM_BASE, SDRAM_RIGHT);
}

static void ysyxsoc_out_of_bound(paddr_t addr) {
  panic("address = " FMT_PADDR " is out of bound for ysyxsoc backend. valid ranges: flash[0x%08x, 0x%08x], "
      "sram[0x%08x, 0x%08x], sdram[0x%08x, 0x%08x], pc = " FMT_WORD,
      addr, FLASH_BASE, FLASH_RIGHT, SRAM_BASE, SRAM_RIGHT, SDRAM_BASE, SDRAM_RIGHT, cpu.pc);
}

const NemuPaddrBackendOps *nemu_ysyxsoc_paddr_backend(void) {
  static const NemuPaddrBackendOps ops = {
    .name = "ysyxsoc",
    .init = ysyxsoc_init,
    .read = ysyxsoc_read,
    .write = ysyxsoc_write,
    .log_ranges = ysyxsoc_log_ranges,
    .out_of_bound = ysyxsoc_out_of_bound,
  };
  return &ops;
}
