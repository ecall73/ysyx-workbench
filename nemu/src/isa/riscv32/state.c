#include <isa.h>
#include "local-include/csr.h"
#include "local-include/state.h"

void riscv_update_arch_state(void) {
  cpu.mtime++;

  word_t timer_pending = cpu.mtime >= cpu.mtimecmp ? MIP_MTIP : 0;
  if ((cpu.menvcfgh & MENVCFGH_STCE) && cpu.mtime >= cpu.stimecmp) {
    timer_pending |= MIP_STIP;
  }
  cpu.mip = (cpu.mip & ~(MIP_MTIP | MIP_STIP)) | timer_pending;
}
