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

static void context_uload(PCB *pcb, const char *filename) {
  uintptr_t entry = loader(pcb, filename);
  pcb->cp = ucontext(&pcb->as, RANGE(pcb->stack, pcb->stack + STACK_SIZE), (void *)entry);
  pcb->cp->GPRx = (uintptr_t)heap.end;
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
  context_uload(&pcb[1], "/bin/pal");
  switch_boot_pcb();
}

Context* schedule(Context *prev) {
  current->cp = prev;
  current = (current == &pcb[0] ? &pcb[1] : &pcb[0]);
  return current->cp;
}
