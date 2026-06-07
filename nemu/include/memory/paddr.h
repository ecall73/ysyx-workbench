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

#ifndef __MEMORY_PADDR_H__
#define __MEMORY_PADDR_H__

#include <common.h>

#define PMEM_LEFT  ((paddr_t)CONFIG_MBASE)
#define PMEM_RIGHT ((paddr_t)CONFIG_MBASE + CONFIG_MSIZE - 1)
#define RESET_VECTOR (PMEM_LEFT + CONFIG_PC_RESET_OFFSET)

typedef enum {
  NEMU_MEM_BACKEND_NATIVE = 0,
  NEMU_MEM_BACKEND_YSYXSOC = 1,
} NemuMemBackend;

typedef struct {
  const char *name;
  void (*init)(void);
  bool (*read)(paddr_t addr, int len, word_t *data);
  bool (*write)(paddr_t addr, int len, word_t data);
  void (*log_ranges)(void);
  void (*out_of_bound)(paddr_t addr);
} NemuPaddrBackendOps;

/* convert the guest physical address in the guest program to host virtual address in NEMU */
uint8_t* guest_to_host(paddr_t paddr);
/* convert the host virtual address in NEMU to guest physical address in the guest program */
paddr_t host_to_guest(uint8_t *haddr);

static inline bool in_pmem(paddr_t addr) {
  return addr - CONFIG_MBASE < CONFIG_MSIZE;
}

void nemu_set_mem_backend(NemuMemBackend backend);
NemuMemBackend nemu_get_mem_backend(void);
bool nemu_in_region_range(paddr_t addr, int len, paddr_t base, uint32_t size);
word_t nemu_host_read_region(uint8_t *space, paddr_t addr, paddr_t base, int len);
void nemu_host_write_region(uint8_t *space, paddr_t addr, paddr_t base, int len, word_t data);
uint8_t *nemu_pmem_base(void);
const NemuPaddrBackendOps *nemu_native_paddr_backend(void);
const NemuPaddrBackendOps *nemu_ysyxsoc_paddr_backend(void);

word_t paddr_read(paddr_t addr, int len);
void paddr_write(paddr_t addr, int len, word_t data);

#endif
