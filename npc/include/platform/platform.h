#ifndef __NPC_PLATFORM_PLATFORM_H__
#define __NPC_PLATFORM_PLATFORM_H__

#include <stddef.h>
#include <stdint.h>

#include "sim_top.h"

#define MEM_SIZE 0x8000000
#define SERIAL_PORT 0x10000000
#define RTC_ADDR    0x00100048

#define NPC_PMEM_BASE        0x80000000u
#define NPC_PMEM_SIZE        MEM_SIZE
#define NPC_FLASH_BASE       0x30000000u
#define NPC_FLASH_SIZE       0x01000000u
#define NPC_SRAM_BASE        0x0f000000u
#define NPC_SRAM_SIZE        0x00002000u
#define NPC_SDRAM_BASE       0xa0000000u
#define NPC_SDRAM_SIZE       0x02000000u
#define NPC_RESET_PC_NPC     NPC_PMEM_BASE
#define NPC_RESET_PC_YSYXSOC NPC_FLASH_BASE

extern SimTop *g_top;
extern VerilatedContext *g_contextp;
extern VerilatedVcdC *g_tfp;

void platform_init();
void platform_cleanup();
void platform_update();
void platform_set_external_idle(SimTop *top);
long platform_load_image(const char *img_file);
bool platform_read_word(uint32_t addr, uint32_t *data);
bool platform_in_comparable_mem(uint32_t addr);
const char *platform_device_name(uint32_t addr);
uint32_t platform_reset_pc();
void platform_difftest_memcpy(void (*ref_memcpy)(uint32_t, void *, size_t, bool), bool direction);
void platform_enable_ref_paddr(void (*enable_ysyxsoc_paddr)(void));

#endif
