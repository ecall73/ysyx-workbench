#include <proc.h>

#define MAX_NR_PROC 4

static PCB pcb[MAX_NR_PROC] __attribute__((used)) = {};
static PCB pcb_boot = {};
PCB *current = NULL;

void switch_boot_pcb() {
  current = &pcb_boot;
}

static void context_kload(PCB *pcb, void (*entry)(void *), void *arg) {
  pcb->cp = kcontext(RANGE(pcb->stack, pcb->stack + STACK_SIZE), entry, arg);
}

void hello_fun(void *arg) {
  int j = 1;
  while (1) {
    Log("Hello World from Nanos-lite with arg '%s' for the %dth time!", (char *)arg, j);
    j ++;
    yield();
  }
}

void init_proc() {
  Log("Initializing processes...");

  context_kload(&pcb[0], hello_fun, "A");
  context_kload(&pcb[1], hello_fun, "B");
  switch_boot_pcb();
}

Context* schedule(Context *prev) {
  current->cp = prev;
  current = (current == &pcb[0] ? &pcb[1] : &pcb[0]);
  return current->cp;
}
