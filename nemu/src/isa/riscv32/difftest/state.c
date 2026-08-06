#include <isa.h>
#include <string.h>
#include "../local-include/difftest.h"
#include "../local-include/fp.h"

void riscv_difftest_build_arch_state(riscv_difftest_arch_state_t *dest,
    uint32_t profile_id, const CPU_state *src) {
  Assert(dest != NULL && src != NULL, "null RISC-V DiffTest state");
  memset(dest, 0, sizeof(*dest));
  dest->pc = src->pc;

  if (profile_id == RISCV_DIFFTEST_PROFILE_RV32IMAC_NPC_NEMU) {
    Assert(ARRLEN(src->gpr) >= RISCV_DIFFTEST_MAX_GPRS,
        "RV32IMAC profile requires 32 GPRs");
    dest->valid_fields = RISCV_DIFFTEST_RV32IMAC_STATE_FIELDS;
    dest->gpr_valid_mask = RISCV_DIFFTEST_RV32IMAC_GPR_MASK;
    for (size_t i = 0; i < RISCV_DIFFTEST_MAX_GPRS; i++) {
      dest->gpr[i] = src->gpr[i];
    }
    dest->priv = src->priv;
    dest->mstatus = fp_normalize_mstatus(src->mstatus);
    dest->mtvec = src->mtvec;
    dest->mepc = src->mepc;
    dest->mcause = src->mcause;
    dest->mtval = src->mtval;
    dest->medeleg = src->medeleg;
    dest->mideleg = src->mideleg;
    dest->mie = src->mie;
    dest->stvec = src->stvec;
    dest->sepc = src->sepc;
    dest->scause = src->scause;
    dest->stval = src->stval;
    dest->sscratch = src->sscratch;
    dest->satp = src->satp;
    dest->mscratch = src->mscratch;
    dest->menvcfgh = src->menvcfgh;
    dest->mcounteren = src->mcounteren;
    dest->scounteren = src->scounteren;
    dest->mcountinhibit = src->mcountinhibit;
    return;
  }

  Assert(profile_id == RISCV_DIFFTEST_PROFILE_RV32GC_NEMU_SPIKE,
      "unsupported RISC-V DiffTest profile: %u", profile_id);
  Assert(ARRLEN(src->gpr) >= RISCV_DIFFTEST_MAX_GPRS,
      "RV32GC profile requires 32 GPRs");
  dest->valid_fields = RISCV_DIFFTEST_RV32GC_STATE_FIELDS;
  dest->gpr_valid_mask = UINT32_MAX;
  for (size_t i = 0; i < RISCV_DIFFTEST_MAX_GPRS; i++) {
    dest->gpr[i] = src->gpr[i];
  }
  dest->fcsr = src->fcsr;
  dest->priv = src->priv;
  for (size_t i = 0; i < RISCV_DIFFTEST_FPRS; i++) {
    dest->fpr[i] = src->fpr[i];
  }
  dest->mcycle = src->mcycle;
  dest->minstret = src->minstret;
  dest->mstatus = fp_normalize_mstatus(src->mstatus);
  dest->mtvec = src->mtvec;
  dest->mepc = src->mepc;
  dest->mcause = src->mcause;
  dest->mtval = src->mtval;
  dest->medeleg = src->medeleg;
  dest->mideleg = src->mideleg;
  dest->mie = src->mie;
  dest->stvec = src->stvec;
  dest->sepc = src->sepc;
  dest->scause = src->scause;
  dest->stval = src->stval;
  dest->sscratch = src->sscratch;
  dest->satp = src->satp;
  dest->mscratch = src->mscratch;
  dest->menvcfgh = src->menvcfgh;
  dest->mcounteren = src->mcounteren;
  dest->scounteren = src->scounteren;
  dest->mcountinhibit = src->mcountinhibit;
}

void riscv_difftest_build_observation(riscv_difftest_observation_t *dest,
    uint32_t profile_id, uint64_t sequence, const CPU_state *src) {
  memset(dest, 0, sizeof(*dest));
  dest->abi_version = RISCV_DIFFTEST_ABI_VERSION;
  dest->struct_size = sizeof(*dest);
  dest->sequence = sequence;
  riscv_difftest_build_arch_state(&dest->state, profile_id, src);
}

void riscv_difftest_build_sync_state(riscv_difftest_sync_state_t *dest,
    uint32_t profile_id, const CPU_state *src) {
  memset(dest, 0, sizeof(*dest));
  dest->abi_version = RISCV_DIFFTEST_ABI_VERSION;
  dest->struct_size = sizeof(*dest);
  riscv_difftest_build_arch_state(&dest->state, profile_id, src);
}

