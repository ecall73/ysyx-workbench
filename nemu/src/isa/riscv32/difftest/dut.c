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
#include "../local-include/difftest.h"

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
      && check_reg("scounteren", ref_r->scounteren, cpu.scounteren, pc)
      && check_reg("mcountinhibit", ref_r->mcountinhibit,
          cpu.mcountinhibit, pc)
      && check_reg("priv", ref_r->priv, cpu.priv, pc);
}

void isa_difftest_attach() {
}

static bool check_u32_field(const char *event_name, uint64_t sequence,
    vaddr_t event_pc, const char *name, uint32_t ref, uint32_t dut) {
  if (ref == dut) return true;
  printf("DiffTest %s sequence=%" PRIu64 " at pc=" FMT_WORD
      ": %s mismatch, ref=" FMT_WORD ", dut=" FMT_WORD "\n",
      event_name, sequence, event_pc, name, ref, dut);
  return false;
}

static bool check_u64_field(const char *event_name, uint64_t sequence,
    vaddr_t event_pc, const char *name, uint64_t ref, uint64_t dut) {
  if (ref == dut) return true;
  printf("DiffTest %s sequence=%" PRIu64 " at pc=" FMT_WORD
      ": %s mismatch, ref=0x%016" PRIx64 ", dut=0x%016" PRIx64 "\n",
      event_name, sequence, event_pc, name, ref, dut);
  return false;
}

bool riscv_difftest_check_observation(
    const riscv_difftest_observation_t *ref,
    const riscv_difftest_observation_t *dut,
    const char *event_name, vaddr_t event_pc) {
  if (ref == NULL || dut == NULL || event_name == NULL) return false;
  if (ref->abi_version != RISCV_DIFFTEST_ABI_VERSION ||
      dut->abi_version != RISCV_DIFFTEST_ABI_VERSION ||
      ref->struct_size != sizeof(*ref) || dut->struct_size != sizeof(*dut)) {
    printf("DiffTest %s at pc=" FMT_WORD
        ": invalid observation header, ref={version=%u,size=%u}, "
        "dut={version=%u,size=%u}\n",
        event_name, event_pc, ref->abi_version, ref->struct_size,
        dut->abi_version, dut->struct_size);
    return false;
  }
  if (ref->sequence != dut->sequence) {
    printf("DiffTest %s at pc=" FMT_WORD
        ": sequence mismatch, ref=%" PRIu64 ", dut=%" PRIu64 "\n",
        event_name, event_pc, ref->sequence, dut->sequence);
    return false;
  }
  if (ref->state.valid_fields != RISCV_DIFFTEST_RV32GC_STATE_FIELDS ||
      dut->state.valid_fields != RISCV_DIFFTEST_RV32GC_STATE_FIELDS ||
      ref->state.gpr_valid_mask != UINT32_MAX ||
      dut->state.gpr_valid_mask != UINT32_MAX ||
      ref->state.reserved_tail != 0 || dut->state.reserved_tail != 0) {
    printf("DiffTest %s sequence=%" PRIu64 " at pc=" FMT_WORD
        ": invalid field mask or reserved data\n",
        event_name, dut->sequence, event_pc);
    return false;
  }

  for (size_t i = 0; i < RISCV_DIFFTEST_MAX_GPRS; i++) {
    if (!check_u32_field(event_name, dut->sequence, event_pc, "gpr",
          ref->state.gpr[i], dut->state.gpr[i])) {
      printf("DiffTest mismatching GPR index: %zu\n", i);
      return false;
    }
  }
  for (size_t i = 0; i < RISCV_DIFFTEST_FPRS; i++) {
    if (!check_u64_field(event_name, dut->sequence, event_pc, "fpr",
          ref->state.fpr[i], dut->state.fpr[i])) {
      printf("DiffTest mismatching FPR index: %zu\n", i);
      return false;
    }
  }

#define CHECK_U32(name) \
  do { \
    if (!check_u32_field(event_name, dut->sequence, event_pc, #name, \
          ref->state.name, dut->state.name)) return false; \
  } while (0)
#define CHECK_U64(name) \
  do { \
    if (!check_u64_field(event_name, dut->sequence, event_pc, #name, \
          ref->state.name, dut->state.name)) return false; \
  } while (0)

  CHECK_U32(pc);
  CHECK_U32(fcsr);
  CHECK_U32(priv);
  CHECK_U64(mcycle);
  CHECK_U64(minstret);
  CHECK_U32(mstatus);
  CHECK_U32(mtvec);
  CHECK_U32(mepc);
  CHECK_U32(mcause);
  CHECK_U32(mtval);
  CHECK_U32(medeleg);
  CHECK_U32(mideleg);
  CHECK_U32(mie);
  CHECK_U32(stvec);
  CHECK_U32(sepc);
  CHECK_U32(scause);
  CHECK_U32(stval);
  CHECK_U32(sscratch);
  CHECK_U32(satp);
  CHECK_U32(mscratch);
  CHECK_U32(menvcfgh);
  CHECK_U32(mcounteren);
  CHECK_U32(scounteren);
  CHECK_U32(mcountinhibit);

#undef CHECK_U64
#undef CHECK_U32
  return true;
}
