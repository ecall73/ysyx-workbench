#include <string.h>

#include "common.h"
#include "cpu/difftest.h"
#include "memory/paddr.h"
#include "platform/platform.h"
#include "utils.h"
#include "internal.h"

enum SkipReason {
  SKIP_NONE = 0,
  SKIP_COUNTER_CSR,
  SKIP_MMIO,
};

#define CSR_MCYCLE      0xB00u
#define CSR_MSTATUS     0x300u
#define CSR_MTVEC       0x305u
#define CSR_MEPC        0x341u
#define CSR_MCAUSE      0x342u
#define CSR_MCYCLEH     0xB80u
#define CSR_MINSTRET    0xB02u
#define CSR_MINSTRETH   0xB82u
#define CSR_CYCLE       0xC00u
#define CSR_CYCLEH      0xC80u
#define CSR_TIME        0xC01u
#define CSR_TIMEH       0xC81u
#define CSR_INSTRET     0xC02u
#define CSR_INSTRETH    0xC82u

#define OPCODE_LOAD     0x03u
#define OPCODE_STORE    0x23u
#define OPCODE_SYSTEM   0x73u

static inline int32_t sext32(uint32_t val, int bits) {
  uint32_t m = 1u << (bits - 1);
  return (int32_t)((val ^ m) - m);
}

static void copy_dut_state(RefCPUState *dut_r, const DutState *state) {
  memset(dut_r, 0, sizeof(*dut_r));
  for (int i = 0; i < 32; i++) {
    dut_r->gpr[i] = state->gpr[i];
  }
  dut_r->pc = state->pc;
  dut_r->mstatus = state->mstatus;
  dut_r->mtvec = state->mtvec;
  dut_r->mepc = state->mepc;
  dut_r->mcause = state->mcause;
}

static SkipReason get_skip_reason(uint32_t inst, const RefCPUState *ref_pre) {
  uint32_t opcode = inst & 0x7fu;

  if (opcode == OPCODE_SYSTEM) {
    uint32_t funct3 = (inst >> 12) & 0x7u;
    if (funct3 != 0u) {
      uint32_t csr = (inst >> 20) & 0xfffu;
      if (csr == CSR_MCYCLE || csr == CSR_MCYCLEH || csr == CSR_MINSTRET || csr == CSR_MINSTRETH ||
          csr == CSR_CYCLE || csr == CSR_CYCLEH || csr == CSR_TIME || csr == CSR_TIMEH ||
          csr == CSR_INSTRET || csr == CSR_INSTRETH) {
        return SKIP_COUNTER_CSR;
      }
    }
    return SKIP_NONE;
  }

  if (opcode == OPCODE_LOAD || opcode == OPCODE_STORE) {
    uint32_t rs1 = (inst >> 15) & 0x1fu;
    int32_t imm = 0;
    if (opcode == OPCODE_LOAD) {
      imm = sext32((inst >> 20) & 0xfffu, 12);
    } else {
      uint32_t imm12 = ((inst >> 25) << 5) | ((inst >> 7) & 0x1fu);
      imm = sext32(imm12, 12);
    }
    uint32_t addr = ref_pre->gpr[rs1] + (uint32_t)imm;
    if (!platform_in_comparable_mem(addr)) {
      return SKIP_MMIO;
    }
  }

  return SKIP_NONE;
}

static void collect_dut_init_regs(RefCPUState *dut_r) {
  memset(dut_r, 0, sizeof(*dut_r));
  dut_r->pc = platform_reset_pc();
  dut_r->mstatus = 0x00001800u;
  dut_r->mtvec = 0x00000001u;
  dut_r->mepc = 0;
  dut_r->mcause = 0;
}

void difftest_init_ref_regs() {
  RefCPUState dut_r;
  collect_dut_init_regs(&dut_r);
  ref_difftest_regcpy(&dut_r, DIFFTEST_TO_REF);
}

static bool difftest_checkregs(const RefCPUState *ref_r, const RefCPUState *dut_r, uint32_t dut_pc) {
  for (int i = 0; i < 32; i++) {
    if (ref_r->gpr[i] != dut_r->gpr[i]) {
      Log("difftest error at pc = 0x%08x: gpr[%d] mismatch, ref = 0x%08x, dut = 0x%08x",
          dut_pc, i, ref_r->gpr[i], dut_r->gpr[i]);
      return false;
    }
  }
  if (ref_r->pc != dut_r->pc) {
    Log("difftest error at pc = 0x%08x: pc mismatch, ref = 0x%08x, dut = 0x%08x",
        dut_pc, ref_r->pc, dut_r->pc);
    return false;
  }
  if (ref_r->mstatus != dut_r->mstatus) {
    Log("difftest error at pc = 0x%08x: mstatus mismatch, ref = 0x%08x, dut = 0x%08x",
        dut_pc, ref_r->mstatus, dut_r->mstatus);
    return false;
  }
  if (ref_r->mtvec != dut_r->mtvec) {
    Log("difftest error at pc = 0x%08x: mtvec mismatch, ref = 0x%08x, dut = 0x%08x",
        dut_pc, ref_r->mtvec, dut_r->mtvec);
    return false;
  }
  if (ref_r->mepc != dut_r->mepc) {
    Log("difftest error at pc = 0x%08x: mepc mismatch, ref = 0x%08x, dut = 0x%08x",
        dut_pc, ref_r->mepc, dut_r->mepc);
    return false;
  }
  if (ref_r->mcause != dut_r->mcause) {
    Log("difftest error at pc = 0x%08x: mcause mismatch, ref = 0x%08x, dut = 0x%08x",
        dut_pc, ref_r->mcause, dut_r->mcause);
    return false;
  }
  return true;
}

bool difftest_step(uint32_t commit_pc, uint32_t commit_inst, const DutState *dut_state) {
  if (!difftest_enabled) {
    return true;
  }

  if (!platform_in_comparable_mem(commit_pc)) {
    Log("difftest detached: DUT enters unsupported ref execute region at pc = 0x%08x", commit_pc);
    difftest_enabled = false;
    return true;
  }

  RefCPUState ref_pre;
  ref_difftest_regcpy(&ref_pre, DIFFTEST_TO_DUT);
  if (ref_pre.pc != commit_pc) {
    Log("difftest error at pc = 0x%08x: pc mismatch before exec, ref = 0x%08x, dut = 0x%08x",
        commit_pc, ref_pre.pc, commit_pc);
    return false;
  }

  SkipReason skip_reason = get_skip_reason(commit_inst, &ref_pre);

  if (skip_reason == SKIP_MMIO || skip_reason == SKIP_COUNTER_CSR) {
    RefCPUState dut_ref_state;
    copy_dut_state(&dut_ref_state, dut_state);
    ref_difftest_regcpy(&dut_ref_state, DIFFTEST_TO_REF);
    return true;
  }

  ref_difftest_exec(1);

  RefCPUState ref_post;
  RefCPUState dut_ref_state;
  ref_difftest_regcpy(&ref_post, DIFFTEST_TO_DUT);
  copy_dut_state(&dut_ref_state, dut_state);

  return difftest_checkregs(&ref_post, &dut_ref_state, commit_pc);
}
