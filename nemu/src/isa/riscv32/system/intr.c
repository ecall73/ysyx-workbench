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
  MSTATUS_MIE  = (1u << 3),
  MSTATUS_MPIE = (1u << 7),
  MSTATUS_MPP  = (3u << 11),
};

vaddr_t isa_raise_intr(word_t NO, vaddr_t epc) {
  word_t mstatus = cpu.mstatus;
  word_t prev_priv = cpu.priv;
  word_t mie = (mstatus & MSTATUS_MIE) ? 1 : 0;
  mstatus = (mstatus & ~MSTATUS_MPIE) | (mie ? MSTATUS_MPIE : 0);
  mstatus &= ~MSTATUS_MIE;
  mstatus = (mstatus & ~MSTATUS_MPP) | (prev_priv << 11);

  cpu.mstatus = mstatus;
  cpu.priv = MODE_M;
  cpu.mepc = epc;
  cpu.mcause = NO;
  return cpu.mtvec & ~0x3;
}

vaddr_t isa_mret() {
  word_t mstatus = cpu.mstatus;
  word_t prev_priv = (mstatus & MSTATUS_MPP) >> 11;
  word_t mpie = (mstatus & MSTATUS_MPIE) ? 1 : 0;
  mstatus = (mstatus & ~MSTATUS_MIE) | (mpie ? MSTATUS_MIE : 0); // MIE <- MPIE
  mstatus |= MSTATUS_MPIE;                                        // MPIE <- 1
  mstatus &= ~MSTATUS_MPP;                                        // MPP <- U(0)
  cpu.mstatus = mstatus;
  cpu.priv = prev_priv;

  return cpu.mepc;
}

word_t isa_query_intr() {
  return INTR_EMPTY;
}
