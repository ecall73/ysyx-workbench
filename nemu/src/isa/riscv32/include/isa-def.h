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

#ifndef __ISA_RISCV_H__
#define __ISA_RISCV_H__

#include <common.h>
#include <difftest-def.h>

typedef struct {
  word_t gpr[MUXDEF(CONFIG_RVE, 16, 32)];
  vaddr_t pc;
  word_t fcsr;
  uint64_t fpr[32];
  // Deterministic fields are packed into the explicit DiffTest context below.
  word_t mstatus, mtvec, mepc, mcause, mtval;
  word_t medeleg, mideleg, mie;
  word_t stvec, sepc, scause, stval, sscratch;
  word_t satp, mscratch, menvcfgh, mcounteren;
  word_t scounteren, mcountinhibit;
  word_t priv;
  // NEMU owns pending interrupts and timer state. They are outside the Spike
  // register-copy ABI, but remain part of the complete CPU state.
  word_t mip;
  uint64_t stimecmp, mtime, mtimecmp;
  bool lr_valid;
  paddr_t lr_addr;
} MUXDEF(CONFIG_RV64, riscv64_CPU_state, riscv32_CPU_state);

static inline void riscv_difftest_pack(riscv_difftest_context_t *ctx,
    const MUXDEF(CONFIG_RV64, riscv64_CPU_state, riscv32_CPU_state) *state) {
  for (int i = 0; i < RISCV_GPR_NUM; i++) ctx->gpr[i] = state->gpr[i];
  ctx->pc = state->pc;
  ctx->fcsr = state->fcsr;
  for (int i = 0; i < RISCV_FPR_NUM; i++) ctx->fpr[i] = state->fpr[i];
  ctx->mstatus = state->mstatus;
  ctx->mtvec = state->mtvec;
  ctx->mepc = state->mepc;
  ctx->mcause = state->mcause;
  ctx->mtval = state->mtval;
  ctx->medeleg = state->medeleg;
  ctx->mideleg = state->mideleg;
  ctx->mie = state->mie;
  ctx->stvec = state->stvec;
  ctx->sepc = state->sepc;
  ctx->scause = state->scause;
  ctx->stval = state->stval;
  ctx->sscratch = state->sscratch;
  ctx->satp = state->satp;
  ctx->mscratch = state->mscratch;
  ctx->menvcfgh = state->menvcfgh;
  ctx->mcounteren = state->mcounteren;
  ctx->scounteren = state->scounteren;
  ctx->mcountinhibit = state->mcountinhibit;
  ctx->priv = state->priv;
}

static inline void riscv_difftest_unpack(
    MUXDEF(CONFIG_RV64, riscv64_CPU_state, riscv32_CPU_state) *state,
    const riscv_difftest_context_t *ctx) {
  for (int i = 0; i < RISCV_GPR_NUM; i++) state->gpr[i] = ctx->gpr[i];
  state->pc = ctx->pc;
  state->fcsr = ctx->fcsr;
  for (int i = 0; i < RISCV_FPR_NUM; i++) state->fpr[i] = ctx->fpr[i];
  state->mstatus = ctx->mstatus;
  state->mtvec = ctx->mtvec;
  state->mepc = ctx->mepc;
  state->mcause = ctx->mcause;
  state->mtval = ctx->mtval;
  state->medeleg = ctx->medeleg;
  state->mideleg = ctx->mideleg;
  state->mie = ctx->mie;
  state->stvec = ctx->stvec;
  state->sepc = ctx->sepc;
  state->scause = ctx->scause;
  state->stval = ctx->stval;
  state->sscratch = ctx->sscratch;
  state->satp = ctx->satp;
  state->mscratch = ctx->mscratch;
  state->menvcfgh = ctx->menvcfgh;
  state->mcounteren = ctx->mcounteren;
  state->scounteren = ctx->scounteren;
  state->mcountinhibit = ctx->mcountinhibit;
  state->priv = ctx->priv;
}

enum { MODE_U, MODE_S, MODE_M = 3 };

// decode
typedef struct {
  uint32_t inst;
} MUXDEF(CONFIG_RV64, riscv64_ISADecodeInfo, riscv32_ISADecodeInfo);

int riscv32_mmu_check(vaddr_t vaddr, int len, int type);
#define isa_mmu_check(vaddr, len, type) riscv32_mmu_check(vaddr, len, type)

#endif
