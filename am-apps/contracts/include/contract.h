#ifndef AM_CONTRACT_H__
#define AM_CONTRACT_H__

#include <am.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifndef CONTRACT_ID
#define CONTRACT_ID "unknown"
#endif

static inline void contract_puts(const char *s) {
  while (*s) putch(*s++);
}

static inline void contract_puthex4(uint32_t v) {
  v &= 0xfu;
  putch((char)(v < 10 ? '0' + v : 'a' + v - 10));
}

static inline void contract_puthex32(uint32_t v) {
  contract_puts("0x");
  for (int i = 7; i >= 0; i--) {
    contract_puthex4(v >> (i * 4));
  }
}

static inline void contract_putu64(uint64_t v) {
  char buf[21];
  int n = 0;
  if (v == 0) {
    putch('0');
    return;
  }
  while (v != 0) {
    buf[n++] = (char)('0' + v % 10);
    v /= 10;
  }
  while (n > 0) putch(buf[--n]);
}

static inline void contract_begin(void) {
  contract_puts("CONTRACT " CONTRACT_ID " BEGIN\n");
}

static inline void contract_fail(const char *stage) __attribute__((noreturn));
static inline void contract_fail(const char *stage) {
  contract_puts("CONTRACT " CONTRACT_ID " FAIL ");
  contract_puts(stage);
  contract_puts("\n");
  halt(1);
}

static inline void contract_pass(void) __attribute__((noreturn));
static inline void contract_pass(void) {
  contract_puts("CONTRACT " CONTRACT_ID " PASS\n");
  halt(0);
}

static inline void contract_skip(const char *reason) __attribute__((noreturn));
static inline void contract_skip(const char *reason) {
  contract_puts("CONTRACT " CONTRACT_ID " SKIP ");
  contract_puts(reason);
  contract_puts("\n");
  contract_pass();
}

#define CONTRACT_CHECK(cond, stage) \
  do { \
    if (!(cond)) contract_fail(stage); \
  } while (0)

#endif
