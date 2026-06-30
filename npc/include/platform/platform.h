#ifndef __NPC_PLATFORM_PLATFORM_H__
#define __NPC_PLATFORM_PLATFORM_H__

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

#endif
