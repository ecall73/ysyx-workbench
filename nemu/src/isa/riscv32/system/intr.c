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

word_t isa_raise_intr(word_t NO, vaddr_t epc) {
  const word_t MSTATUS_MIE  = (1u << 3);
  const word_t MSTATUS_MPIE = (1u << 7);
  const word_t MSTATUS_MPP  = (3u << 11);

  word_t mstatus = cpu.mstatus;
  word_t mie = (mstatus & MSTATUS_MIE) ? 1 : 0;
  mstatus = (mstatus & ~MSTATUS_MPIE) | (mie ? MSTATUS_MPIE : 0);
  mstatus &= ~MSTATUS_MIE;
  mstatus = (mstatus & ~MSTATUS_MPP) | MSTATUS_MPP; // trap to M-mode

  cpu.mstatus = mstatus;
  cpu.mepc = epc;
  cpu.mcause = NO;
  return cpu.mtvec & ~0x3;
}

word_t isa_query_intr() {
  return INTR_EMPTY;
}
