#ifndef __NPC_MEMORY_PADDR_H__
#define __NPC_MEMORY_PADDR_H__

#include <stddef.h>
#include <stdint.h>

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

long platform_load_image(const char *img_file);
bool platform_read_word(uint32_t addr, uint32_t *data);
bool platform_in_comparable_mem(uint32_t addr);
void platform_difftest_memcpy(void (*ref_memcpy)(uint32_t, void *, size_t, bool), bool direction);
void platform_enable_ref_paddr(void (*enable_ysyxsoc_paddr)(void));

#endif