int riscv_difftest_build_skip_sync_state(riscv_difftest_sync_state_t *dest,
    uint32_t reason, uint32_t instruction_bits, uint32_t instruction_length,
    const CPU_state *src) {
  uint32_t gpr_mask;
  int status = riscv_difftest_skip_gpr_mask(reason, instruction_bits,
      instruction_length, &gpr_mask);
  if (status != RISCV_DIFFTEST_OK) return status;
  riscv_difftest_build_sync_state(dest,
      RISCV_DIFFTEST_PROFILE_RV32GC_NEMU_SPIKE, src);
  dest->state.valid_fields = riscv_difftest_skip_sync_fields(
      RISCV_DIFFTEST_PROFILE_RV32GC_NEMU_SPIKE, reason);
  dest->state.gpr_valid_mask = gpr_mask;
  if (gpr_mask == 0) {
    dest->state.valid_fields &= ~RISCV_DIFFTEST_FIELD_GPR;
  }
  return RISCV_DIFFTEST_OK;
}

int riscv_difftest_apply_sync_state(CPU_state *dest,
    uint32_t profile_id, const riscv_difftest_sync_state_t *src) {
  if (dest == NULL || src == NULL) return RISCV_DIFFTEST_BAD_ARGUMENT;
  if (src->abi_version != RISCV_DIFFTEST_ABI_VERSION) {
    return RISCV_DIFFTEST_BAD_ABI_VERSION;
  }
  if (src->struct_size != sizeof(*src)) return RISCV_DIFFTEST_BAD_STRUCT_SIZE;
  bool rv32imac_profile =
      profile_id == RISCV_DIFFTEST_PROFILE_RV32IMAC_NPC_NEMU;
  if (!rv32imac_profile &&
      profile_id != RISCV_DIFFTEST_PROFILE_RV32GC_NEMU_SPIKE) {
    return RISCV_DIFFTEST_UNSUPPORTED_PROFILE;
  }
  const uint64_t allowed_fields = rv32imac_profile
      ? RISCV_DIFFTEST_RV32IMAC_STATE_FIELDS
      : RISCV_DIFFTEST_RV32GC_STATE_FIELDS;
  const uint32_t allowed_gprs = UINT32_MAX;
  const size_t gpr_count = RISCV_DIFFTEST_MAX_GPRS;
  if (gpr_count > ARRLEN(dest->gpr)) return RISCV_DIFFTEST_BAD_STATE;
  if ((src->state.valid_fields & ~allowed_fields) != 0 ||
      ((src->state.valid_fields & RISCV_DIFFTEST_FIELD_GPR) == 0 &&
       src->state.gpr_valid_mask != 0) ||
      (src->state.gpr_valid_mask & ~allowed_gprs) != 0 ||
      ((src->state.gpr_valid_mask & 1u) != 0 && src->state.gpr[0] != 0) ||
      src->state.reserved_tail != 0) {
    return RISCV_DIFFTEST_BAD_STATE;
  }
  if ((src->state.valid_fields & RISCV_DIFFTEST_FIELD_PRIV) &&
      src->state.priv != MODE_U && src->state.priv != MODE_S &&
      src->state.priv != MODE_M) {
    return RISCV_DIFFTEST_BAD_STATE;
  }
  if (src->state.valid_fields & RISCV_DIFFTEST_FIELD_GPR) {
    for (size_t i = 0; i < gpr_count; i++) {
      if (src->state.gpr_valid_mask & (UINT32_C(1) << i)) {
        dest->gpr[i] = src->state.gpr[i];
      }
    }
  }
  if (src->state.valid_fields & RISCV_DIFFTEST_FIELD_PC) {
    dest->pc = src->state.pc;
  }
  if (!rv32imac_profile &&
      (src->state.valid_fields & RISCV_DIFFTEST_FIELD_FCSR)) {
    dest->fcsr = src->state.fcsr;
  }
  if (!rv32imac_profile &&
      (src->state.valid_fields & RISCV_DIFFTEST_FIELD_FPR)) {
    for (size_t i = 0; i < RISCV_DIFFTEST_FPRS; i++) {
      dest->fpr[i] = src->state.fpr[i];
    }
  }
#define APPLY_FIELD(bit, member) \
  do { \
    if (src->state.valid_fields & (bit)) dest->member = src->state.member; \
  } while (0)
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MCYCLE, mcycle);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MINSTRET, minstret);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MSTATUS, mstatus);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MTVEC, mtvec);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MEPC, mepc);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MCAUSE, mcause);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MTVAL, mtval);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MEDELEG, medeleg);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MIDELEG, mideleg);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MIE, mie);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_STVEC, stvec);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_SEPC, sepc);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_SCAUSE, scause);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_STVAL, stval);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_SSCRATCH, sscratch);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_SATP, satp);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MSCRATCH, mscratch);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MENVCFGH, menvcfgh);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MCOUNTEREN, mcounteren);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_SCOUNTEREN, scounteren);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_MCOUNTINHIBIT, mcountinhibit);
  APPLY_FIELD(RISCV_DIFFTEST_FIELD_PRIV, priv);
#undef APPLY_FIELD
  return RISCV_DIFFTEST_OK;
}
