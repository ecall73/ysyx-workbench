#include <assert.h>
#include <stdio.h>
#include <string.h>

#include <memory/paddr.h>
#include <isa.h>
#include <memory/host.h>
#include <platform/platform.h>

static uint8_t pmem[NPC_PMEM_SIZE] = {};
static long img_size = 0;

static bool in_npc_pmem(uint32_t addr) {
  return addr >= NPC_PMEM_BASE && addr < NPC_PMEM_BASE + NPC_PMEM_SIZE;
}

void platform_log_memory() {
  Log("physical memory area [0x%08x, 0x%08x]", NPC_PMEM_BASE, NPC_PMEM_BASE + NPC_PMEM_SIZE - 1);
}

void platform_init() {}
void platform_cleanup() {}
void platform_update() {}
void platform_set_external_idle(SimTop *top) { (void)top; }
uint32_t platform_reset_pc() { return NPC_RESET_PC_NPC; }

long platform_load_image(const char *img_file) {
  FILE *fp = fopen(img_file, "rb");
  Assert(fp, "Can not open '%s'", img_file);
  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  Assert(size > 0 && size <= NPC_PMEM_SIZE, "bad image size %ld", size);
  int ret = fread(pmem, size, 1, fp);
  assert(ret == 1);
  fclose(fp);
  img_size = size;
  Log("The image is %s, size = %ld", img_file, size);
  return size;
}

bool platform_read(paddr_t addr, int len, word_t *data) {
  if (len <= 0 || !in_npc_pmem(addr) || addr > NPC_PMEM_BASE + NPC_PMEM_SIZE - len) return false;
  *data = host_read(pmem + addr - NPC_PMEM_BASE, len);
  return true;
}

bool platform_write(paddr_t addr, int len, word_t data) {
  if (len <= 0 || !in_npc_pmem(addr) || addr > NPC_PMEM_BASE + NPC_PMEM_SIZE - len) return false;
  host_write(pmem + addr - NPC_PMEM_BASE, len, data);
  return true;
}

void platform_out_of_bound(paddr_t addr) {
  panic("address = " FMT_PADDR " is out of bound of pmem [0x%08x, 0x%08x] at pc = " FMT_WORD,
      addr, NPC_PMEM_BASE, NPC_PMEM_BASE + NPC_PMEM_SIZE - 1, cpu.pc);
}

const char *platform_device_name(uint32_t addr) {
  if (addr == 0x10000000u) return "uart";
  return NULL;
}

void platform_difftest_memcpy(void (*ref_memcpy)(paddr_t, void *, size_t, bool), bool direction) {
  if (img_size > 0) ref_memcpy(NPC_PMEM_BASE, pmem, (size_t)img_size, direction);
}

void platform_enable_ref_paddr(void (*enable_ysyxsoc_paddr)(void)) { (void)enable_ysyxsoc_paddr; }

extern "C" int pmem_read(int raddr) {
  word_t data = 0;
  if (!platform_read((uint32_t)raddr, 4, &data)) return 0;
  return (int)data;
}

extern "C" void pmem_write(int waddr, int wdata, unsigned char wmask) {
  uint32_t aligned = (uint32_t)waddr & ~0x3u;
  if (!in_npc_pmem(aligned) || aligned > NPC_PMEM_BASE + NPC_PMEM_SIZE - 4) return;
  uint8_t *p = pmem + aligned - NPC_PMEM_BASE;
  for (int i = 0; i < 4; i++) {
    if (wmask & (1u << i)) p[i] = (uint8_t)((uint32_t)wdata >> (i * 8));
  }
}
