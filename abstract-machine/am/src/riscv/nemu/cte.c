#include <am.h>
#include <riscv/riscv.h>
#include <klib.h>

static Context* (*user_handler)(Event, Context*) = NULL;

void __am_get_cur_as(Context *c);
void __am_switch(Context *c);
void __am_timer_irq_init(void);
void __am_timer_irq_ack(void);

static void __am_kcontext_start(void *entry, void *arg) {
  ((void (*)(void *))entry)(arg);
  halt(1);
}

Context* __am_irq_handle(Context *c) {
  if (user_handler) {
    __am_get_cur_as(c);
    Event ev = {0};
    switch (c->mcause) {
      case ((uintptr_t)1 << (sizeof(uintptr_t) * 8 - 1)) | 7:
        __am_timer_irq_ack();
        ev.event = EVENT_IRQ_TIMER;
        break;
      case 8:
      case 11:
        c->mepc += 4;
        ev.event = (c->GPR1 == (uintptr_t)-1) ? EVENT_YIELD : EVENT_SYSCALL;
        break;
      default: ev.event = EVENT_ERROR; break;
    }

    c = user_handler(ev, c);
    assert(c != NULL);
    __am_switch(c);
  }

  return c;
}

extern void __am_asm_trap(void);

bool cte_init(Context*(*handler)(Event, Context*)) {
  // initialize exception entry
  asm volatile("csrw mtvec, %0" : : "r"(__am_asm_trap));
  asm volatile("csrw mscratch, zero");

  // register event handler
  user_handler = handler;
  __am_timer_irq_init();

  return true;
}

Context *kcontext(Area kstack, void (*entry)(void *), void *arg) {
  Context *c = (Context *)kstack.end - 1;
  assert(kstack.start <= (void *)c && (void *)c < kstack.end);
  *c = (Context) {0};
  c->mepc = (uintptr_t)__am_kcontext_start;
  c->mstatus = MSTATUS_MPP_M | MSTATUS_MPIE;
  c->gpr[2] = (uintptr_t)kstack.end;
  c->gpr[10] = (uintptr_t)entry; // a0: __am_kcontext_start(entry, arg)
  c->gpr[11] = (uintptr_t)arg;   // a1
  c->pdir = NULL;
  return c;
}

void yield() {
#ifdef __riscv_e
  asm volatile("li a5, -1; ecall");
#else
  asm volatile("li a7, -1; ecall");
#endif
}

bool ienabled() {
  uintptr_t mstatus;
  asm volatile("csrr %0, mstatus" : "=r"(mstatus));
  return mstatus & MSTATUS_MIE;
}

void iset(bool enable) {
  if (enable) {
    asm volatile("csrsi mstatus, 8");
  } else {
    asm volatile("csrci mstatus, 8");
  }
}
