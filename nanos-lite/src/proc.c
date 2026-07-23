#include <proc.h>

#define MAX_NR_PROC 4
#define PAL_TIME_SLICES 10

static PCB pcb[MAX_NR_PROC] __attribute__((used)) = {};
static PCB pcb_boot = {};
PCB *current = NULL;
static int pal_slices = 0;

void switch_boot_pcb() {
  current = &pcb_boot;
}

void context_kload(PCB *pcb, void (*entry)(void *), void *arg) {
  pcb->cp = kcontext(RANGE(pcb->stack, pcb->stack + STACK_SIZE), entry, arg);
}

void context_uload(PCB *pcb, const char *filename, char *const argv[], char *const envp[]) {
  protect(&pcb->as);

  void *stack = new_page(STACK_SIZE / PGSIZE);
  uintptr_t ustack = (uintptr_t)pcb->as.area.end - STACK_SIZE;
  for (size_t offset = 0; offset < STACK_SIZE; offset += PGSIZE) {
    map(&pcb->as, (void *)(ustack + offset), (uint8_t *)stack + offset,
        MMAP_READ | MMAP_WRITE);
  }

  size_t argc = 0, envc = 0, str_size = 0;
  for (; argv[argc] != NULL; argc ++) {
    str_size += strlen(argv[argc]) + 1;
  }
  for (; envp[envc] != NULL; envc ++) {
    str_size += strlen(envp[envc]) + 1;
  }

  size_t args_size = (argc + envc + 3) * sizeof(uintptr_t);
  assert(str_size + args_size + 15 <= STACK_SIZE);

  uintptr_t strings_offset = STACK_SIZE - str_size;
  uintptr_t stack_end = ROUNDDOWN(strings_offset, sizeof(uintptr_t));
  uintptr_t sp_offset = ROUNDDOWN(stack_end - args_size, 16);
  uintptr_t sp = ustack + sp_offset;

  uintptr_t *args = (uintptr_t *)((uint8_t *)stack + sp_offset);
  *args = argc;
  char **stack_argv = (char **)(args + 1);
  char **stack_envp = stack_argv + argc + 1;

  char *str = (char *)stack + strings_offset;
  uintptr_t user_str = ustack + strings_offset;
  for (size_t i = 0; i < argc; i ++) {
    stack_argv[i] = (char *)user_str;
    strcpy(str, argv[i]);
    size_t len = strlen(argv[i]) + 1;
    str += len;
    user_str += len;
  }
  stack_argv[argc] = NULL;
  for (size_t i = 0; i < envc; i ++) {
    stack_envp[i] = (char *)user_str;
    strcpy(str, envp[i]);
    size_t len = strlen(envp[i]) + 1;
    str += len;
    user_str += len;
  }
  stack_envp[envc] = NULL;

  uintptr_t entry = loader(pcb, filename);
  pcb->cp = ucontext(&pcb->as, RANGE(pcb->stack, pcb->stack + STACK_SIZE), (void *)entry);
  pcb->cp->gpr[2] = sp;
  pcb->cp->GPRx = sp;
}

void hello_fun(void *arg) {
  int j = 1;
  while (1) {
    if (j == 1 || j % 1000 == 0) {
      Log("Hello World from Nanos-lite with arg '%s' for the %dth time!", (char *)arg, j);
    }
    j ++;
    yield();
  }
}

void init_proc() {
  char *const argv[] = { "pal", NULL };
  char *const envp[] = { NULL };

  Log("Initializing processes...");

  context_kload(&pcb[0], hello_fun, "hello");
  context_uload(&pcb[1], "/bin/pal", argv, envp);
  switch_boot_pcb();
}

Context* schedule(Context *prev) {
  current->cp = prev;
  if (current->as.ptr == NULL) {
    current->cp->pdir = NULL;
  }
  if (pal_slices < PAL_TIME_SLICES) {
    current = &pcb[1];
    pal_slices++;
  } else {
    current = &pcb[0];
    pal_slices = 0;
  }
  return current->cp;
}
