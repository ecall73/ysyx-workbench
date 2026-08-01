#include <isa.h>
#include "local-include/csr.h"
#include "local-include/state.h"

static riscv_retire_info_t current_retire_info;

const riscv_retire_info_t *riscv_begin_arch_step(void) {
  current_retire_info = (riscv_retire_info_t) {
    .pre_mcountinhibit = cpu.mcountinhibit,
  };
  return &current_retire_info;
}

void riscv_record_counter_write(uint32_t addr) {
  switch (addr) {
    case CSR_MCYCLE:
    case CSR_MCYCLEH:
      current_retire_info.mcycle_written = true;
      current_retire_info.mcycle_write_value = cpu.mcycle;
      break;
    case CSR_MINSTRET:
    case CSR_MINSTRETH:
      current_retire_info.minstret_written = true;
      current_retire_info.minstret_write_value = cpu.minstret;
      break;
    case CSR_MCOUNTINHIBIT:
      current_retire_info.mcountinhibit_written = true;
      current_retire_info.mcountinhibit_write_value = cpu.mcountinhibit;
      break;
    default:
      panic("record unsupported counter CSR: 0x%03x", addr);
  }
}

void riscv_update_arch_state(const riscv_retire_info_t *retire_info) {
  Assert(retire_info == &current_retire_info,
      "invalid RISC-V retire_info pointer");

  cpu.mtime++;
  if (!(retire_info->pre_mcountinhibit & MCOUNTINHIBIT_CY)) cpu.mcycle++;
  if (!(retire_info->pre_mcountinhibit & MCOUNTINHIBIT_IR)) cpu.minstret++;

  if (retire_info->mcycle_written) {
    cpu.mcycle = retire_info->mcycle_write_value;
  }
  if (retire_info->minstret_written) {
    cpu.minstret = retire_info->minstret_write_value;
  }
  if (retire_info->mcountinhibit_written) {
    cpu.mcountinhibit = retire_info->mcountinhibit_write_value;
  }
}

word_t riscv_mip_value(void) {
  word_t pending = (cpu.msip ? MIP_MSIP : 0) | (cpu.ssip ? MIP_SSIP : 0);

  if (cpu.mtime >= cpu.mtimecmp) pending |= MIP_MTIP;
  if ((cpu.menvcfgh & MENVCFGH_STCE) && cpu.mtime >= cpu.stimecmp) {
    pending |= MIP_STIP;
  }
  return pending;
}

word_t riscv_sip_value(void) {
  return riscv_mip_value() & cpu.mideleg;
}
