#include <am.h>
#include <klib.h>
#include <stdarg.h>
#include <stdio.h>
#include <limits.h>
#include <stddef.h>
#include <stdint.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

typedef struct {
  char *buf;
  size_t cap;
  size_t len;
} Output;

static void out_char(Output *out, char ch) {
  if (out->buf == NULL) {
    putch(ch);
  } else if (out->len + 1 < out->cap) {
    out->buf[out->len] = ch;
  }
  out->len++;
}

static void out_repeat(Output *out, char ch, int count) {
  while (count-- > 0) {
    out_char(out, ch);
  }
}

static unsigned long long read_unsigned(va_list *ap, int long_level) {
  if (long_level >= 2) return va_arg(*ap, unsigned long long);
  if (long_level == 1) return va_arg(*ap, unsigned long);
  return va_arg(*ap, unsigned int);
}

static unsigned long long read_signed_abs(va_list *ap, int long_level, char *sign) {
  long long val;
  if (long_level >= 2) val = va_arg(*ap, long long);
  else if (long_level == 1) val = va_arg(*ap, long);
  else val = va_arg(*ap, int);

  if (val < 0) {
    *sign = '-';
    return (unsigned long long)(-(val + 1)) + 1;
  }
  *sign = 0;
  return (unsigned long long)val;
}

static int convert_number(char *buf, unsigned long long val, int base, bool upper) {
  int len = 0;
  const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";

  if (val == 0) {
    buf[len++] = '0';
  } else {
    while (val > 0) {
      buf[len++] = digits[val % (unsigned)base];
      val /= (unsigned)base;
    }
  }
  return len;
}

static void out_string(Output *out, const char *s, int width, bool left_align) {
  int len = (int)strlen(s);
  int pad = width > len ? width - len : 0;

  if (!left_align) out_repeat(out, ' ', pad);
  while (*s != '\0') out_char(out, *s++);
  if (left_align) out_repeat(out, ' ', pad);
}

static void out_number(Output *out, unsigned long long val, int base, bool upper,
    char sign, const char *prefix, int width, bool left_align, bool zero_pad) {
  char buf[64];
  int len = convert_number(buf, val, base, upper);
  int prefix_len = (int)strlen(prefix);
  int body_len = len + prefix_len + (sign ? 1 : 0);
  int pad = width > body_len ? width - body_len : 0;
  char pad_ch = zero_pad && !left_align ? '0' : ' ';

  if (!left_align && pad_ch == ' ') out_repeat(out, ' ', pad);
  if (sign) out_char(out, sign);
  while (*prefix != '\0') out_char(out, *prefix++);
  if (!left_align && pad_ch == '0') out_repeat(out, '0', pad);
  while (len > 0) out_char(out, buf[--len]);
  if (left_align) out_repeat(out, ' ', pad);
}

static int format(Output *out, const char *fmt, va_list ap) {
  for (const char *p = fmt; *p != '\0'; p++) {
    if (*p != '%') {
      out_char(out, *p);
      continue;
    }

    p++;
    if (*p == '\0') break;

    bool left_align = false;
    bool zero_pad = false;
    int width = 0;
    int long_level = 0;

    while (*p == '-' || *p == '0') {
      if (*p == '-') left_align = true;
      if (*p == '0') zero_pad = true;
      p++;
    }
    if (left_align) zero_pad = false;

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

    switch (spec) {
      case '%':
        out_char(out, '%');
        break;
      case 'c': {
        char ch = (char)va_arg(ap, int);
        int pad = width > 1 ? width - 1 : 0;
        if (!left_align) out_repeat(out, ' ', pad);
        out_char(out, ch);
        if (left_align) out_repeat(out, ' ', pad);
        break;
      }
      case 's': {
        const char *s = va_arg(ap, const char *);
        out_string(out, s != NULL ? s : "(null)", width, left_align);
        break;
      }
      case 'd':
      case 'i': {
        char sign;
        unsigned long long val = read_signed_abs(&ap, long_level, &sign);
        out_number(out, val, 10, false, sign, "", width, left_align, zero_pad);
        break;
      }
      case 'u': {
        unsigned long long val = read_unsigned(&ap, long_level);
        out_number(out, val, 10, false, 0, "", width, left_align, zero_pad);
        break;
      }
      case 'x':
      case 'X': {
        unsigned long long val = read_unsigned(&ap, long_level);
        out_number(out, val, 16, spec == 'X', 0, "", width, left_align, zero_pad);
        break;
      }
      case 'p': {
        unsigned long long val = (uintptr_t)va_arg(ap, void *);
        out_number(out, val, 16, false, 0, "0x", width, left_align, zero_pad);
        break;
      }
      default:
        out_char(out, '%');
        out_char(out, spec);
        break;
    }
  }

  if (out->buf != NULL && out->cap > 0) {
    size_t pos = out->len < out->cap - 1 ? out->len : out->cap - 1;
    out->buf[pos] = '\0';
  }

  return (int)out->len;
}

int vfprintf(FILE *stream, const char *fmt, va_list ap) {
  (void)stream;
  Output out = { .buf = NULL, .cap = 0, .len = 0 };
  return format(&out, fmt, ap);
}

int printf(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vfprintf(NULL, fmt, ap);
  va_end(ap);
  return ret;
}

int vsnprintf(char *s, size_t n, const char *fmt, va_list ap) {
  Output out = { .buf = s, .cap = n, .len = 0 };
  return format(&out, fmt, ap);
}

int snprintf(char *s, size_t n, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vsnprintf(s, n, fmt, ap);
  va_end(ap);
  return ret;
}

int vsprintf(char *s, const char *fmt, va_list ap) {
  return vsnprintf(s, INT_MAX, fmt, ap);
}

int sprintf(char *s, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  int ret = vsprintf(s, fmt, ap);
  va_end(ap);
  return ret;
}

#endif
