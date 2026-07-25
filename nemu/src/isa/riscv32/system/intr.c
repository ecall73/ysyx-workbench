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

#include <isa.h>
#include "../local-include/csr.h"

static vaddr_t trap_vector(word_t tvec, word_t cause) {
  vaddr_t base = tvec & ~0x3u;
  bool vectored = (tvec & 0x3u) == 1;
  bool interrupt = cause >> 31;
  return interrupt && vectored ? base + ((cause & 0x7fffffffu) << 2) : base;
}

vaddr_t isa_raise_intr(word_t NO, vaddr_t epc) {
  Assert((epc & 0x1) == 0, "raise_intr with unaligned epc: NO=" FMT_WORD " epc=" FMT_WORD, NO, epc);
  word_t cause = NO & 0x7fffffffu;
  bool interrupt = NO >> 31;
  word_t deleg = interrupt ? cpu.mideleg : cpu.medeleg;
  bool delegated = cpu.priv != MODE_M && (deleg & (1u << cause));

  if (delegated) {
    word_t sie = cpu.mstatus & MSTATUS_SIE;
    cpu.mstatus = (cpu.mstatus & ~MSTATUS_SPIE) |
        (sie ? MSTATUS_SPIE : 0);
    cpu.mstatus &= ~MSTATUS_SIE;
    if (cpu.priv == MODE_S) cpu.mstatus |= MSTATUS_SPP;
    else cpu.mstatus &= ~MSTATUS_SPP;
    cpu.sepc = epc;
    cpu.scause = NO;
    cpu.stval = 0;
    cpu.priv = MODE_S;
    vaddr_t target = trap_vector(cpu.stvec, NO);
#ifdef CONFIG_ETRACE
    etrace_write("raise NO=%u epc=" FMT_WORD " -> stvec=" FMT_WORD
        " mstatus=" FMT_WORD "\n", (uint32_t)NO, epc, target, cpu.mstatus);
#endif
    return target;
  }

  word_t mstatus = cpu.mstatus;
  word_t old_mstatus = mstatus;
  word_t prev_priv = cpu.priv;
  word_t mie = (mstatus & MSTATUS_MIE) ? 1 : 0;
  mstatus = (mstatus & ~MSTATUS_MPIE) | (mie ? MSTATUS_MPIE : 0);
  mstatus &= ~MSTATUS_MIE;
  mstatus = (mstatus & ~MSTATUS_MPP) | (prev_priv << 11);

  cpu.mstatus = mstatus;
  cpu.priv = MODE_M;
  cpu.mepc = epc;
  cpu.mcause = NO;
  cpu.mtval = 0;
  vaddr_t target = trap_vector(cpu.mtvec, NO);
  Assert(cpu.mepc == epc && cpu.mcause == NO,
      "raise_intr state mismatch: NO=" FMT_WORD " epc=" FMT_WORD " mepc=" FMT_WORD " mcause=" FMT_WORD,
      NO, epc, cpu.mepc, cpu.mcause);
  Assert((cpu.mstatus & MSTATUS_MIE) == 0 &&
      ((cpu.mstatus & MSTATUS_MPP) >> 11) == prev_priv && cpu.priv == MODE_M,
      "raise_intr mstatus mismatch: NO=" FMT_WORD " epc=" FMT_WORD " old_mstatus=" FMT_WORD
      " new_mstatus=" FMT_WORD,
      NO, epc, old_mstatus, cpu.mstatus);
  Assert((target & 0x3) == 0,
      "raise_intr target is unaligned: NO=" FMT_WORD " epc=" FMT_WORD " mtvec=" FMT_WORD " target=" FMT_WORD,
      NO, epc, cpu.mtvec, target);
#ifdef CONFIG_ETRACE
  etrace_write("raise NO=%u epc=" FMT_WORD " -> mtvec=" FMT_WORD
      " mstatus=" FMT_WORD "\n", (uint32_t)NO, epc, target, cpu.mstatus);
#endif
  return target;
}

vaddr_t isa_mret() {
  Assert(cpu.priv == MODE_M, "mret outside M-mode: pc=" FMT_WORD " priv=%u",
      cpu.pc, cpu.priv);
  word_t mstatus = cpu.mstatus;
  word_t old_mstatus = mstatus;
  word_t prev_priv = (mstatus & MSTATUS_MPP) >> 11;
  word_t mpie = (mstatus & MSTATUS_MPIE) ? 1 : 0;
  mstatus = (mstatus & ~MSTATUS_MIE) | (mpie ? MSTATUS_MIE : 0); // MIE <- MPIE
  mstatus |= MSTATUS_MPIE;                                        // MPIE <- 1
  mstatus &= ~MSTATUS_MPP;                                        // MPP <- U(0)
  cpu.mstatus = mstatus;
  cpu.priv = prev_priv;
  if (prev_priv != MODE_M) cpu.mstatus &= ~MSTATUS_MPRV;

  vaddr_t target = cpu.mepc;
  Assert((target & 0x1) == 0,
      "mret target is unaligned: mepc=" FMT_WORD " old_mstatus=" FMT_WORD " new_mstatus=" FMT_WORD,
      target, old_mstatus, cpu.mstatus);
  Assert((cpu.mstatus & MSTATUS_MPIE) != 0 && (cpu.mstatus & MSTATUS_MPP) == 0 &&
      cpu.priv == prev_priv,
      "mret mstatus mismatch: target=" FMT_WORD " old_mstatus=" FMT_WORD " new_mstatus=" FMT_WORD,
      target, old_mstatus, cpu.mstatus);
#ifdef CONFIG_ETRACE
  etrace_write("mret -> " FMT_WORD " mstatus=" FMT_WORD "\n", target, cpu.mstatus);
#endif
  return target;
}

vaddr_t isa_sret() {
  Assert(cpu.priv != MODE_U, "sret from U-mode: pc=" FMT_WORD, cpu.pc);
  word_t prev_priv = (cpu.mstatus & MSTATUS_SPP) ? MODE_S : MODE_U;
  word_t spie = cpu.mstatus & MSTATUS_SPIE;
  cpu.mstatus = (cpu.mstatus & ~MSTATUS_SIE) |
      (spie ? MSTATUS_SIE : 0);
  cpu.mstatus |= MSTATUS_SPIE;
  cpu.mstatus &= ~MSTATUS_SPP;
  cpu.mstatus &= ~MSTATUS_MPRV;
  cpu.priv = prev_priv;
  return cpu.sepc;
}

word_t isa_query_intr() {
  word_t enabled = cpu.mip & cpu.mie;

  static const uint8_t priority[] = { IRQ_MTIP, IRQ_SEIP, IRQ_SSIP, IRQ_STIP };
  for (int i = 0; i < ARRLEN(priority); i++) {
    word_t irq = priority[i];
    word_t mask = 1u << irq;
    if (!(enabled & mask)) continue;

    bool delegated = cpu.mideleg & mask;
    bool globally_enabled;
    if (delegated) {
      globally_enabled = cpu.priv < MODE_S ||
          (cpu.priv == MODE_S && (cpu.mstatus & MSTATUS_SIE));
    } else {
      globally_enabled = cpu.priv < MODE_M ||
          (cpu.priv == MODE_M && (cpu.mstatus & MSTATUS_MIE));
    }
    if (!globally_enabled) continue;
    return 0x80000000u | irq;
  }
  return INTR_EMPTY;
}
