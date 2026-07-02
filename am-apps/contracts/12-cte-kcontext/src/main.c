#define CONTRACT_ID "12-cte-kcontext"
#include <contract.h>

static uint8_t child_stack[4096] __attribute__((aligned(16)));
static Context *main_ctx = NULL;
static Context *child_ctx = NULL;
static volatile int phase = 0;
static volatile int child_seen = 0;

static void child_entry(void *arg) {
  CONTRACT_CHECK((uintptr_t)arg == 0x13572468u, "child-arg");
  child_seen = 1;
  phase = 2;
  yield();
  contract_fail("child-resume");
}

static Context *handler(Event ev, Context *ctx) {
  CONTRACT_CHECK(ev.event == EVENT_YIELD, "event-yield");

  if (phase == 0) {
    main_ctx = ctx;
    phase = 1;
    return child_ctx;
  }

  if (phase == 2) {
    phase = 3;
    return main_ctx;
  }

  contract_fail("unexpected-yield");
}

int main(const char *args) {
  (void)args;
  contract_begin();

  Area stack = {
    .start = child_stack,
    .end = child_stack + sizeof(child_stack),
  };
  child_ctx = kcontext(stack, child_entry, (void *)0x13572468u);
  CONTRACT_CHECK(child_ctx != NULL, "kcontext");
  CONTRACT_CHECK(cte_init(handler), "cte-init");

  yield();
  CONTRACT_CHECK(phase == 3, "main-return");
  CONTRACT_CHECK(child_seen == 1, "child-seen");
  contract_pass();
}
