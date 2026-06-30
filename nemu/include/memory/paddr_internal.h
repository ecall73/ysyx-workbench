#ifndef __MEMORY_PADDR_INTERNAL_H__
#define __MEMORY_PADDR_INTERNAL_H__

#include <memory/paddr.h>

void nemu_enable_ysyxsoc_paddr(void);

void ysyxsoc_paddr_init(void);
bool ysyxsoc_paddr_read(paddr_t addr, int len, word_t *data);
bool ysyxsoc_paddr_write(paddr_t addr, int len, word_t data);
void ysyxsoc_paddr_log_ranges(void);
void ysyxsoc_paddr_out_of_bound(paddr_t addr);

#endif
