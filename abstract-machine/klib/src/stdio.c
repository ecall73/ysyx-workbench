#include <am.h>
#include <klib.h>
#include <stdarg.h>
#include <stdio.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

int vsnprintf(char *out, size_t n, const char *fmt, va_list ap) {
  size_t len = 0;

#define PUTC(ch) do { \
  if (out != NULL && len + 1 < n) out[len] = (ch); \
  len++; \
} while (0)

#define PUTS(s) do { \
  const char *__s = (s); \
  while (*__s != '\0') PUTC(*__s++); \
} while (0)

#define PAD(ch, cnt) do { \
  for (int __i = 0; __i < (cnt); __i++) PUTC(ch); \
} while (0)

  for (const char *p = fmt; *p != '\0'; p++) {
    if (*p != '%') {
      PUTC(*p);
      continue;
    }

    p++;
    if (*p == '\0') break;

    int left_align = 0;
    int zero_pad = 0;
    int width = 0;
    int long_level = 0;

    while (*p == '-' || *p == '0') {
      if (*p == '-') left_align = 1;
      if (*p == '0') zero_pad = 1;
      p++;
    }
    if (left_align) zero_pad = 0;

    while (*p >= '0' && *p <= '9') {
      width = width * 10 + (*p - '0');
      p++;
    }

    if (*p == '.') {
      p++;
      while (*p >= '0' && *p <= '9') p++;
    }

    while (*p == 'l') {
      long_level++;
      p++;
    }

    char spec = *p;
    if (spec == '\0') break;

    if (spec == '%') {
      PUTC('%');
      continue;
    }

    if (spec == 'c') {
      char ch = (char)va_arg(ap, int);
      int pad = width > 1 ? width - 1 : 0;
      if (!left_align) PAD(' ', pad);
      PUTC(ch);
      if (left_align) PAD(' ', pad);
      continue;
    }

    if (spec == 's') {
      const char *s = va_arg(ap, const char *);
      if (s == NULL) s = "(null)";
      int slen = (int)strlen(s);
      int pad = width > slen ? width - slen : 0;
      if (!left_align) PAD(' ', pad);
      PUTS(s);
      if (left_align) PAD(' ', pad);
      continue;
    }

    char numbuf[64];
    int ndig = 0;
    int base = 10;
    int upper = 0;
    char sign = 0;
    const char *prefix = "";
    unsigned long long val = 0;

    if (spec == 'd' || spec == 'i') {
      long long x;
      if (long_level >= 2) x = va_arg(ap, long long);
      else if (long_level == 1) x = va_arg(ap, long);
      else x = va_arg(ap, int);

      if (x < 0) {
        sign = '-';
        val = (unsigned long long)(-(x + 1)) + 1;
      } else {
        val = (unsigned long long)x;
      }
    } else if (spec == 'u' || spec == 'x' || spec == 'X') {
      if (long_level >= 2) val = va_arg(ap, unsigned long long);
      else if (long_level == 1) val = va_arg(ap, unsigned long);
      else val = va_arg(ap, unsigned int);
      if (spec == 'x' || spec == 'X') {
        base = 16;
        upper = spec == 'X';
      }
    } else if (spec == 'p') {
      val = (uintptr_t)va_arg(ap, void *);
      base = 16;
      prefix = "0x";
    } else {
      PUTC('%');
      PUTC(spec);
      continue;
    }

    if (val == 0) {
      numbuf[ndig++] = '0';
    } else {
      const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
      while (val > 0) {
        numbuf[ndig++] = digits[val % (unsigned)base];
        val /= (unsigned)base;
      }
    }

    int prefix_len = (int)strlen(prefix);
    int body_len = ndig + prefix_len + (sign ? 1 : 0);
    int pad = width > body_len ? width - body_len : 0;
    char pad_ch = zero_pad && !left_align ? '0' : ' ';

    if (!left_align && pad_ch == ' ') PAD(' ', pad);
    if (sign) PUTC(sign);
    PUTS(prefix);
    if (!left_align && pad_ch == '0') PAD('0', pad);
    while (ndig > 0) PUTC(numbuf[--ndig]);
    if (left_align) PAD(' ', pad);
  }

  if (out != NULL && n > 0) {
    size_t pos = len < n - 1 ? len : n - 1;
    out[pos] = '\0';
  }

#undef PAD
#undef PUTS
#undef PUTC

  return (int)len;
}

int snprintf(char *out, size_t n, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vsnprintf(out, n, fmt, ap);
  va_end(ap);
  return ret;
}

int vsprintf(char *out, const char *fmt, va_list ap) {
  return vsnprintf(out, INT_MAX, fmt, ap);
}

int sprintf(char *out, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vsprintf(out, fmt, ap);
  va_end(ap);
  return ret;
}

int vfprintf(FILE *stream, const char *fmt, va_list ap) {
  (void)stream;
  char buf[1024];
  int ret = vsnprintf(buf, sizeof(buf), fmt, ap);
  for (int i = 0; buf[i] != '\0'; i++) {
    putch(buf[i]);
  }
  return ret;
}

int printf(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vfprintf(NULL, fmt, ap);
  va_end(ap);
  return ret;
}

#endif
