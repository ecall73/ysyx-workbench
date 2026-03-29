#include <am.h>
#include <klib.h>
#include <rtthread.h>

typedef struct {
  void *tentry;
  void *parameter;
  void *texit;
} kctx_boot_t;

typedef struct {
  uintptr_t magic;
  Context **from;
  Context **to;
} kctx_switch_req_t;

#define KCTX_SWITCH_MAGIC 0x63747873u /* "ctxs" */

static void rt_kthread_bootstrap(void *arg) {
  kctx_boot_t *boot = (kctx_boot_t *)arg;
  void (*entry)(void *) = (void (*)(void *))boot->tentry;
  void (*texit)(void) = (void (*)(void))boot->texit;
  entry(boot->parameter);
  texit();
  halt(1);
}

static kctx_switch_req_t *kctx_get_switch_req(rt_thread_t self) {
  if (self == RT_NULL || self->user_data == 0) {
    return RT_NULL;
  }
  uintptr_t p = self->user_data;
  uintptr_t lo = (uintptr_t)self->stack_addr;
  uintptr_t hi = lo + self->stack_size;
  if (!(lo <= p && p + sizeof(kctx_switch_req_t) <= hi)) {
    return RT_NULL;
  }
  kctx_switch_req_t *req = (kctx_switch_req_t *)p;
  if (req->magic != KCTX_SWITCH_MAGIC) {
    return RT_NULL;
  }
  return req;
}

static Context* ev_handler(Event e, Context *c) {
  switch (e.event) {
    case EVENT_YIELD: {
      rt_thread_t self = rt_thread_self();
      kctx_switch_req_t *req = kctx_get_switch_req(self);
      if (req == RT_NULL) {
        return c;
      }
      if (req->from != RT_NULL) {
        *req->from = c;
      }
      Context *next = *req->to;
      RT_ASSERT(next != RT_NULL);
      return next;
    }
    case EVENT_IRQ_TIMER:
      rt_interrupt_enter();
      rt_tick_increase();
      rt_interrupt_leave();
      return c;
    default: printf("Unhandled event ID = %d\n", e.event); assert(0);
  }
  return c;
}

void __am_cte_init() {
  cte_init(ev_handler);
}

void rt_hw_context_switch_to(rt_ubase_t to) {
  rt_thread_t self = rt_thread_self();
  RT_ASSERT(self != RT_NULL);
  uintptr_t saved_user_data = self->user_data;
  kctx_switch_req_t req = {
    .magic = KCTX_SWITCH_MAGIC,
    .from = RT_NULL,
    .to = (Context **)to,
  };
  self->user_data = (rt_ubase_t)(uintptr_t)&req;
  yield();
  self->user_data = saved_user_data;
}

void rt_hw_context_switch(rt_ubase_t from, rt_ubase_t to) {
  rt_thread_t self = rt_thread_self();
  RT_ASSERT(self != RT_NULL);
  uintptr_t saved_user_data = self->user_data;
  kctx_switch_req_t req = {
    .magic = KCTX_SWITCH_MAGIC,
    .from = (Context **)from,
    .to = (Context **)to,
  };
  self->user_data = (rt_ubase_t)(uintptr_t)&req;
  yield();
  self->user_data = saved_user_data;
}

void rt_hw_context_switch_interrupt(void *context, rt_ubase_t from, rt_ubase_t to, struct rt_thread *to_thread) {
  (void)context;
  (void)to_thread;
  rt_hw_context_switch(from, to);
}

rt_uint8_t *rt_hw_stack_init(void *tentry, void *parameter, rt_uint8_t *stack_addr, void *texit) {
  uintptr_t stack_top = RT_ALIGN_DOWN((uintptr_t)stack_addr, sizeof(uintptr_t));
  uintptr_t ctx_base = stack_top - sizeof(Context);
  uintptr_t boot_addr = RT_ALIGN_DOWN(ctx_base - sizeof(kctx_boot_t), sizeof(uintptr_t));

  kctx_boot_t *boot = (kctx_boot_t *)boot_addr;
  boot->tentry = tentry;
  boot->parameter = parameter;
  boot->texit = texit;

  Context *cp = kcontext((Area){ .start = (void *)boot_addr, .end = (void *)stack_top },
                         rt_kthread_bootstrap, boot);
  RT_ASSERT(cp != RT_NULL);
  return (rt_uint8_t *)cp;
}
