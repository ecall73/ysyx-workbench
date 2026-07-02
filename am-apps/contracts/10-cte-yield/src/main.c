#define CONTRACT_ID "10-cte-yield"
#include <contract.h>

static volatile int yield_count = 0;

static Context *handler(Event ev, Context *ctx) {
  CONTRACT_CHECK(ev.event == EVENT_YIELD, "event-yield");
  yield_count++;
  return ctx;
}

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(cte_init(handler), "cte-init");
  yield();
  CONTRACT_CHECK(yield_count == 1, "yield-return");
  contract_pass();
}
