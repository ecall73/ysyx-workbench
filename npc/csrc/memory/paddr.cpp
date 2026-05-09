#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "npc.h"

uint8_t pmem[MEM_SIZE];

static uint64_t get_time_us() {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000000 + (uint64_t)ts.tv_nsec / 1000;
}

bool check_bound(int addr, const char *type) {
    (void)type;
    if (addr < 0x80000000 || addr >= 0x80000000 + MEM_SIZE) {
        return false;
    }
    return true;
}

extern "C" int pmem_read(int raddr) {
    uint32_t aligned = (uint32_t)raddr & ~0x3u;
    if (aligned == RTC_ADDR || aligned == RTC_ADDR + 4) {
        uint64_t now = get_time_us();
        return (aligned == RTC_ADDR) ? (uint32_t)now : (uint32_t)(now >> 32);
    }

    if (!check_bound(aligned, "READ")) {
        return 0;
    }
    int index = aligned - 0x80000000;
    return *(int *)&pmem[index];
}

extern "C" void pmem_write(int waddr, int wdata, char wmask) {
    if (!check_bound(waddr, "WRITE")) {
        return;
    }

    int index = (waddr - 0x80000000) & ~0x3u;
    uint32_t *p = (uint32_t *)&pmem[index];
    uint32_t orig = *p;
    uint32_t mask = 0;
    if (wmask & 0x1) {
        mask |= 0x000000FF;
    }
    if (wmask & 0x2) {
        mask |= 0x0000FF00;
    }
    if (wmask & 0x4) {
        mask |= 0x00FF0000;
    }
    if (wmask & 0x8) {
        mask |= 0xFF000000;
    }

    *p = (orig & ~mask) | (wdata & mask);
}
