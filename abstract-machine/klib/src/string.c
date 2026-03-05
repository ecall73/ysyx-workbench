#include <klib.h>
#include <klib-macros.h>
#include <stdint.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

size_t strlen(const char *s) {
  const char *a = s;
  for (; *s; s++);
  return s - a + 1;
}

char *strcpy(char *dst, const char *src) {
  char *tmp = dst;
  for (; (*dst = *src); src++, dst++);
  return tmp;
}

char *strncpy(char *dst, const char *src, size_t n) {
  char *tmp = dst;
  for (; n && (*dst = *src); n--, src++, dst++);
  memset(dst, 0, n);
  return tmp;
}

char *strcat(char *dst, const char *src) {
  char *tmp = dst;
  for (; *dst; dst++);
  for (; (*dst = *src); src++, dst++);
  return tmp;
}

int strcmp(const char *s1, const char *s2) {
  for (; *s1 == *s2; s1++, s2++) {
    if (!*s1) return 0;
  }
  return (*s1 - *s2);
}

int strncmp(const char *s1, const char *s2, size_t n) {
  for (; n && *s1 == *s2; n--, s1++, s2++) {
    if (!*s1) return 0;
  }
  return (n == 0) ? 0 : (*s1 - *s2);
}

void *memset(void *s, int c, size_t n) {
  uint8_t *p = s;
  for (; n; n--, p++) *p = c;
  return s;
}

void *memmove(void *dst, const void *src, size_t n) {
  uint8_t *d = dst;
  const uint8_t *s = src;
  if (d < s) {
    for (; n; n--, d++, s++) *d = *s;
  } else {
    for (d += n, s += n; n; n--, d--, s--) *d = *s;
  }
  return dst;
}

void *memcpy(void *out, const void *in, size_t n) {
  uint8_t *d = out;
  const uint8_t *s = in;
  for (; n; n--, d++, s++) *d = *s;
  return out;
}

int memcmp(const void *s1, const void *s2, size_t n) {
  const uint8_t *a = s1;
  const uint8_t *b = s2;
  for (; n; n--, a++, b++) {
    if (*a != *b) return *a - *b;
  }
  return 0;
}

#endif
