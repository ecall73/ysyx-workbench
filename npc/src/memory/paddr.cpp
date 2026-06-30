#include <stdint.h>
#include <time.h>

#include "memory/paddr.h"

static uint8_t pmem[MEM_SIZE];

static uint64_t get_time_us() {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (uint64_t)ts.tv_sec * 1000000 + (uint64_t)ts.tv_nsec / 1000;
}

uint8_t *guest_to_host(uint32_t paddr) {
  return pmem + paddr - NPC_PMEM_BASE;
}

uint32_t host_to_guest(uint8_t *haddr) {
  return haddr - pmem + NPC_PMEM_BASE;
}

bool in_pmem(uint32_t addr) {
  return addr >= NPC_PMEM_BASE && addr < NPC_PMEM_BASE + NPC_PMEM_SIZE;
}

uint32_t pmem_read_word(uint32_t addr) {
  return *(uint32_t *)guest_to_host(addr);
}

void pmem_write_word(uint32_t addr, uint32_t data, uint8_t wmask) {
  uint32_t *p = (uint32_t *)guest_to_host(addr);
  uint32_t mask = 0;
  if (wmask & 0x1) mask |= 0x000000ff;
  if (wmask & 0x2) mask |= 0x0000ff00;
  if (wmask & 0x4) mask |= 0x00ff0000;
  if (wmask & 0x8) mask |= 0xff000000;
  *p = (*p & ~mask) | (data & mask);
}

uint8_t *pmem_base() {
  return pmem;
}

extern "C" int pmem_read(int raddr) {
  uint32_t aligned = (uint32_t)raddr & ~0x3u;
  if (aligned == RTC_ADDR || aligned == RTC_ADDR + 4) {
    uint64_t now = get_time_us();
    return (aligned == RTC_ADDR) ? (uint32_t)now : (uint32_t)(now >> 32);
  }

  return in_pmem(aligned) ? (int)pmem_read_word(aligned) : 0;
}

extern "C" void pmem_write(int waddr, int wdata, char wmask) {
  uint32_t aligned = (uint32_t)waddr & ~0x3u;
  if (in_pmem(aligned)) {
    pmem_write_word(aligned, (uint32_t)wdata, (uint8_t)wmask);
  }
}
