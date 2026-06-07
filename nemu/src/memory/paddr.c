/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include <memory/host.h>
#include <memory/paddr.h>
#include <device/mmio.h>
#include <isa.h>

#define MROM_BASE 0x20000000u
#define MROM_SIZE 0x1000u
#define MROM_RIGHT (MROM_BASE + MROM_SIZE - 1)
#define FLASH_BASE 0x30000000u
#define FLASH_SIZE (16u * 1024u * 1024u)
#define FLASH_RIGHT (FLASH_BASE + FLASH_SIZE - 1)
#define SRAM_BASE 0x0f000000u
#define SRAM_SIZE 0x2000u
#define SRAM_RIGHT (SRAM_BASE + SRAM_SIZE - 1)
#define SDRAM_BASE 0xa0000000u
#define SDRAM_SIZE (32u * 1024u * 1024u)
#define SDRAM_RIGHT (SDRAM_BASE + SDRAM_SIZE - 1)

#if   defined(CONFIG_PMEM_MALLOC)
static uint8_t *pmem = NULL;
#else // CONFIG_PMEM_GARRAY
static uint8_t pmem[CONFIG_MSIZE] PG_ALIGN = {};
#endif

static uint8_t mrom[MROM_SIZE] = {};
static uint8_t flash[FLASH_SIZE] = {};
static uint8_t sram[SRAM_SIZE] = {};
static uint8_t sdram[SDRAM_SIZE] = {};
static bool soc_memory_map_active = false;

uint8_t* guest_to_host(paddr_t paddr) { return pmem + paddr - CONFIG_MBASE; }
paddr_t host_to_guest(uint8_t *haddr) { return haddr - pmem + CONFIG_MBASE; }

static inline bool in_region_range(paddr_t addr, int len, paddr_t base, uint32_t size) {
  if (len <= 0) return false;
  if (addr < base) return false;
  uint64_t off = (uint64_t)(addr - base);
  return off + (uint64_t)len <= (uint64_t)size;
}

static inline bool in_pmem_range(paddr_t addr, int len) {
  return in_region_range(addr, len, CONFIG_MBASE, CONFIG_MSIZE);
}

static inline bool in_mrom_range(paddr_t addr, int len) {
  return in_region_range(addr, len, MROM_BASE, MROM_SIZE);
}

static inline bool in_sram_range(paddr_t addr, int len) {
  return in_region_range(addr, len, SRAM_BASE, SRAM_SIZE);
}

static inline bool in_flash_range(paddr_t addr, int len) {
  return in_region_range(addr, len, FLASH_BASE, FLASH_SIZE);
}

static inline bool in_sdram_range(paddr_t addr, int len) {
  return in_region_range(addr, len, SDRAM_BASE, SDRAM_SIZE);
}

static inline bool in_soc_boot_range(paddr_t addr, int len) {
  return in_mrom_range(addr, len) || in_flash_range(addr, len) || in_sram_range(addr, len);
}

static inline void activate_soc_memory_map_if_needed(paddr_t addr, int len) {
  if (!soc_memory_map_active && in_soc_boot_range(addr, len)) {
    soc_memory_map_active = true;
  }
}

static word_t mem_read(uint8_t *space, paddr_t addr, paddr_t base, int len) {
  word_t ret = host_read(space + (addr - base), len);
  return ret;
}

static void mem_write(uint8_t *space, paddr_t addr, paddr_t base, int len, word_t data) {
  host_write(space + (addr - base), len, data);
}

static void out_of_bound(paddr_t addr) {
  panic("address = " FMT_PADDR " is out of bound. valid ranges: pmem[" FMT_PADDR ", " FMT_PADDR "], "
      "mrom[0x%08x, 0x%08x], flash[0x%08x, 0x%08x], sram[0x%08x, 0x%08x], sdram[0x%08x, 0x%08x], pc = " FMT_WORD,
      addr, PMEM_LEFT, PMEM_RIGHT, MROM_BASE, MROM_RIGHT, FLASH_BASE, FLASH_RIGHT, SRAM_BASE, SRAM_RIGHT, SDRAM_BASE, SDRAM_RIGHT, cpu.pc);
}

