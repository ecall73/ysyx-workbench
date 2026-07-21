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

void context_uload(PCB *pcb, const char *filename, char *const argv[], char *const envp[]) {
  uintptr_t entry = loader(pcb, filename);
  void *ustack = new_page(STACK_SIZE / PGSIZE);
  Area stack = RANGE(ustack, (uint8_t *)ustack + STACK_SIZE);
  pcb->cp = ucontext(&pcb->as, RANGE(pcb->stack, pcb->stack + STACK_SIZE), (void *)entry);

  size_t argc = 0, envc = 0, str_size = 0;
  for (; argv[argc] != NULL; argc ++) {
    str_size += strlen(argv[argc]) + 1;
  }
  for (; envp[envc] != NULL; envc ++) {
    str_size += strlen(envp[envc]) + 1;
  }

  size_t args_size = (argc + envc + 3) * sizeof(uintptr_t);
  assert(str_size + args_size + 15 <= (uintptr_t)stack.end - (uintptr_t)stack.start);

  uintptr_t strings_start = (uintptr_t)stack.end - str_size;
  uintptr_t stack_end = ROUNDDOWN(strings_start, sizeof(uintptr_t));
  uintptr_t sp = ROUNDDOWN(stack_end - args_size, 16);

  *(uintptr_t *)sp = argc;
  char **stack_argv = (char **)(sp + sizeof(uintptr_t));
  char **stack_envp = stack_argv + argc + 1;

  char *str = (char *)strings_start;
  for (size_t i = 0; i < argc; i ++) {
    stack_argv[i] = str;
    str += strlen(argv[i]) + 1;
    strcpy(stack_argv[i], argv[i]);
  }
  stack_argv[argc] = NULL;
  for (size_t i = 0; i < envc; i ++) {
    stack_envp[i] = str;
    str += strlen(envp[i]) + 1;
    strcpy(stack_envp[i], envp[i]);
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
  char *const argv[] = { "/bin/exec-test", NULL };
  char *const envp[] = { NULL };

  Log("Initializing processes...");

  context_kload(&pcb[0], hello_fun, "A");
  context_uload(&pcb[1], "/bin/exec-test", argv, envp);
  switch_boot_pcb();
}

Context* schedule(Context *prev) {
  current->cp = prev;
  current = (current == &pcb[0] ? &pcb[1] : &pcb[0]);
  return current->cp;
}
