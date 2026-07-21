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

static size_t strv_len(char *const v[]) {
  size_t n = 0;
  if (v != NULL) {
    while (v[n] != NULL) {
      n ++;
    }
  }
  return n;
}

static void context_uload(PCB *pcb, const char *filename, char *const argv[], char *const envp[]) {
  uintptr_t entry = loader(pcb, filename);
  pcb->cp = ucontext(&pcb->as, RANGE(pcb->stack, pcb->stack + STACK_SIZE), (void *)entry);

  size_t argc = strv_len(argv);
  size_t envc = strv_len(envp);
  size_t str_size = 0;
  for (size_t i = 0; i < argc; i ++) {
    str_size += strlen(argv[i]) + 1;
  }
  for (size_t i = 0; i < envc; i ++) {
    str_size += strlen(envp[i]) + 1;
  }

  uintptr_t sp = (uintptr_t)heap.end - str_size;
  char *str = (char *)sp;
  for (size_t i = 0; i < argc; i ++) {
    strcpy(str, argv[i]);
    str += strlen(str) + 1;
  }
  for (size_t i = 0; i < envc; i ++) {
    strcpy(str, envp[i]);
    str += strlen(str) + 1;
  }

  sp = ROUNDDOWN(sp, sizeof(uintptr_t));
  sp -= (envc + 1) * sizeof(uintptr_t);
  char **stack_envp = (char **)sp;
  sp -= (argc + 1) * sizeof(uintptr_t);
  char **stack_argv = (char **)sp;
  sp -= sizeof(uintptr_t);
  *(uintptr_t *)sp = argc;
  assert(sp >= (uintptr_t)heap.start);

  str = (char *)heap.end - str_size;
  for (size_t i = 0; i < argc; i ++) {
    stack_argv[i] = str;
    str += strlen(str) + 1;
  }
  stack_argv[argc] = NULL;
  for (size_t i = 0; i < envc; i ++) {
    stack_envp[i] = str;
    str += strlen(str) + 1;
  }
  stack_envp[envc] = NULL;

  pcb->cp->GPRx = sp;
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
  char *const argv[] = { "/bin/pal", "--skip", NULL };
  char *const envp[] = { NULL };

  Log("Initializing processes...");

  context_kload(&pcb[0], hello_fun, "A");
  context_uload(&pcb[1], "/bin/pal", argv, envp);
  switch_boot_pcb();
}

Context* schedule(Context *prev) {
  current->cp = prev;
  current = (current == &pcb[0] ? &pcb[1] : &pcb[0]);
  return current->cp;
}
