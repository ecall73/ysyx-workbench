#define CONTRACT_ID "04-klib-stdio"
#include <contract.h>
#include <klib.h>
#include <limits.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

static size_t local_strlen(const char *s) {
  size_t n = 0;
  while (s[n]) n++;
  return n;
}

static bool local_streq(const char *a, const char *b) {
  size_t i = 0;
  while (a[i] && b[i] && a[i] == b[i]) i++;
  return a[i] == b[i];
}

static void fill_guard(char *buf, size_t n) {
  for (size_t i = 0; i < n; i++) buf[i] = (char)0xcc;
}

static void check_vsprintf(const char *stage, const char *exp, const char *fmt, ...) {
  char buf[128];
  fill_guard(buf, sizeof(buf));

  va_list ap;
  va_start(ap, fmt);
  int ret = vsprintf(buf, fmt, ap);
  va_end(ap);

  CONTRACT_CHECK(ret == (int)local_strlen(exp), stage);
  CONTRACT_CHECK(local_streq(buf, exp), stage);
  CONTRACT_CHECK(buf[local_strlen(exp) + 1] == (char)0xcc, stage);
}

static void check_vsnprintf(const char *stage, const char *exp, size_t n, const char *fmt, ...) {
  char buf[128];
  fill_guard(buf, sizeof(buf));

  va_list ap;
  va_start(ap, fmt);
  int ret = vsnprintf(buf, n, fmt, ap);
  va_end(ap);

  CONTRACT_CHECK(ret == (int)local_strlen(exp), stage);
  if (n > 0) {
    CONTRACT_CHECK(local_streq(buf, exp), stage);
    if (n < sizeof(buf)) CONTRACT_CHECK(buf[n] == (char)0xcc, stage);
  }
}

static void check_vsnprintf_ret(const char *stage, const char *out_exp, int ret_exp,
                                size_t n, const char *fmt, ...) {
  char buf[128];
  fill_guard(buf, sizeof(buf));

  va_list ap;
  va_start(ap, fmt);
  int ret = vsnprintf(buf, n, fmt, ap);
  va_end(ap);

  CONTRACT_CHECK(ret == ret_exp, stage);
  if (n > 0) {
    CONTRACT_CHECK(local_streq(buf, out_exp), stage);
    if (n < sizeof(buf)) CONTRACT_CHECK(buf[n] == (char)0xcc, stage);
  }
}

int main(const char *args) {
  (void)args;
  contract_begin();

  int pret = printf("KLIB_PRINTF_TOKEN\n");
  CONTRACT_CHECK(pret == 18, "printf-ret");

  char buf[128];
  fill_guard(buf, sizeof(buf));
  int ret = sprintf(buf, "%d %i %u %x %X", -12345, -7, 4000000000u,
      0x1a2b3c4du, 0xfeedu);
  CONTRACT_CHECK(ret == 34, "sprintf-ret");
  CONTRACT_CHECK(local_streq(buf, "-12345 -7 4000000000 1a2b3c4d FEED"), "sprintf-basic");
  CONTRACT_CHECK(buf[ret + 1] == (char)0xcc, "sprintf-guard");

  fill_guard(buf, sizeof(buf));
  const char *long_exp = "-2147483647 -1234567890123 123456789abcdef0";
  ret = sprintf(buf, "%ld %lld %llx", (long)-2147483647L,
      -1234567890123ll, 0x123456789abcdef0ull);
  CONTRACT_CHECK(ret == (int)local_strlen(long_exp), "sprintf-long-ret");
  CONTRACT_CHECK(local_streq(buf, long_exp), "sprintf-long");

  check_vsprintf("vsprintf-basic", "ptr=0x1234abcd end", "ptr=%p %s",
      (void *)0x1234abcd, "end");

  ret = snprintf(buf, sizeof(buf), "%08d|%-5c|%q", -42, 'Z');
  CONTRACT_CHECK(ret == 17, "snprintf-ret");
  CONTRACT_CHECK(local_streq(buf, "-0000042|Z    |%q"), "snprintf-basic");

  check_vsnprintf("vsnprintf-string", "hi      |00042|%", sizeof(buf), "%-8s|%05d|%%", "hi", 42);
  check_vsnprintf("vsnprintf-char", "A 0", sizeof(buf), "%c %u", 'A', 0u);
  check_vsnprintf("vsnprintf-null", "(null)", sizeof(buf), "%s", (const char *)NULL);
  check_vsnprintf("vsnprintf-int-min", "-2147483648", sizeof(buf), "%d", (int)0x80000000u);
  check_vsnprintf_ret("vsnprintf-trunc", "-214748", 20, 8, "%d-%x",
      (int)0x80000000u, 0xffffffffu);

  ret = snprintf(NULL, 0, "%x", 0x1234u);
  CONTRACT_CHECK(ret == 4, "snprintf-null");
  check_vsnprintf_ret("vsnprintf-zero", "", 4, 0, "%x", 0x1234u);

  contract_pass();
}
