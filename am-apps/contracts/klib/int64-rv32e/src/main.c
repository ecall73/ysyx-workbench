#include <contract.h>

int main(const char *args) {
  (void)args;
  contract_begin();

  volatile uint64_t a = 0x123456789abcdef0ull;
  volatile uint64_t b = 0x12345ull;
  uint64_t q = a / b;
  uint64_t r = a % b;
  CONTRACT_CHECK(q == 0x100005b00205ull, "udiv64");
  CONTRACT_CHECK(r == 0xa497ull, "umod64");

  volatile int64_t s = -1234567890123ll;
  volatile int64_t d = 321ll;
  CONTRACT_CHECK(s / d == -3846005888ll, "sdiv64");
  CONTRACT_CHECK(s % d == -75ll, "smod64");

  volatile uint64_t m0 = 0x12345678abcdef01ull;
  volatile uint64_t m1 = 0x100000001ull;
  CONTRACT_CHECK((m0 * m1) == 0xbe024579abcdef01ull, "umul64");
  CONTRACT_CHECK((m0 << 13) == 0x8acf1579bde02000ull, "shl64");
  CONTRACT_CHECK((m0 >> 17) == 0x0000091a2b3c55e6ull, "shr64");

  contract_pass();
}
