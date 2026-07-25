/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of Mulan PSL v2 at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
*
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include "mmu.h"
#include "sim.h"
#include "../../include/common.h"
#include <difftest-def.h>

#define NR_GPR MUXDEF(CONFIG_RVE, 16, 32)

static std::vector<std::pair<reg_t, abstract_device_t*>> difftest_plugin_devices;
static std::vector<std::string> difftest_htif_args;
static std::vector<std::pair<reg_t, mem_t*>> difftest_mem(
    1, std::make_pair(reg_t(DRAM_BASE), new mem_t(CONFIG_MSIZE)));
static debug_module_config_t difftest_dm_config = {
  .progbufsize = 2,
  .max_sba_data_width = 0,
  .require_authentication = false,
  .abstract_rti = 0,
  .support_hasel = true,
  .support_abstract_csr_access = true,
  .support_abstract_fpr_access = true,
  .support_haltgroups = true,
  .support_impebreak = true
};

struct diff_context_t {
  word_t gpr[MUXDEF(CONFIG_RVE, 16, 32)];
  word_t pc;
  word_t fcsr;
  uint64_t fpr[32];
  word_t stimecmp;
  word_t stimecmph;
  // Must match nemu/src/isa/riscv32/include/isa-def.h.
  word_t mstatus;
  word_t mtvec;
  word_t mepc;
  word_t mcause;
  word_t mtval;
  word_t medeleg;
  word_t mideleg;
  word_t mie;
  word_t stvec;
  word_t sepc;
  word_t scause;
  word_t stval;
  word_t sscratch;
  word_t satp;
  word_t mscratch;
  word_t menvcfgh;
  word_t mcounteren;
  word_t priv;
};

static_assert(sizeof(diff_context_t) == DIFFTEST_REG_SIZE,
    "Spike and NEMU DiffTest register layouts must match");

static sim_t* s = NULL;
static processor_t *p = NULL;
static state_t *state = NULL;

// NEMU owns pending interrupts and injects accepted interrupts through
// difftest_raise_intr(). Clear the NEMU-managed bits in Spike so that it
// cannot independently enter a trap while stepping an instruction for
// comparison.
static const reg_t difftest_pending_mask =
    MIP_SSIP | MIP_STIP | MIP_MTIP | MIP_SEIP;

void sim_t::diff_init(int port) {
  p = get_core("0");
  state = p->get_state();
}

void sim_t::diff_step(uint64_t n) {
  while (n-- > 0) {
    state->mip->backdoor_write_with_mask(difftest_pending_mask, 0);
    if (p->is_waiting_for_interrupt()) p->resume_from_wfi();
    step(1);
  }
}

void sim_t::diff_get_regs(void* diff_context) {
  struct diff_context_t* ctx = (struct diff_context_t*)diff_context;
  for (int i = 0; i < NR_GPR; i++) {
    ctx->gpr[i] = state->XPR[i];
  }
  ctx->pc = state->pc;
  ctx->fcsr = state->csrmap[CSR_FCSR]->read();
  for (int i = 0; i < NFPR; i++) {
    ctx->fpr[i] = state->FPR[i].v[0];
  }
  ctx->stimecmp = state->csrmap[CSR_STIMECMP]->read();
  ctx->stimecmph = state->csrmap[CSR_STIMECMPH]->read();
  ctx->mstatus = state->mstatus->read();
  ctx->mtvec = state->mtvec->read();
  ctx->mepc = state->mepc->read();
  ctx->mcause = state->mcause->read();
  ctx->mtval = state->mtval->read();
  ctx->medeleg = state->medeleg->read();
  ctx->mideleg = state->mideleg->read();
  ctx->mie = state->mie->read();
  ctx->stvec = state->stvec->read();
  ctx->sepc = state->sepc->read();
  ctx->scause = state->scause->read();
  ctx->stval = state->stval->read();
  ctx->sscratch = state->csrmap[CSR_SSCRATCH]->read();
  ctx->satp = state->satp->read();
  ctx->mscratch = state->csrmap[CSR_MSCRATCH]->read();
  ctx->menvcfgh = state->csrmap[CSR_MENVCFGH]->read();
  ctx->mcounteren = state->csrmap[CSR_MCOUNTEREN]->read();
  ctx->priv = state->prv;
}

