#include <contract.h>
#include <klib-macros.h>

static void spin(unsigned n) {
  for (volatile unsigned i = 0; i < n; i++) {
  }
}

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(ioe_init(), "ioe-init");
  uint64_t first = io_read(AM_TIMER_UPTIME).us;
  uint64_t last = first;
  bool grew = false;

  for (int i = 0; i < 256; i++) {
    spin(10000u);
    uint64_t now = io_read(AM_TIMER_UPTIME).us;
    CONTRACT_CHECK(now >= last, "uptime-monotonic");
    if (now > first) grew = true;
    last = now;
  }

  CONTRACT_CHECK(grew, "uptime-growth");
  contract_pass();
}
