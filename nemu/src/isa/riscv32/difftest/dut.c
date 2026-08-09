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
#include "../local-include/difftest.h"

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
      dut->state.gpr_valid_mask != UINT32_MAX) {
    printf("DiffTest %s sequence=%" PRIu64 " at pc=" FMT_WORD
        ": invalid field mask\n",
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
