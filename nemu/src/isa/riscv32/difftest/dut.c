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
#include <cpu/difftest.h>
#include "../local-include/reg.h"

static bool check_reg(const char *name, word_t ref, word_t dut, vaddr_t pc) {
  if (ref == dut) return true;
  printf("difftest error at pc = " FMT_WORD ": %s mismatch, ref = " FMT_WORD ", dut = " FMT_WORD "\n",
      pc, name, ref, dut);
  return false;
}

bool isa_difftest_checkregs(CPU_state *ref_r, vaddr_t pc) {
  for (int i = 0; i < ARRLEN(cpu.gpr); i++) {
    if (ref_r->gpr[i] != cpu.gpr[i]) {
      printf("difftest error at pc = " FMT_WORD ": gpr[%d] mismatch, ref = " FMT_WORD ", dut = " FMT_WORD "\n",
          pc, i, ref_r->gpr[i], cpu.gpr[i]);
      return false;
    }
  }

  for (int i = 0; i < ARRLEN(cpu.fpr); i++) {
    if (ref_r->fpr[i] != cpu.fpr[i]) {
      printf("difftest error at pc = " FMT_WORD ": fpr[%d] mismatch, ref = 0x%016" PRIx64
          ", dut = 0x%016" PRIx64 ", ref-pc = " FMT_WORD ", dut-pc = " FMT_WORD
          ", ref-mstatus = " FMT_WORD ", ref-mcause = " FMT_WORD "\n",
          pc, i, ref_r->fpr[i], cpu.fpr[i], ref_r->pc, cpu.pc,
          ref_r->mstatus, ref_r->mcause);
      return false;
    }
  }

  return check_reg("pc", ref_r->pc, cpu.pc, pc)
      && check_reg("fcsr", ref_r->fcsr, cpu.fcsr, pc)
      && check_reg("mstatus", ref_r->mstatus, cpu.mstatus, pc)
      && check_reg("mtvec", ref_r->mtvec, cpu.mtvec, pc)
      && check_reg("mepc", ref_r->mepc, cpu.mepc, pc)
      && check_reg("mcause", ref_r->mcause, cpu.mcause, pc)
      && check_reg("mtval", ref_r->mtval, cpu.mtval, pc)
      && check_reg("medeleg", ref_r->medeleg, cpu.medeleg, pc)
      && check_reg("mideleg", ref_r->mideleg, cpu.mideleg, pc)
      && check_reg("mie", ref_r->mie, cpu.mie, pc)
      && check_reg("stvec", ref_r->stvec, cpu.stvec, pc)
      && check_reg("sepc", ref_r->sepc, cpu.sepc, pc)
      && check_reg("scause", ref_r->scause, cpu.scause, pc)
      && check_reg("stval", ref_r->stval, cpu.stval, pc)
      && check_reg("sscratch", ref_r->sscratch, cpu.sscratch, pc)
      && check_reg("satp", ref_r->satp, cpu.satp, pc)
      && check_reg("mscratch", ref_r->mscratch, cpu.mscratch, pc)
      && check_reg("menvcfgh", ref_r->menvcfgh, cpu.menvcfgh, pc)
      && check_reg("mcounteren", ref_r->mcounteren, cpu.mcounteren, pc)
      && check_reg("stimecmp", (word_t)ref_r->stimecmp,
          (word_t)cpu.stimecmp, pc)
      && check_reg("stimecmph", (word_t)(ref_r->stimecmp >> 32),
          (word_t)(cpu.stimecmp >> 32), pc)
      && check_reg("priv", ref_r->priv, cpu.priv, pc);
}

void isa_difftest_attach() {
}
