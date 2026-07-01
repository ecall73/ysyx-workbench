#include <assert.h>
#include <stdio.h>
#include <string.h>

#include <nvboard.h>

#include <memory/host.h>
#include <memory/paddr.h>
#include <isa.h>
#include <platform/platform.h>
#include <sim_top.h>

void nvboard_bind_all_pins(SimTop *top);

static uint8_t flash[NPC_FLASH_SIZE];
static long flash_size = 0;

static bool in_flash(uint32_t addr) {
  return addr >= NPC_FLASH_BASE && addr < NPC_FLASH_BASE + NPC_FLASH_SIZE;
}

static bool in_range(uint32_t addr, int len, uint32_t base, uint32_t size) {
  return len > 0 && addr >= base && addr <= base + size - (uint32_t)len;
}

void platform_log_memory() {
  Log("ysyxsoc flash area [0x%08x, 0x%08x]", NPC_FLASH_BASE, NPC_FLASH_BASE + NPC_FLASH_SIZE - 1);
}

void platform_init() {
  nvboard_bind_all_pins(g_top);
  nvboard_init();
}

void platform_cleanup() { nvboard_quit(); }
void platform_update() { nvboard_update(); }

void platform_set_external_idle(SimTop *top) {
  top->externalPins_ps2_clk = 1;
  top->externalPins_ps2_data = 1;
  top->externalPins_uart_rx = 1;
}

uint32_t platform_reset_pc() { return NPC_RESET_PC_YSYXSOC; }

long platform_load_image(const char *img_file) {
  memset(flash, 0xff, sizeof(flash));
  FILE *fp = fopen(img_file, "rb");
  Assert(fp, "Can not open '%s'", img_file);
  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  Assert(size > 0 && size <= NPC_FLASH_SIZE, "bad image size %ld", size);
  size_t nread = fread(flash, 1, (size_t)size, fp);
  fclose(fp);
  assert(nread == (size_t)size);
  flash_size = size;
  Log("Flash boot image loaded: %s, size = %ld, base = 0x%08x", img_file, size, NPC_FLASH_BASE);
  return size;
}

bool platform_read(paddr_t addr, int len, word_t *data) {
  if (!in_range(addr, len, NPC_FLASH_BASE, NPC_FLASH_SIZE)) return false;
  *data = host_read(flash + addr - NPC_FLASH_BASE, len);
  return true;
}

bool platform_write(paddr_t addr, int len, word_t data) {
  if (!in_range(addr, len, NPC_FLASH_BASE, NPC_FLASH_SIZE)) return false;
  host_write(flash + addr - NPC_FLASH_BASE, len, data);
  return true;
}

void platform_out_of_bound(paddr_t addr) {
  panic("address = " FMT_PADDR " is out of bound of ysyxSoC flash [0x%08x, 0x%08x] at pc = " FMT_WORD,
      addr, NPC_FLASH_BASE, NPC_FLASH_BASE + NPC_FLASH_SIZE - 1, cpu.pc);
}

const char *platform_device_name(uint32_t addr) {
  if (addr >= 0x02000000u && addr <= 0x0200ffffu) return "clint";
  if (addr >= 0x10000000u && addr <= 0x10000fffu) return "uart16550";
  if (addr >= 0x10011000u && addr <= 0x10011007u) return "ps2";
  if (addr >= 0x21000000u && addr <= 0x211fffffu) return "vga";
  if (in_flash(addr)) return "flash";
  if (addr >= NPC_SRAM_BASE && addr < NPC_SRAM_BASE + NPC_SRAM_SIZE) return "sram";
  if (addr >= NPC_SDRAM_BASE && addr < NPC_SDRAM_BASE + NPC_SDRAM_SIZE) return "sdram";
  return NULL;
}

bool platform_in_comparable_mem(paddr_t addr) {
  return in_flash(addr);
}

void platform_difftest_memcpy(void (*ref_memcpy)(paddr_t, void *, size_t, bool), bool direction) {
  if (flash_size > 0) ref_memcpy(NPC_FLASH_BASE, flash, (size_t)flash_size, direction);
}

void platform_enable_ref_paddr(void (*enable_ysyxsoc_paddr)(void)) {
  assert(enable_ysyxsoc_paddr);
  enable_ysyxsoc_paddr();
}

extern "C" void flash_read(int addr, int *data) {
  uint32_t off = (uint32_t)addr & ~0x3u;
  if (off > NPC_FLASH_SIZE - 4) {
    *data = -1;
    return;
  }
  *data = (int)host_read(flash + off, 4);
}

extern "C" void mrom_read(int raddr, int *rdata) {
  (void)raddr;
  *rdata = 0x00000013;
}
