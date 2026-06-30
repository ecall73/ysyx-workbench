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
#include <difftest-def.h>
#include <device/mmio.h>
#include <isa.h>

void ysyxsoc_paddr_init(void);
bool ysyxsoc_paddr_read(paddr_t addr, int len, word_t *data);
bool ysyxsoc_paddr_write(paddr_t addr, int len, word_t data);
void ysyxsoc_paddr_log_ranges(void);
void ysyxsoc_paddr_out_of_bound(paddr_t addr);

#if   defined(CONFIG_PMEM_MALLOC)
static uint8_t *pmem = NULL;
#else // CONFIG_PMEM_GARRAY
static uint8_t pmem[CONFIG_MSIZE] PG_ALIGN = {};
#endif

static bool use_ysyxsoc_paddr = false;

uint8_t* guest_to_host(paddr_t paddr) { return pmem + paddr - CONFIG_MBASE; }
paddr_t host_to_guest(uint8_t *haddr) { return haddr - pmem + CONFIG_MBASE; }

static word_t pmem_read(paddr_t addr, int len) {
  return host_read(guest_to_host(addr), len);
}

static void pmem_write(paddr_t addr, int len, word_t data) {
  host_write(guest_to_host(addr), len, data);
}

static void out_of_bound(paddr_t addr) {
  panic("address = " FMT_PADDR " is out of bound of pmem [" FMT_PADDR ", " FMT_PADDR "] at pc = " FMT_WORD,
      addr, PMEM_LEFT, PMEM_RIGHT, cpu.pc);
}

__EXPORT void difftest_enable_ysyxsoc_paddr(void) {
  use_ysyxsoc_paddr = true;
}

void init_mem() {
#if   defined(CONFIG_PMEM_MALLOC)
  pmem = malloc(CONFIG_MSIZE);
  assert(pmem);
#endif
  IFDEF(CONFIG_MEM_RANDOM, memset(pmem, rand(), CONFIG_MSIZE));

  if (use_ysyxsoc_paddr) {
    ysyxsoc_paddr_init();
    Log("memory backend = ysyxsoc");
    ysyxsoc_paddr_log_ranges();
  } else {
    Log("physical memory area [" FMT_PADDR ", " FMT_PADDR "]", PMEM_LEFT, PMEM_RIGHT);
  }
}

word_t paddr_read(paddr_t addr, int len) {
  if (use_ysyxsoc_paddr) {
    word_t data = 0;
    if (likely(ysyxsoc_paddr_read(addr, len, &data))) {
      return data;
    }
    ysyxsoc_paddr_out_of_bound(addr);
    return 0;
  }

  if (likely(in_pmem(addr))) return pmem_read(addr, len);
  IFDEF(CONFIG_DEVICE, return mmio_read(addr, len));
  out_of_bound(addr);
  return 0;
}

void paddr_write(paddr_t addr, int len, word_t data) {
  if (use_ysyxsoc_paddr) {
    if (likely(ysyxsoc_paddr_write(addr, len, data))) {
      return;
    }
    ysyxsoc_paddr_out_of_bound(addr);
    return;
  }

  if (likely(in_pmem(addr))) { pmem_write(addr, len, data); return; }
  IFDEF(CONFIG_DEVICE, mmio_write(addr, len, data); return);
  out_of_bound(addr);
}
