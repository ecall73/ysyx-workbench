#include <proc.h>

static void *pf = NULL;

void* new_page(size_t nr_page) {
  assert((uintptr_t)pf + nr_page * PGSIZE <= (uintptr_t)heap.end);
  void *p = pf;
  pf = (void *)((uintptr_t)pf + nr_page * PGSIZE);
  return p;
}

#ifdef HAS_VME
static void* pg_alloc(int n) {
  assert(n % PGSIZE == 0);
  void *p = new_page(n / PGSIZE);
  memset(p, 0, n);
  return p;
}
#endif

void free_page(void *p) {
  panic("not implement yet");
}

/* The brk() system call handler. */
int mm_brk(uintptr_t brk) {
  uintptr_t new_max_brk = ROUNDUP(brk, PGSIZE);
  if (new_max_brk > current->max_brk) {
    for (uintptr_t va = current->max_brk; va < new_max_brk; va += PGSIZE) {
      map(&current->as, (void *)va, new_page(1), MMAP_READ | MMAP_WRITE);
    }
    current->max_brk = new_max_brk;
  }
  return 0;
}

void init_mm() {
  pf = (void *)ROUNDUP(heap.start, PGSIZE);
  Log("free physical pages starting from %p", pf);

#ifdef HAS_VME
  vme_init(pg_alloc, free_page);
#endif
}
