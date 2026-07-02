#include <contract.h>

static bool streq(const char *a, const char *b) {
  while (*a && *b && *a == *b) {
    a++;
    b++;
  }
  return *a == *b;
}

int main(const char *args) {
  contract_begin();

  CONTRACT_CHECK(args != NULL, "args-nonnull");
  CONTRACT_CHECK(streq(args, EXPECT_MAINARGS), "args-match");
  contract_pass();
}
