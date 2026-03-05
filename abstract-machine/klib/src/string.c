#include <klib.h>
#include <klib-macros.h>
#include <stdint.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

size_t strlen(const char *s) {
  const char *a = s;
  for (; *s; s++);
  return s - a;
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
  strcpy(dst + strlen(dst), src);
	return dst;
}

int strcmp(const char *s1, const char *s2) {
  for (; *s1==*s2 && *s1; s1++, s2++);
  return *(unsigned char *)s1 - *(unsigned char *)s2;
}

int strncmp(const char *s1, const char *s2, size_t n) {
  const unsigned char *l=(void *)s1, *r=(void *)s2;
	if (!n--) return 0;
	for (; *l && *r && n && *l == *r ; l++, r++, n--);
	return *l - *r;
}

void *memset(void *s, int c, size_t n) {

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
