#include <am.h>
#include <klib.h>
#include <rtthread.h>

typedef struct {
  void *tentry;
  void *parameter;
  void *texit;
} kctx_boot_t;

static Context **ctx_from = RT_NULL;
static Context **ctx_to = RT_NULL;

static void rt_kthread_bootstrap(void *arg) {
  kctx_boot_t *boot = (kctx_boot_t *)arg;
  void (*entry)(void *) = (void (*)(void *))boot->tentry;
  void (*texit)(void) = (void (*)(void))boot->texit;
  entry(boot->parameter);
  texit();
  halt(1);
}

static Context* ev_handler(Event e, Context *c) {
  switch (e.event) {
    case EVENT_YIELD: {
      if (ctx_to == RT_NULL) {
        return c;
      }
      if (ctx_from != RT_NULL) {
        *ctx_from = c;
      }
      Context *next = *ctx_to;
      RT_ASSERT(next != RT_NULL);
      ctx_from = RT_NULL;
      ctx_to = RT_NULL;
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
  ctx_from = RT_NULL;
  ctx_to = (Context **)to;
  yield();
}

void rt_hw_context_switch(rt_ubase_t from, rt_ubase_t to) {
  ctx_from = (Context **)from;
  ctx_to = (Context **)to;
  yield();
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
