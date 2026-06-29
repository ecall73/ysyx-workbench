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

enum {
  MSTATUS_MIE      = (1u << 3),
  MSTATUS_MPIE     = (1u << 7),
  MSTATUS_MPP_MASK = (3u << 11),
  MSTATUS_MPP_M    = (3u << 11),
};

vaddr_t isa_raise_intr(word_t NO, vaddr_t epc) {
  word_t mstatus = cpu.mstatus;
  word_t mie = (mstatus & MSTATUS_MIE) ? 1 : 0;
  mstatus = (mstatus & ~MSTATUS_MPIE) | (mie ? MSTATUS_MPIE : 0);
  mstatus &= ~MSTATUS_MIE;
  mstatus = (mstatus & ~MSTATUS_MPP_MASK) | MSTATUS_MPP_M;

  cpu.mstatus = mstatus;
  cpu.mepc = epc;
  cpu.mcause = NO;
  vaddr_t target = cpu.mtvec & ~0x3;
#ifdef CONFIG_ETRACE
  etrace_write("raise NO=%u epc=" FMT_WORD " -> mtvec=" FMT_WORD
      " mstatus=" FMT_WORD "\n", (uint32_t)NO, epc, target, cpu.mstatus);
#endif
  return target;
}

vaddr_t isa_mret() {
  word_t mstatus = cpu.mstatus;
  word_t mpie = (mstatus & MSTATUS_MPIE) ? 1 : 0;
  mstatus = (mstatus & ~MSTATUS_MIE) | (mpie ? MSTATUS_MIE : 0); // MIE <- MPIE
  mstatus |= MSTATUS_MPIE;                                        // MPIE <- 1
  mstatus &= ~MSTATUS_MPP_MASK;                                   // MPP <- U(0)
  cpu.mstatus = mstatus;

  vaddr_t target = cpu.mepc;
#ifdef CONFIG_ETRACE
  etrace_write("mret -> " FMT_WORD " mstatus=" FMT_WORD "\n", target, cpu.mstatus);
#endif
  return target;
}

word_t isa_query_intr() {
  return INTR_EMPTY;
}
