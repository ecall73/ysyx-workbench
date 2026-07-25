#ifndef __RISCV32_TIMER_H__
#define __RISCV32_TIMER_H__

#include <common.h>

bool riscv_clint_read(paddr_t addr, int len, word_t *data);
bool riscv_clint_write(paddr_t addr, int len, word_t data);

#endif
