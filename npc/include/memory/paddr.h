#ifndef __NPC_MEMORY_PADDR_H__
#define __NPC_MEMORY_PADDR_H__

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

uint8_t *guest_to_host(uint32_t paddr);
uint32_t host_to_guest(uint8_t *haddr);
bool in_pmem(uint32_t addr);
uint32_t pmem_read_word(uint32_t addr);
void pmem_write_word(uint32_t addr, uint32_t data, uint8_t wmask);
uint8_t *pmem_base();

#endif
