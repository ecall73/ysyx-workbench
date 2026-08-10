#include <am.h>
#include <nemu.h>
#include <klib.h>

static AddrSpace kas = {};
static void* (*pgalloc_usr)(int) = NULL;
static void (*pgfree_usr)(void*) = NULL;
static int vme_enable = 0;

static Area segments[] = {      // Kernel memory mappings
  NEMU_PADDR_SPACE
};

#define USER_SPACE RANGE(0x40000000, 0x80000000)

static inline void set_satp(void *pdir) {
  uintptr_t mode = 1ul << (__riscv_xlen - 1);
  asm volatile("csrw satp, %0" : : "r"(mode | ((uintptr_t)pdir >> 12)));
}

static inline uintptr_t get_satp() {
  uintptr_t satp;
  asm volatile("csrr %0, satp" : "=r"(satp));
  return satp << 12;
}

bool vme_init(void* (*pgalloc_f)(int), void (*pgfree_f)(void*)) {
  pgalloc_usr = pgalloc_f;
  pgfree_usr = pgfree_f;

  kas.ptr = pgalloc_f(PGSIZE);
  for (int i = 0; i < LENGTH(segments); i ++) {
    for (void *va = segments[i].start; va < segments[i].end; va += PGSIZE) {
      map(&kas, va, va, 0);
    }
  }

  set_satp(kas.ptr);
  vme_enable = 1;

  return true;
}

void protect(AddrSpace *as) {
  PTE *updir = (PTE*)(pgalloc_usr(PGSIZE));
  as->ptr = updir;
  as->area = USER_SPACE;
  as->pgsize = PGSIZE;
  // map kernel space
  memcpy(updir, kas.ptr, PGSIZE);
}

void unprotect(AddrSpace *as) {
}

void __am_get_cur_as(Context *c) {
  c->pdir = (vme_enable ? (void *)get_satp() : NULL);
}

void __am_switch(Context *c) {
  if (vme_enable && c->pdir != NULL) {
    set_satp(c->pdir);
  }
}

void map(AddrSpace *as, void *va, void *pa, int prot) {
  assert((uintptr_t)va % PGSIZE == 0 && (uintptr_t)pa % PGSIZE == 0);

  PTE *pdir = as->ptr;
  PTE *pde = &pdir[((uintptr_t)va >> 22) & 0x3ff];
  PTE *ptable;

  if (!(*pde & PTE_V)) {
    ptable = pgalloc_usr(PGSIZE);
    *pde = (((uintptr_t)ptable >> 12) << 10) | PTE_V;
  } else {
    ptable = (PTE *)(((*pde >> 10) << 12));
  }

  ptable[((uintptr_t)va >> 12) & 0x3ff] =
      (((uintptr_t)pa >> 12) << 10) | PTE_V | PTE_R | PTE_W | PTE_X |
      PTE_U | PTE_A | PTE_D;
  (void)prot;
}

Context *ucontext(AddrSpace *as, Area kstack, void *entry) {
  Context *c = (Context *)kstack.end - 1;
  assert(kstack.start <= (void *)c && (void *)c < kstack.end);
  *c = (Context) {0};
  c->mepc = (uintptr_t)entry;
  c->mstatus = MSTATUS_MPP_U | MSTATUS_MPIE | MSTATUS_MXR | MSTATUS_SUM;
  c->pdir = as->ptr;
  return c;
}
