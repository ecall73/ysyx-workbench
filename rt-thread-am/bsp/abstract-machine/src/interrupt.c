#include <am.h>
#include <klib.h>
#include <rthw.h>

void rt_hw_interrupt_enable(rt_base_t level) {
  iset(level != 0);
}

rt_base_t rt_hw_interrupt_disable(void) {
  rt_base_t level = ienabled();
  iset(0);
  return level;
}
