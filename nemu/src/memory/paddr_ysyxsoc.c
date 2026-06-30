#include <device/mmio.h>
#include <isa.h>
#include <memory/host.h>
#include <string.h>
#include <memory/paddr_internal.h>

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

static bool in_region(paddr_t addr, int len, paddr_t base, uint32_t size) {
  if (len <= 0) return false;
  if (addr < base) return false;
  uint64_t off = (uint64_t)(addr - base);
  return off + (uint64_t)len <= (uint64_t)size;
}

void ysyxsoc_paddr_init(void) {
  memset(flash, 0, sizeof(flash));
  memset(sram, 0, sizeof(sram));
  memset(sdram, 0, sizeof(sdram));
}

bool ysyxsoc_paddr_read(paddr_t addr, int len, word_t *data) {
  if (in_region(addr, len, FLASH_BASE, FLASH_SIZE)) {
    *data = host_read(flash + (addr - FLASH_BASE), len);
    return true;
  }
  if (in_region(addr, len, SRAM_BASE, SRAM_SIZE)) {
    *data = host_read(sram + (addr - SRAM_BASE), len);
    return true;
  }
  if (in_region(addr, len, SDRAM_BASE, SDRAM_SIZE)) {
    *data = host_read(sdram + (addr - SDRAM_BASE), len);
    return true;
  }
  IFDEF(CONFIG_DEVICE, {
    *data = mmio_read(addr, len);
    return true;
  });
  return false;
}

bool ysyxsoc_paddr_write(paddr_t addr, int len, word_t data) {
  if (in_region(addr, len, FLASH_BASE, FLASH_SIZE)) {
    host_write(flash + (addr - FLASH_BASE), len, data);
    return true;
  }
  if (in_region(addr, len, SRAM_BASE, SRAM_SIZE)) {
    host_write(sram + (addr - SRAM_BASE), len, data);
    return true;
  }
  if (in_region(addr, len, SDRAM_BASE, SDRAM_SIZE)) {
    host_write(sdram + (addr - SDRAM_BASE), len, data);
    return true;
  }
  IFDEF(CONFIG_DEVICE, {
    mmio_write(addr, len, data);
    return true;
  });
  return false;
}

void ysyxsoc_paddr_log_ranges(void) {
  Log("FLASH area [0x%08x, 0x%08x]", FLASH_BASE, FLASH_RIGHT);
  Log("SRAM area [0x%08x, 0x%08x]", SRAM_BASE, SRAM_RIGHT);
  Log("SDRAM area [0x%08x, 0x%08x]", SDRAM_BASE, SDRAM_RIGHT);
}

void ysyxsoc_paddr_out_of_bound(paddr_t addr) {
  panic("address = " FMT_PADDR " is out of bound for ysyxsoc memory. valid ranges: flash[0x%08x, 0x%08x], "
      "sram[0x%08x, 0x%08x], sdram[0x%08x, 0x%08x], pc = " FMT_WORD,
      addr, FLASH_BASE, FLASH_RIGHT, SRAM_BASE, SRAM_RIGHT, SDRAM_BASE, SDRAM_RIGHT, cpu.pc);
}
