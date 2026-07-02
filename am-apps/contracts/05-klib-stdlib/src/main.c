#define CONTRACT_ID "05-klib-stdlib"
#include <contract.h>
#include <klib.h>

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(atoi("0") == 0, "atoi-zero");
  CONTRACT_CHECK(atoi("  12345xyz") == 12345, "atoi-space");
  CONTRACT_CHECK(abs(0) == 0 && abs(123) == 123 && abs(-123) == 123, "abs");

  srand(1);
  int r0 = rand();
  int r1 = rand();
  srand(1);
  CONTRACT_CHECK(rand() == r0, "rand-repeat-0");
  CONTRACT_CHECK(rand() == r1, "rand-repeat-1");
  CONTRACT_CHECK(r0 >= 0 && r0 < 32768 && r1 >= 0 && r1 < 32768, "rand-range");

  uint8_t *a = (uint8_t *)malloc(32);
  uint8_t *b = (uint8_t *)malloc(32);
  CONTRACT_CHECK(a != NULL && b != NULL && a != b, "malloc-ptr");
  for (int i = 0; i < 32; i++) {
    a[i] = (uint8_t)(0xa0 + i);
    b[i] = (uint8_t)(0xc0 + i);
  }
  for (int i = 0; i < 32; i++) {
    CONTRACT_CHECK(a[i] == (uint8_t)(0xa0 + i), "malloc-a");
    CONTRACT_CHECK(b[i] == (uint8_t)(0xc0 + i), "malloc-b");
  }
  free(a);
  free(b);

  contract_pass();
}
