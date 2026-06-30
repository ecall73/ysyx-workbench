#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <time.h>

#include "common.h"
#include "memory/paddr.h"
#include "platform/platform.h"
#include "utils.h"

static uint8_t pmem[MEM_SIZE];
static long img_size = 0;

static uint64_t get_time_us() {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (uint64_t)ts.tv_sec * 1000000 + (uint64_t)ts.tv_nsec / 1000;
}

static bool in_pmem(uint32_t addr) {
  return addr >= NPC_PMEM_BASE && addr < NPC_PMEM_BASE + NPC_PMEM_SIZE;
}

long platform_load_image(const char *img_file) {
  FILE *fp = fopen(img_file, "rb");
  if (fp == NULL) return 0;

  fseek(fp, 0, SEEK_END);
  long size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  int ret = fread(pmem, size, 1, fp);
  assert(ret == 1);
  fclose(fp);

  img_size = size;
  printf("The image is %s, size = %ld\n", img_file, size);
  return size;
}

bool platform_read_word(uint32_t addr, uint32_t *data) {
  uint32_t aligned = addr & ~0x3u;
  if (!in_pmem(aligned)) return false;
  *data = *(uint32_t *)&pmem[aligned - NPC_PMEM_BASE];
  return true;
}

bool platform_in_comparable_mem(uint32_t addr) {
  return in_pmem(addr);
}

void platform_difftest_memcpy(void (*ref_memcpy)(uint32_t, void *, size_t, bool), bool direction) {
  if (img_size > 0) {
    ref_memcpy(NPC_PMEM_BASE, pmem, (size_t)img_size, direction);
  } else {
    Log("warning: no pmem image loaded before DiffTest init");
  }
}

extern "C" int pmem_read(int raddr) {
  uint32_t aligned = (uint32_t)raddr & ~0x3u;
  if (aligned == RTC_ADDR || aligned == RTC_ADDR + 4) {
    uint64_t now = get_time_us();
    return (aligned == RTC_ADDR) ? (uint32_t)now : (uint32_t)(now >> 32);
  }

  uint32_t data = 0;
  return platform_read_word(aligned, &data) ? (int)data : 0;
}

extern "C" void pmem_write(int waddr, int wdata, char wmask) {
  uint32_t aligned = (uint32_t)waddr & ~0x3u;
  if (!in_pmem(aligned)) return;

  uint32_t *p = (uint32_t *)&pmem[aligned - NPC_PMEM_BASE];
  uint32_t mask = 0;
  if (wmask & 0x1) mask |= 0x000000ff;
  if (wmask & 0x2) mask |= 0x0000ff00;
  if (wmask & 0x4) mask |= 0x00ff0000;
  if (wmask & 0x8) mask |= 0xff000000;
  *p = (*p & ~mask) | ((uint32_t)wdata & mask);
}
