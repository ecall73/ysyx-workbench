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
#include <memory/paddr_internal.h>

#if   defined(CONFIG_PMEM_MALLOC)
static uint8_t *pmem = NULL;
#else // CONFIG_PMEM_GARRAY
static uint8_t pmem[CONFIG_MSIZE] PG_ALIGN = {};
#endif

static const NemuPaddrBackendOps *current_backend = NULL;

uint8_t* guest_to_host(paddr_t paddr) { return pmem + paddr - CONFIG_MBASE; }
paddr_t host_to_guest(uint8_t *haddr) { return haddr - pmem + CONFIG_MBASE; }

uint8_t *nemu_pmem_base(void) {
  return pmem;
}

bool nemu_in_region_range(paddr_t addr, int len, paddr_t base, uint32_t size) {
  if (len <= 0) return false;
  if (addr < base) return false;
  uint64_t off = (uint64_t)(addr - base);
  return off + (uint64_t)len <= (uint64_t)size;
}

word_t nemu_host_read_region(uint8_t *space, paddr_t addr, paddr_t base, int len) {
  return host_read(space + (addr - base), len);
}

void nemu_host_write_region(uint8_t *space, paddr_t addr, paddr_t base, int len, word_t data) {
  host_write(space + (addr - base), len, data);
}

void nemu_select_ysyxsoc_paddr_backend(void) {
  current_backend = nemu_ysyxsoc_paddr_backend();
}

static void out_of_bound(paddr_t addr) {
  current_backend->out_of_bound(addr);
}

void init_mem() {
#if   defined(CONFIG_PMEM_MALLOC)
  pmem = malloc(CONFIG_MSIZE);
  assert(pmem);
#endif
  IFDEF(CONFIG_MEM_RANDOM, memset(pmem, rand(), CONFIG_MSIZE));
  if (current_backend == NULL) {
    current_backend = nemu_native_paddr_backend();
  }
  if (current_backend->init != NULL) {
    current_backend->init();
  }
  Log("memory backend = %s", current_backend->name);
  current_backend->log_ranges();
}

word_t paddr_read(paddr_t addr, int len) {
  word_t data = 0;
  if (likely(current_backend->read(addr, len, &data))) {
    return data;
  }
  out_of_bound(addr);
  return 0;
}

void paddr_write(paddr_t addr, int len, word_t data) {
  if (likely(current_backend->write(addr, len, data))) {
    return;
  }
  out_of_bound(addr);
}