void init_mem() {
#if   defined(CONFIG_PMEM_MALLOC)
  pmem = malloc(CONFIG_MSIZE);
  assert(pmem);
#endif
  IFDEF(CONFIG_MEM_RANDOM, memset(pmem, rand(), CONFIG_MSIZE));
  memset(mrom, 0, sizeof(mrom));
  memset(flash, 0, sizeof(flash));
  memset(sram, 0, sizeof(sram));
  memset(sdram, 0, sizeof(sdram));
  soc_memory_map_active = false;
  Log("physical memory area [" FMT_PADDR ", " FMT_PADDR "]", PMEM_LEFT, PMEM_RIGHT);
  Log("MROM area [0x%08x, 0x%08x]", MROM_BASE, MROM_RIGHT);
  Log("FLASH area [0x%08x, 0x%08x]", FLASH_BASE, FLASH_RIGHT);
  Log("SRAM area [0x%08x, 0x%08x]", SRAM_BASE, SRAM_RIGHT);
  Log("SDRAM area [0x%08x, 0x%08x]", SDRAM_BASE, SDRAM_RIGHT);
}

#ifdef CONFIG_MTRACE
static inline void mtrace_log_read(paddr_t addr, int len, word_t data) {
  if ((MTRACE_COND)) {
    log_write("mtrace: R " FMT_PADDR " len=%d data=" FMT_WORD "\n", addr, len, data);
  }
}

static inline void mtrace_log_write(paddr_t addr, int len, word_t data) {
  if ((MTRACE_COND)) {
    log_write("mtrace: W " FMT_PADDR " len=%d data=" FMT_WORD "\n", addr, len, data);
  }
}
#endif

word_t paddr_read(paddr_t addr, int len) {
  if (likely(in_pmem_range(addr, len))) {
    word_t data = mem_read(pmem, addr, CONFIG_MBASE, len);
    IFDEF(CONFIG_MTRACE, mtrace_log_read(addr, len, data));
    return data;
  }
  activate_soc_memory_map_if_needed(addr, len);
  if (likely(soc_memory_map_active && in_mrom_range(addr, len))) {
    word_t data = mem_read(mrom, addr, MROM_BASE, len);
    IFDEF(CONFIG_MTRACE, mtrace_log_read(addr, len, data));
    return data;
  }
  if (likely(soc_memory_map_active && in_flash_range(addr, len))) {
    word_t data = mem_read(flash, addr, FLASH_BASE, len);
    IFDEF(CONFIG_MTRACE, mtrace_log_read(addr, len, data));
    return data;
  }
  if (likely(soc_memory_map_active && in_sram_range(addr, len))) {
    word_t data = mem_read(sram, addr, SRAM_BASE, len);
    IFDEF(CONFIG_MTRACE, mtrace_log_read(addr, len, data));
    return data;
  }
  if (likely(soc_memory_map_active && in_sdram_range(addr, len))) {
    word_t data = mem_read(sdram, addr, SDRAM_BASE, len);
    IFDEF(CONFIG_MTRACE, mtrace_log_read(addr, len, data));
    return data;
  }
  IFDEF(CONFIG_DEVICE, {
    word_t data = mmio_read(addr, len);
    IFDEF(CONFIG_MTRACE, mtrace_log_read(addr, len, data));
    return data;
  });
  out_of_bound(addr);
  return 0;
}

void paddr_write(paddr_t addr, int len, word_t data) {
  if (likely(in_pmem_range(addr, len))) {
    mem_write(pmem, addr, CONFIG_MBASE, len, data);
    IFDEF(CONFIG_MTRACE, mtrace_log_write(addr, len, data));
    return;
  }
  activate_soc_memory_map_if_needed(addr, len);
  if (likely(soc_memory_map_active && in_mrom_range(addr, len))) {
    mem_write(mrom, addr, MROM_BASE, len, data);
    IFDEF(CONFIG_MTRACE, mtrace_log_write(addr, len, data));
    return;
  }
  if (likely(soc_memory_map_active && in_flash_range(addr, len))) {
    mem_write(flash, addr, FLASH_BASE, len, data);
    IFDEF(CONFIG_MTRACE, mtrace_log_write(addr, len, data));
    return;
  }
  if (likely(soc_memory_map_active && in_sram_range(addr, len))) {
    mem_write(sram, addr, SRAM_BASE, len, data);
    IFDEF(CONFIG_MTRACE, mtrace_log_write(addr, len, data));
    return;
  }
  if (likely(soc_memory_map_active && in_sdram_range(addr, len))) {
    mem_write(sdram, addr, SDRAM_BASE, len, data);
    IFDEF(CONFIG_MTRACE, mtrace_log_write(addr, len, data));
    return;
  }
  IFDEF(CONFIG_DEVICE, {
    mmio_write(addr, len, data);
    IFDEF(CONFIG_MTRACE, mtrace_log_write(addr, len, data));
    return;
  });
  out_of_bound(addr);
}
