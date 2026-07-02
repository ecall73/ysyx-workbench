#define CONTRACT_ID "05-klib-stdlib"
#include <contract.h>
#include <klib.h>

static bool range_overlap(const uint8_t *a, size_t an, const uint8_t *b, size_t bn) {
  uintptr_t al = (uintptr_t)a;
  uintptr_t ar = al + an;
  uintptr_t bl = (uintptr_t)b;
  uintptr_t br = bl + bn;
  return al < br && bl < ar;
}

static void fill_block(uint8_t *p, size_t n, uint8_t seed) {
  for (size_t i = 0; i < n; i++) p[i] = (uint8_t)(seed + i);
}

static void check_block(const uint8_t *p, size_t n, uint8_t seed, const char *stage) {
  for (size_t i = 0; i < n; i++) CONTRACT_CHECK(p[i] == (uint8_t)(seed + i), stage);
}

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(atoi("0") == 0, "atoi-zero");
  CONTRACT_CHECK(atoi("") == 0, "atoi-empty");
  CONTRACT_CHECK(atoi("abc") == 0, "atoi-no-digit");
  CONTRACT_CHECK(atoi("0012") == 12, "atoi-leading-zero");
  CONTRACT_CHECK(atoi("  12345xyz") == 12345, "atoi-space");
  CONTRACT_CHECK(atoi("77 88") == 77, "atoi-stop-space");
  CONTRACT_CHECK(abs(0) == 0 && abs(123) == 123 && abs(-123) == 123, "abs");

  srand(1);
  int r0 = rand();
  int r1 = rand();
  int r2 = rand();
  srand(1);
  CONTRACT_CHECK(rand() == r0, "rand-repeat-0");
  CONTRACT_CHECK(rand() == r1, "rand-repeat-1");
  CONTRACT_CHECK(rand() == r2, "rand-repeat-2");
  CONTRACT_CHECK(r0 != r1 || r1 != r2, "rand-advance");
  CONTRACT_CHECK(r0 >= 0 && r0 < 32768 && r1 >= 0 && r1 < 32768 && r2 >= 0 && r2 < 32768, "rand-range");

  uint8_t *a = (uint8_t *)malloc(16);
  uint8_t *b = (uint8_t *)malloc(24);
  uint8_t *c = (uint8_t *)malloc(1);
  uint8_t *d = (uint8_t *)malloc(40);
  CONTRACT_CHECK(a != NULL && b != NULL && c != NULL && d != NULL, "malloc-nonnull");
  CONTRACT_CHECK(!range_overlap(a, 16, b, 24), "malloc-ab-overlap");
  CONTRACT_CHECK(!range_overlap(a, 16, c, 1), "malloc-ac-overlap");
  CONTRACT_CHECK(!range_overlap(a, 16, d, 40), "malloc-ad-overlap");
  CONTRACT_CHECK(!range_overlap(b, 24, c, 1), "malloc-bc-overlap");
  CONTRACT_CHECK(!range_overlap(b, 24, d, 40), "malloc-bd-overlap");
  CONTRACT_CHECK(!range_overlap(c, 1, d, 40), "malloc-cd-overlap");

  fill_block(a, 16, 0xa0);
  fill_block(b, 24, 0xb0);
  fill_block(c, 1, 0xc0);
  fill_block(d, 40, 0xd0);
  check_block(a, 16, 0xa0, "malloc-a");
  check_block(b, 24, 0xb0, "malloc-b");
  check_block(c, 1, 0xc0, "malloc-c");
  check_block(d, 40, 0xd0, "malloc-d");

  free(a);
  free(b);
  check_block(c, 1, 0xc0, "free-live-c");
  check_block(d, 40, 0xd0, "free-live-d");

  uint8_t *e = (uint8_t *)malloc(8);
  CONTRACT_CHECK(e != NULL, "malloc-after-free");
  CONTRACT_CHECK(!range_overlap(e, 8, c, 1), "malloc-e-c-overlap");
  CONTRACT_CHECK(!range_overlap(e, 8, d, 40), "malloc-e-d-overlap");
  fill_block(e, 8, 0xe0);
  check_block(c, 1, 0xc0, "malloc-e-live-c");
  check_block(d, 40, 0xd0, "malloc-e-live-d");
  check_block(e, 8, 0xe0, "malloc-e");
  free(c);
  free(d);
  free(e);

  contract_pass();
}
