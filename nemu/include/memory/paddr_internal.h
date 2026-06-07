#ifndef __MEMORY_PADDR_INTERNAL_H__
#define __MEMORY_PADDR_INTERNAL_H__

#include <memory/paddr.h>

typedef struct {
  const char *name;
  void (*init)(void);
  bool (*read)(paddr_t addr, int len, word_t *data);
  bool (*write)(paddr_t addr, int len, word_t data);
  void (*log_ranges)(void);
  void (*out_of_bound)(paddr_t addr);
} NemuPaddrBackendOps;

bool nemu_in_region_range(paddr_t addr, int len, paddr_t base, uint32_t size);
word_t nemu_host_read_region(uint8_t *space, paddr_t addr, paddr_t base, int len);
void nemu_host_write_region(uint8_t *space, paddr_t addr, paddr_t base, int len, word_t data);
uint8_t *nemu_pmem_base(void);
const NemuPaddrBackendOps *nemu_native_paddr_backend(void);
const NemuPaddrBackendOps *nemu_ysyxsoc_paddr_backend(void);
void nemu_select_ysyxsoc_paddr_backend(void);

#endif