void sim_t::diff_set_regs(void* diff_context) {
  struct diff_context_t* ctx = (struct diff_context_t*)diff_context;
  for (int i = 0; i < NR_GPR; i++) {
    state->XPR.write(i, (sword_t)ctx->gpr[i]);
  }
  state->pc = ctx->pc;
  // Spike rejects writes to floating-point CSRs while mstatus.FS is Off.
  // Temporarily enable FS so DiffTest can restore the complete architectural
  // state, then restore the DUT's exact mstatus below.
  state->mstatus->write(ctx->mstatus | (MSTATUS_FS & (MSTATUS_FS >> 1)));
  state->csrmap[CSR_FCSR]->write(ctx->fcsr);
  for (int i = 0; i < NFPR; i++) {
    freg_t value = {};
    value.v[0] = ctx->fpr[i];
    value.v[1] = UINT64_MAX;
    state->FPR.write(i, value);
  }
  state->mstatus->write(ctx->mstatus);
  state->mtvec->write(ctx->mtvec);
  state->mepc->write(ctx->mepc);
  state->mcause->write(ctx->mcause);
  state->mtval->write(ctx->mtval);
  state->medeleg->write(ctx->medeleg);
  state->mideleg->write(ctx->mideleg);
  state->mie->write(ctx->mie);
  state->stvec->write(ctx->stvec);
  state->sepc->write(ctx->sepc);
  state->scause->write(ctx->scause);
  state->stval->write(ctx->stval);
  state->csrmap[CSR_SSCRATCH]->write(ctx->sscratch);
  state->satp->write(ctx->satp);
  state->csrmap[CSR_MSCRATCH]->write(ctx->mscratch);
  state->csrmap[CSR_MENVCFGH]->write(ctx->menvcfgh);
  state->csrmap[CSR_MCOUNTEREN]->write(ctx->mcounteren);
  state->csrmap[CSR_STIMECMP]->write(ctx->stimecmp);
  state->csrmap[CSR_STIMECMPH]->write(ctx->stimecmph);
  p->set_privilege(ctx->priv);
}

void sim_t::diff_memcpy(reg_t dest, void* src, size_t n) {
  mmu_t* mmu = p->get_mmu();
  for (size_t i = 0; i < n; i++) {
    mmu->store<uint8_t>(dest+i, *((uint8_t*)src+i));
  }
}

extern "C" {

__EXPORT void difftest_memcpy(paddr_t addr, void *buf, size_t n, bool direction) {
  if (direction == DIFFTEST_TO_REF) {
    s->diff_memcpy(addr, buf, n);
  } else {
    assert(0);
  }
}

__EXPORT void difftest_regcpy(void* dut, bool direction) {
  if (direction == DIFFTEST_TO_REF) {
    s->diff_set_regs(dut);
  } else {
    s->diff_get_regs(dut);
  }
}

__EXPORT void difftest_exec(uint64_t n) {
  s->diff_step(n);
}

__EXPORT void difftest_init(int port) {
  difftest_htif_args.push_back("");
  const char *isa = "RV" MUXDEF(CONFIG_RV64, "64", "32")
      MUXDEF(CONFIG_RVE, "E", "I") "MAFDC_Zicsr_Zifencei_Zicntr_Sstc_Svadu";
  cfg_t *cfg = new cfg_t(/*default_initrd_bounds=*/std::make_pair((reg_t)0, (reg_t)0),
            /*default_bootargs=*/nullptr,
            /*default_isa=*/isa,
            /*default_priv=*/DEFAULT_PRIV,
            /*default_varch=*/DEFAULT_VARCH,
            /*default_misaligned=*/false,
            /*default_endianness*/endianness_little,
            /*default_pmpregions=*/16,
            /*default_mem_layout=*/std::vector<mem_cfg_t>(),
            /*default_hartids=*/std::vector<size_t>(1),
            /*default_real_time_clint=*/false,
            /*default_trigger_count=*/4);
  s = new sim_t(cfg, false,
      difftest_mem, difftest_plugin_devices, difftest_htif_args,
      difftest_dm_config, nullptr, false, NULL,
      false,
      NULL,
      true);
  s->diff_init(port);
}

__EXPORT void difftest_raise_intr(uint64_t NO) {
  trap_t t(NO);
  p->take_trap_public(t, state->pc);
}

}
