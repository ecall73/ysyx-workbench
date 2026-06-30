#ifndef __NPC_PLATFORM_PLATFORM_H__
#define __NPC_PLATFORM_PLATFORM_H__

#include <stddef.h>
#include <stdint.h>

#include "sim_top.h"

extern SimTop *g_top;
extern VerilatedContext *g_contextp;
extern VerilatedVcdC *g_tfp;

void platform_init();
void platform_cleanup();
void platform_update();
void platform_set_external_idle(SimTop *top);
const char *platform_device_name(uint32_t addr);
uint32_t platform_reset_pc();
long platform_load_image(const char *img_file);
bool platform_read_word(uint32_t addr, uint32_t *data);
bool platform_in_comparable_mem(uint32_t addr);
void platform_difftest_memcpy(void (*ref_memcpy)(uint32_t, void *, size_t, bool), bool direction);
void platform_enable_ref_paddr(void (*enable_ysyxsoc_paddr)(void));

#endif
