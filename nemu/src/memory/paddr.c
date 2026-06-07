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
#include <string.h>

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

static uint8_t flash[FLASH_SIZE] = {};
static uint8_t sram[SRAM_SIZE] = {};
static uint8_t sdram[SDRAM_SIZE] = {};

#ifdef CONFIG_TARGET_SHARE
static NemuMachineProfile current_machine_profile = NEMU_MACHINE_NPC_REF;
#else
static NemuMachineProfile current_machine_profile = NEMU_MACHINE_STANDALONE;
#endif

uint8_t* guest_to_host(paddr_t paddr) { return pmem + paddr - CONFIG_MBASE; }
paddr_t host_to_guest(uint8_t *haddr) { return haddr - pmem + CONFIG_MBASE; }

void nemu_set_machine_profile(NemuMachineProfile profile) {
  current_machine_profile = profile;
}

NemuMachineProfile nemu_get_machine_profile(void) {
  return current_machine_profile;
}

const char *nemu_machine_profile_name(NemuMachineProfile profile) {
  switch (profile) {
    case NEMU_MACHINE_STANDALONE: return "standalone";
    case NEMU_MACHINE_NPC_REF: return "npc-ref";
    case NEMU_MACHINE_YSYXSOC_REF: return "ysyxsoc-ref";
    default: return "unknown";
  }
}

bool nemu_parse_machine_profile(const char *name, NemuMachineProfile *out) {
  if (name == NULL || out == NULL) return false;
  if (strcmp(name, "standalone") == 0 || strcmp(name, "nemu") == 0) {
    *out = NEMU_MACHINE_STANDALONE;
    return true;
  }
  if (strcmp(name, "npc-ref") == 0 || strcmp(name, "npc") == 0) {
    *out = NEMU_MACHINE_NPC_REF;
    return true;
  }
  if (strcmp(name, "ysyxsoc-ref") == 0 || strcmp(name, "ysyxsoc") == 0) {
    *out = NEMU_MACHINE_YSYXSOC_REF;
    return true;
  }
  return false;
}

static inline bool in_region_range(paddr_t addr, int len, paddr_t base, uint32_t size) {
  if (len <= 0) return false;
  if (addr < base) return false;
  uint64_t off = (uint64_t)(addr - base);
  return off + (uint64_t)len <= (uint64_t)size;
}

static inline bool in_pmem_range(paddr_t addr, int len) {
  return in_region_range(addr, len, CONFIG_MBASE, CONFIG_MSIZE);
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

static inline bool machine_uses_soc_memory_map(void) {
  return current_machine_profile == NEMU_MACHINE_YSYXSOC_REF;
}

static word_t mem_read(uint8_t *space, paddr_t addr, paddr_t base, int len) {
  word_t ret = host_read(space + (addr - base), len);
  return ret;
}

static void mem_write(uint8_t *space, paddr_t addr, paddr_t base, int len, word_t data) {
  host_write(space + (addr - base), len, data);
}

static void out_of_bound(paddr_t addr) {
  if (machine_uses_soc_memory_map()) {
    panic("address = " FMT_PADDR " is out of bound for machine=%s. valid ranges: pmem[" FMT_PADDR ", " FMT_PADDR "], "
        "flash[0x%08x, 0x%08x], sram[0x%08x, 0x%08x], sdram[0x%08x, 0x%08x], pc = " FMT_WORD,
        addr, nemu_machine_profile_name(current_machine_profile), PMEM_LEFT, PMEM_RIGHT,
        FLASH_BASE, FLASH_RIGHT, SRAM_BASE, SRAM_RIGHT, SDRAM_BASE, SDRAM_RIGHT, cpu.pc);
  } else {
    panic("address = " FMT_PADDR " is out of bound for machine=%s. valid ranges: pmem[" FMT_PADDR ", " FMT_PADDR "], pc = " FMT_WORD,
        addr, nemu_machine_profile_name(current_machine_profile), PMEM_LEFT, PMEM_RIGHT, cpu.pc);
  }
}

void init_mem() {
#if   defined(CONFIG_PMEM_MALLOC)
  pmem = malloc(CONFIG_MSIZE);
  assert(pmem);
#endif
  IFDEF(CONFIG_MEM_RANDOM, memset(pmem, rand(), CONFIG_MSIZE));
  memset(flash, 0, sizeof(flash));
  memset(sram, 0, sizeof(sram));
  memset(sdram, 0, sizeof(sdram));
  Log("machine profile = %s", nemu_machine_profile_name(current_machine_profile));
  Log("physical memory area [" FMT_PADDR ", " FMT_PADDR "]", PMEM_LEFT, PMEM_RIGHT);
  if (machine_uses_soc_memory_map()) {
    Log("FLASH area [0x%08x, 0x%08x]", FLASH_BASE, FLASH_RIGHT);
    Log("SRAM area [0x%08x, 0x%08x]", SRAM_BASE, SRAM_RIGHT);
    Log("SDRAM area [0x%08x, 0x%08x]", SDRAM_BASE, SDRAM_RIGHT);
  }
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
  if (likely(machine_uses_soc_memory_map() && in_flash_range(addr, len))) {
    word_t data = mem_read(flash, addr, FLASH_BASE, len);
    IFDEF(CONFIG_MTRACE, mtrace_log_read(addr, len, data));
    return data;
  }
  if (likely(machine_uses_soc_memory_map() && in_sram_range(addr, len))) {
    word_t data = mem_read(sram, addr, SRAM_BASE, len);
    IFDEF(CONFIG_MTRACE, mtrace_log_read(addr, len, data));
    return data;
  }
  if (likely(machine_uses_soc_memory_map() && in_sdram_range(addr, len))) {
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
  if (likely(machine_uses_soc_memory_map() && in_flash_range(addr, len))) {
    mem_write(flash, addr, FLASH_BASE, len, data);
    IFDEF(CONFIG_MTRACE, mtrace_log_write(addr, len, data));
    return;
  }
  if (likely(machine_uses_soc_memory_map() && in_sram_range(addr, len))) {
    mem_write(sram, addr, SRAM_BASE, len, data);
    IFDEF(CONFIG_MTRACE, mtrace_log_write(addr, len, data));
    return;
  }
  if (likely(machine_uses_soc_memory_map() && in_sdram_range(addr, len))) {
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
