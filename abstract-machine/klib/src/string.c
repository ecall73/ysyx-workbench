#include <klib.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

size_t strlen(const char *s) {
  assert(s != NULL);
  const char *a = s;
  for (; *s; s++);
  return s - a;
}

char *strcpy(char *dst, const char *src) {
  assert(dst != NULL && src != NULL);
  char *tmp = dst;
  for (; (*dst = *src); src++, dst++);
  return tmp;
}

char *strncpy(char *dst, const char *src, size_t n) {
  assert(dst != NULL && src != NULL);
  char *tmp = dst;
  for (; n && (*dst = *src); n--, src++, dst++);
  while (n--) *dst++ = '\0';
  return tmp;
}

char *strcat(char *dst, const char *src) {
  assert(dst != NULL && src != NULL);
  strcpy(dst + strlen(dst), src);
  return dst;
}

int strcmp(const char *s1, const char *s2) {
  assert(s1 != NULL && s2 != NULL);
  while (*s1 && *s1 == *s2) {
    s1++;
    s2++;
  }
  return *(unsigned char *)s1 - *(unsigned char *)s2;
}

int strncmp(const char *s1, const char *s2, size_t n) {
  assert(s1 != NULL && s2 != NULL);
  while (n && *s1 && *s1 == *s2) {
    s1++;
    s2++;
    n--;
  }
  return n ? *(unsigned char *)s1 - *(unsigned char *)s2 : 0;
}

void *memset(void *s, int c, size_t n) {
  assert(s != NULL || n == 0);
  unsigned char *p = s;
  while (n--) *p++ = (unsigned char)c;
  return s;
}

void *memmove(void *dst, const void *src, size_t n) {
  assert((dst != NULL && src != NULL) || n == 0);
  if (n == 0) return dst;
  unsigned char *d = dst;
  const unsigned char *s = src;
  if (d == s) return dst;
  if (d < s) {
    while (n--) *d++ = *s++;
  } else {
    d += n;
    s += n;
    while (n--) *--d = *--s;
  }
  return dst;
}

void *memcpy(void *dst, const void *src, size_t n) {
  assert((dst != NULL && src != NULL) || n == 0);
  unsigned char *d = dst;
  const unsigned char *s = src;
  while (n--) *d++ = *s++;
  return dst;
}

int memcmp(const void *s1, const void *s2, size_t n) {
  assert((s1 != NULL && s2 != NULL) || n == 0);
  const unsigned char *p1 = s1;
  const unsigned char *p2 = s2;
  while (n--) {
    if (*p1 != *p2) return *p1 - *p2;
    p1++;
    p2++;
  }
  return 0;
}

#endif
