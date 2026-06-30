#ifndef __NPC_COMMON_H__
#define __NPC_COMMON_H__

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <assert.h>

#include "generated/autoconf.h"

#define ANSI_FG_BLACK   "\33[1;30m"
#define ANSI_FG_RED     "\33[1;31m"
#define ANSI_FG_GREEN   "\33[1;32m"
#define ANSI_FG_YELLOW  "\33[1;33m"
#define ANSI_FG_BLUE    "\33[1;34m"
#define ANSI_FG_MAGENTA "\33[1;35m"
#define ANSI_FG_CYAN    "\33[1;36m"
#define ANSI_FG_WHITE   "\33[1;37m"
#define ANSI_BG_BLACK   "\33[1;40m"
#define ANSI_BG_RED     "\33[1;41m"
#define ANSI_BG_GREEN   "\33[1;42m"
#define ANSI_BG_YELLOW  "\33[1;43m"
#define ANSI_BG_BLUE    "\33[1;44m"
#define ANSI_BG_MAGENTA "\33[1;45m"
#define ANSI_BG_CYAN    "\33[1;46m"
#define ANSI_BG_WHITE   "\33[1;47m"
#define ANSI_NONE       "\33[0m"
#define ANSI_FMT(str, fmt) fmt str ANSI_NONE

typedef uint32_t word_t;
typedef uint32_t vaddr_t;
#define FMT_WORD "0x%08" PRIx32

#define Assert(cond, format, ...) do { \
  if (!(cond)) { \
    fprintf(stderr, ANSI_FMT(format, ANSI_FG_RED) "\n", ##__VA_ARGS__); \
    assert(cond); \
  } \
} while (0)

#ifndef CONFIG_MAX_SIM_TIME
#define CONFIG_MAX_SIM_TIME 1000000000
#endif

#endif
