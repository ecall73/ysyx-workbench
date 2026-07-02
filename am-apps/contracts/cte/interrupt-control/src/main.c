#include <contract.h>

static Context *handler(Event ev, Context *ctx) {
  CONTRACT_CHECK(ev.event == EVENT_YIELD, "event-yield");
  return ctx;
}

int main(const char *args) {
  (void)args;
  contract_begin();

  CONTRACT_CHECK(cte_init(handler), "cte-init");
  iset(false);
  CONTRACT_CHECK(!ienabled(), "disabled");
  yield();
  iset(true);
  CONTRACT_CHECK(!ienabled(), "enabled-current-semantics");
  yield();
  iset(false);
  CONTRACT_CHECK(!ienabled(), "disabled-again");

  contract_pass();
}
