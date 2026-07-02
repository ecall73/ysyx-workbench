#include <contract.h>
#include <klib.h>

static uint8_t buf[96];
static uint8_t src[96];

static void fill_seq(uint8_t *p, size_t n, uint8_t seed) {
  for (size_t i = 0; i < n; i++) p[i] = (uint8_t)(seed + i);
}

static bool local_streq(const char *a, const char *b) {
  size_t i = 0;
  while (a[i] != '\0' && b[i] != '\0' && a[i] == b[i]) i++;
  return a[i] == b[i];
}

static bool local_memeq(const uint8_t *a, const uint8_t *b, size_t n) {
  for (size_t i = 0; i < n; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

static void check_range(const uint8_t *p, size_t n, uint8_t val, const char *stage) {
  for (size_t i = 0; i < n; i++) CONTRACT_CHECK(p[i] == val, stage);
}

static void check_seq(const uint8_t *p, size_t n, uint8_t seed, const char *stage) {
  for (size_t i = 0; i < n; i++) CONTRACT_CHECK(p[i] == (uint8_t)(seed + i), stage);
}

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(strlen("") == 0, "strlen-empty");
  CONTRACT_CHECK(strlen("abcdef") == 6, "strlen");
  CONTRACT_CHECK(strlen("ab\0hidden") == 2, "strlen-early-nul");

  fill_seq(buf, sizeof(buf), 0xa0);
  char *dst = (char *)buf + 8;
  CONTRACT_CHECK(strcpy(dst, "riscv") == dst, "strcpy-ret");
  CONTRACT_CHECK(local_streq(dst, "riscv"), "strcpy-data");
  check_seq(buf, 8, 0xa0, "strcpy-before");
  check_seq(buf + 14, 8, (uint8_t)(0xa0 + 14), "strcpy-after");

  fill_seq(buf, sizeof(buf), 0xb0);
  dst = (char *)buf + 8;
  CONTRACT_CHECK(strncpy(dst, "xy", 5) == dst, "strncpy-pad-ret");
  CONTRACT_CHECK(dst[0] == 'x' && dst[1] == 'y', "strncpy-pad-data");
  CONTRACT_CHECK(dst[2] == '\0' && dst[3] == '\0' && dst[4] == '\0', "strncpy-pad-zero");
  check_seq(buf, 8, 0xb0, "strncpy-pad-before");
  check_seq(buf + 13, 8, (uint8_t)(0xb0 + 13), "strncpy-pad-after");

  fill_seq(buf, sizeof(buf), 0xc0);
  dst = (char *)buf + 8;
  CONTRACT_CHECK(strncpy(dst, "abcdef", 3) == dst, "strncpy-cut-ret");
  CONTRACT_CHECK(dst[0] == 'a' && dst[1] == 'b' && dst[2] == 'c', "strncpy-cut-data");
  CONTRACT_CHECK((uint8_t)dst[3] == (uint8_t)(0xc0 + 11), "strncpy-cut-no-nul");
  check_seq(buf, 8, 0xc0, "strncpy-cut-before");

  fill_seq(buf, sizeof(buf), 0xd0);
  dst = (char *)buf + 8;
  dst[0] = 'h';
  dst[1] = 'i';
  dst[2] = '\0';
  CONTRACT_CHECK(strcat(dst, "!42") == dst, "strcat-ret");
  CONTRACT_CHECK(local_streq(dst, "hi!42"), "strcat-data");
  check_seq(buf, 8, 0xd0, "strcat-before");
  check_seq(buf + 14, 8, (uint8_t)(0xd0 + 14), "strcat-after");

  CONTRACT_CHECK(strcmp("abc", "abc") == 0, "strcmp-eq");
  CONTRACT_CHECK(strcmp("abc", "abd") < 0, "strcmp-lt");
  CONTRACT_CHECK(strcmp("abe", "abd") > 0, "strcmp-gt");
  CONTRACT_CHECK(strcmp("abc", "abcd") < 0, "strcmp-prefix-lt");
  CONTRACT_CHECK(strcmp("\xff", "\x7f") > 0, "strcmp-unsigned");
  CONTRACT_CHECK(strncmp("abc", "xyz", 0) == 0, "strncmp-zero");
  CONTRACT_CHECK(strncmp("abcdef", "abcxyz", 3) == 0, "strncmp-prefix");
  CONTRACT_CHECK(strncmp("abcdef", "abcxyz", 4) < 0, "strncmp-diff");
  CONTRACT_CHECK(strncmp("abc", "abcd", 4) < 0, "strncmp-nul-lt");
  CONTRACT_CHECK(strncmp("\xff", "\x7f", 1) > 0, "strncmp-unsigned");

  fill_seq(buf, sizeof(buf), 0x10);
  CONTRACT_CHECK(memset(buf + 8, 0x5a, 16) == buf + 8, "memset-ret");
  check_seq(buf, 8, 0x10, "memset-before");
  check_range(buf + 8, 16, 0x5a, "memset-mid");
  check_seq(buf + 24, 24, (uint8_t)(0x10 + 24), "memset-after");
  fill_seq(buf, sizeof(buf), 0x20);
  CONTRACT_CHECK(memset(buf + 4, 0x11, 0) == buf + 4, "memset-zero-ret");
  check_seq(buf, 32, 0x20, "memset-zero-data");

  fill_seq(buf, sizeof(buf), 0x30);
  fill_seq(src, sizeof(src), 0x80);
  CONTRACT_CHECK(memcpy(buf + 4, src + 9, 23) == buf + 4, "memcpy-ret");
  CONTRACT_CHECK(local_memeq(buf + 4, src + 9, 23), "memcpy-data");
  check_seq(buf, 4, 0x30, "memcpy-before");
  check_seq(buf + 27, 16, (uint8_t)(0x30 + 27), "memcpy-after");
  CONTRACT_CHECK(memcpy(buf + 1, src + 1, 0) == buf + 1, "memcpy-zero-ret");
  check_seq(buf + 27, 16, (uint8_t)(0x30 + 27), "memcpy-zero-data");

  fill_seq(buf, sizeof(buf), 0x40);
  memmove(buf + 7, buf, 32);
  for (int i = 0; i < 32; i++) CONTRACT_CHECK(buf[7 + i] == (uint8_t)(0x40 + i), "memmove-overlap-right");
  check_seq(buf + 39, 16, (uint8_t)(0x40 + 39), "memmove-right-after");

  fill_seq(buf, sizeof(buf), 0x50);
  memmove(buf, buf + 7, 32);
  for (int i = 0; i < 32; i++) CONTRACT_CHECK(buf[i] == (uint8_t)(0x50 + 7 + i), "memmove-overlap-left");
  check_seq(buf + 32, 16, (uint8_t)(0x50 + 32), "memmove-left-after");

  fill_seq(buf, sizeof(buf), 0x60);
  CONTRACT_CHECK(memmove(buf + 5, buf + 5, 20) == buf + 5, "memmove-same-ret");
  check_seq(buf, 48, 0x60, "memmove-same-data");
  CONTRACT_CHECK(memmove(buf + 3, src + 3, 0) == buf + 3, "memmove-zero-ret");
  check_seq(buf, 48, 0x60, "memmove-zero-data");

  uint8_t a0[] = {0x00, 0x7f, 0x80, 0xff};
  uint8_t a1[] = {0x00, 0x7f, 0x80, 0xff};
  uint8_t a2[] = {0x00, 0x7f, 0x81, 0x00};
  CONTRACT_CHECK(memcmp(a0, a1, 4) == 0, "memcmp-eq");
  CONTRACT_CHECK(memcmp(a0, a2, 4) < 0, "memcmp-lt");
  CONTRACT_CHECK(memcmp(a2, a0, 4) > 0, "memcmp-gt");
  CONTRACT_CHECK(memcmp(a0, a2, 0) == 0, "memcmp-zero");

  contract_pass();
}
