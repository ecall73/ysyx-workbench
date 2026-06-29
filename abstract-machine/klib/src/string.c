#include <klib.h>

#if !defined(__ISA_NATIVE__) || defined(__NATIVE_USE_KLIB__)

size_t strlen(const char *s) {
  size_t n = 0;
  while (s[n] != '\0') {
    n++;
  }
  return n;
}

char *strcpy(char *dst, const char *src) {
  char *ret = dst;
  while ((*dst = *src) != '\0') {
    dst++;
    src++;
  }
  return ret;
}

char *strncpy(char *dst, const char *src, size_t n) {
  char *ret = dst;
  while (n > 0 && *src != '\0') {
    *dst++ = *src++;
    n--;
  }
  while (n > 0) {
    *dst++ = '\0';
    n--;
  }
  return ret;
}

char *strcat(char *dst, const char *src) {
  strcpy(dst + strlen(dst), src);
  return dst;
}

int strcmp(const char *s1, const char *s2) {
  while (*s1 && *s1 == *s2) {
    s1++;
    s2++;
  }
  return *(unsigned char *)s1 - *(unsigned char *)s2;
}

int strncmp(const char *s1, const char *s2, size_t n) {
  while (n && *s1 && *s1 == *s2) {
    s1++;
    s2++;
    n--;
  }
  return n ? *(unsigned char *)s1 - *(unsigned char *)s2 : 0;
}

void *memset(void *s, int c, size_t n) {
  unsigned char *p = s;
  while (n > 0) {
    *p++ = (unsigned char)c;
    n--;
  }
  return s;
}

void *memcpy(void *dst, const void *src, size_t n) {
  unsigned char *d = dst;
  const unsigned char *s = src;
  while (n > 0) {
    *d++ = *s++;
    n--;
  }
  return dst;
}

void *memmove(void *dst, const void *src, size_t n) {
  unsigned char *d = dst;
  const unsigned char *s = src;

  if (d == s) return dst;

  if (d < s) {
    while (n > 0) {
      *d++ = *s++;
      n--;
    }
  } else {
    d += n;
    s += n;
    while (n > 0) {
      *--d = *--s;
      n--;
    }
  }
  return dst;
}

int memcmp(const void *s1, const void *s2, size_t n) {
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
