#define CONTRACT_ID "04-klib-format"
#include <contract.h>
#include <klib.h>
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

static void check_vsn(const char *stage, const char *exp, size_t n, const char *fmt, ...) {
  char buf[96];
  for (int i = 0; i < 96; i++) buf[i] = (char)0xcc;

  va_list ap;
  va_start(ap, fmt);
  int ret = vsnprintf(buf, n, fmt, ap);
  va_end(ap);

  CONTRACT_CHECK(ret == (int)local_strlen(exp), stage);
  if (n > 0) CONTRACT_CHECK(local_streq(buf, exp), stage);
}

static void check_vsn_ret(const char *stage, const char *out_exp, int ret_exp,
                          size_t n, const char *fmt, ...) {
  char buf[96];
  for (int i = 0; i < 96; i++) buf[i] = (char)0xcc;

  va_list ap;
  va_start(ap, fmt);
  int ret = vsnprintf(buf, n, fmt, ap);
  va_end(ap);

  CONTRACT_CHECK(ret == ret_exp, stage);
  if (n > 0) CONTRACT_CHECK(local_streq(buf, out_exp), stage);
}

int main(const char *args) {
  (void)args;
  contract_begin();

  char buf[96];
  int ret = sprintf(buf, "%d %u %x", -12345, 4000000000u, 0x1a2b3c4du);
  CONTRACT_CHECK(ret == 26, "sprintf-ret");
  CONTRACT_CHECK(local_streq(buf, "-12345 4000000000 1a2b3c4d"), "sprintf-basic");

  check_vsn("vsn-string", "hi      |00042|%", sizeof(buf), "%-8s|%05d|%%", "hi", 42);
  check_vsn("vsn-char", "A 0", sizeof(buf), "%c %u", 'A', 0u);
  check_vsn("vsn-null", "(null)", sizeof(buf), "%s", (const char *)NULL);
  check_vsn_ret("vsn-trunc", "-214748", 20, 8, "%d-%x",
      (int)0x80000000u, 0xffffffffu);

  ret = snprintf(NULL, 0, "%x", 0x1234u);
  CONTRACT_CHECK(ret == 4, "snprintf-null");

  contract_pass();
}
