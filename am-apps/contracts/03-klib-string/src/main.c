#define CONTRACT_ID "03-klib-string"
#include <contract.h>
#include <klib.h>

static uint8_t buf[64];
static uint8_t src[64];

static void fill_seq(uint8_t *p, int n, uint8_t seed) {
  for (int i = 0; i < n; i++) p[i] = (uint8_t)(seed + i);
}

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(strlen("") == 0, "strlen-empty");
  CONTRACT_CHECK(strlen("abcdef") == 6, "strlen");
  CONTRACT_CHECK(strcmp("abc", "abc") == 0, "strcmp-eq");
  CONTRACT_CHECK(strcmp("abc", "abd") < 0, "strcmp-lt");
  CONTRACT_CHECK(strcmp("abe", "abd") > 0, "strcmp-gt");
  CONTRACT_CHECK(strncmp("abcdef", "abcxyz", 3) == 0, "strncmp-prefix");
  CONTRACT_CHECK(strncmp("abcdef", "abcxyz", 4) < 0, "strncmp-diff");

  fill_seq(buf, 64, 0x10);
  CONTRACT_CHECK(memset(buf + 8, 0x5a, 16) == buf + 8, "memset-ret");
  for (int i = 0; i < 8; i++) CONTRACT_CHECK(buf[i] == (uint8_t)(0x10 + i), "memset-before");
  for (int i = 8; i < 24; i++) CONTRACT_CHECK(buf[i] == 0x5a, "memset-mid");
  for (int i = 24; i < 64; i++) CONTRACT_CHECK(buf[i] == (uint8_t)(0x10 + i), "memset-after");

  fill_seq(src, 64, 0x80);
  CONTRACT_CHECK(memcpy(buf + 4, src + 9, 23) == buf + 4, "memcpy-ret");
  CONTRACT_CHECK(memcmp(buf + 4, src + 9, 23) == 0, "memcpy-data");

  fill_seq(buf, 64, 0x20);
  memmove(buf + 7, buf, 32);
  for (int i = 0; i < 32; i++) CONTRACT_CHECK(buf[7 + i] == (uint8_t)(0x20 + i), "memmove-forward");

  fill_seq(buf, 64, 0x40);
  memmove(buf, buf + 7, 32);
  for (int i = 0; i < 32; i++) CONTRACT_CHECK(buf[i] == (uint8_t)(0x40 + 7 + i), "memmove-backward");

  contract_pass();
}
