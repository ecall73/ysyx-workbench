#include <am.h>
#include <klib.h>
#include <stdint.h>

#define N 32

static uint8_t data[N];
static uint8_t src_data[N];
static uint8_t model[N];

static void reset_seq(uint8_t *buf) {
  for (int i = 0; i < N; i++) {
    buf[i] = (uint8_t)(i + 1);
  }
}

static void copy_buf(uint8_t *dst, const uint8_t *src) {
  for (int i = 0; i < N; i++) {
    dst[i] = src[i];
  }
}

static void check_seq(const uint8_t *buf, int l, int r, int val) {
  for (int i = l; i < r; i++) {
    assert(buf[i] == (uint8_t)(val + i - l));
  }
}

static void check_eq(const uint8_t *buf, int l, int r, uint8_t val) {
  for (int i = l; i < r; i++) {
    assert(buf[i] == val);
  }
}

static void check_same(const uint8_t *a, const uint8_t *b) {
  for (int i = 0; i < N; i++) {
    assert(a[i] == b[i]);
  }
}

static void make_ascii_string(char *dst, int len, int seed) {
  for (int i = 0; i < len; i++) {
    dst[i] = (char)('a' + (seed + i) % 26);
  }
  dst[len] = '\0';
}

static void test_memset(void) {
  for (int l = 0; l <= N; l++) {
    for (int r = l; r <= N; r++) {
      reset_seq(data);
      uint8_t val = (uint8_t)((l * 7 + r * 11) & 0xff);
      void *ret = memset(data + l, val, (size_t)(r - l));
      assert(ret == data + l);
      check_seq(data, 0, l, 1);
      check_eq(data, l, r, val);
      check_seq(data, r, N, r + 1);
    }
  }
}

static void test_memcpy(void) {
  for (int dl = 0; dl <= N; dl++) {
    for (int sl = 0; sl <= N; sl++) {
      int max_len = N - (dl > sl ? dl : sl);
      for (int len = 0; len <= max_len; len++) {
        reset_seq(data);
        reset_seq(src_data);
        copy_buf(model, data);
        for (int i = 0; i < len; i++) {
          model[dl + i] = src_data[sl + i];
        }

        void *ret = memcpy(data + dl, src_data + sl, (size_t)len);
        assert(ret == data + dl);
        check_same(data, model);
        check_seq(src_data, 0, N, 1);
      }
    }
  }
}

static void test_memmove(void) {
  for (int dl = 0; dl <= N; dl++) {
    for (int sl = 0; sl <= N; sl++) {
      int max_len = N - (dl > sl ? dl : sl);
      for (int len = 0; len <= max_len; len++) {
        reset_seq(data);
        copy_buf(model, data);

        if (dl <= sl) {
          for (int i = 0; i < len; i++) {
            model[dl + i] = model[sl + i];
          }
        } else {
          for (int i = len - 1; i >= 0; i--) {
            model[dl + i] = model[sl + i];
          }
        }

        void *ret = memmove(data + dl, data + sl, (size_t)len);
        assert(ret == data + dl);
        check_same(data, model);
      }
    }
  }
}

static void test_strcpy(void) {
  char src[N + 1];

  for (int l = 0; l < N; l++) {
    for (int len = 0; l + len < N; len++) {
      reset_seq(data);
      make_ascii_string(src, len, l);

      char *ret = strcpy((char *)data + l, src);
      assert(ret == (char *)data + l);
      check_seq(data, 0, l, 1);
      for (int i = 0; i < len; i++) {
        assert(data[l + i] == (uint8_t)src[i]);
      }
      assert(data[l + len] == 0);
      check_seq(data, l + len + 1, N, l + len + 2);
    }
  }
}

static void test_strncpy(void) {
  char src[N + 1];

  for (int l = 0; l <= N; l++) {
    for (int src_len = 0; src_len < N; src_len++) {
      make_ascii_string(src, src_len, l + 3);
      for (int n = 0; l + n <= N; n++) {
        reset_seq(data);

        copy_buf(model, data);
        int cpy = (src_len < n ? src_len : n);
        for (int i = 0; i < cpy; i++) {
          model[l + i] = (uint8_t)src[i];
        }
        for (int i = cpy; i < n; i++) {
          model[l + i] = 0;
        }

        char *ret = strncpy((char *)data + l, src, (size_t)n);
        assert(ret == (char *)data + l);
        check_same(data, model);
      }
    }
  }
}

static void test_strcat(void) {
  char src[N + 1];

  for (int l = 0; l < N; l++) {
    for (int dst_len = 0; l + dst_len < N; dst_len++) {
      for (int src_len = 0; l + dst_len + src_len < N; src_len++) {
        reset_seq(data);
        make_ascii_string((char *)data + l, dst_len, src_len + 5);
        make_ascii_string(src, src_len, l + 7);

        char *ret = strcat((char *)data + l, src);
        assert(ret == (char *)data + l);

        check_seq(data, 0, l, 1);
        for (int i = 0; i < dst_len; i++) {
          assert(data[l + i] == (uint8_t)('a' + (src_len + 5 + i) % 26));
        }
        for (int i = 0; i < src_len; i++) {
          assert(data[l + dst_len + i] == (uint8_t)src[i]);
        }
        assert(data[l + dst_len + src_len] == 0);
        check_seq(data, l + dst_len + src_len + 1, N, l + dst_len + src_len + 2);
      }
    }
  }
}

int main(const char *args) {
  (void)args;

  test_memset();
  printf("[klib-tests] memset OK\n");

  test_memcpy();
  printf("[klib-tests] memcpy OK\n");

  test_memmove();
  printf("[klib-tests] memmove OK\n");

  test_strcpy();
  printf("[klib-tests] strcpy OK\n");

  test_strncpy();
  printf("[klib-tests] strncpy OK\n");

  test_strcat();
  printf("[klib-tests] strcat OK\n");

  printf("[klib-tests] all write-function tests passed\n");
  return 0;
}
