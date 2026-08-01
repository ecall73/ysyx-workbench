#include <isa.h>

static bool check_u32(const char *event_name, uint64_t sequence,
    vaddr_t event_pc, const char *field, uint32_t ref, uint32_t dut) {
  if (ref == dut) return true;
  printf("DiffTest %s sequence=%" PRIu64 " at pc=" FMT_WORD
      ": %s mismatch, ref=" FMT_WORD ", dut=" FMT_WORD "\n",
      event_name, sequence, event_pc, field, ref, dut);
  return false;
}

static bool check_u64(const char *event_name, uint64_t sequence,
    vaddr_t event_pc, const char *field, uint64_t ref, uint64_t dut) {
  if (ref == dut) return true;
  printf("DiffTest %s sequence=%" PRIu64 " at pc=" FMT_WORD
      ": %s mismatch, ref=0x%016" PRIx64 ", dut=0x%016" PRIx64 "\n",
      event_name, sequence, event_pc, field, ref, dut);
  return false;
}

bool isa_difftest_check_observation(
    const riscv_difftest_observation_t *ref,
    const riscv_difftest_observation_t *dut,
    const char *event_name, vaddr_t event_pc) {
  if (ref == NULL || dut == NULL || event_name == NULL) return false;
  if (ref->abi_version != RISCV_DIFFTEST_ABI_VERSION ||
      dut->abi_version != RISCV_DIFFTEST_ABI_VERSION ||
      ref->struct_size != sizeof(*ref) || dut->struct_size != sizeof(*dut) ||
      ref->sequence != dut->sequence) {
    printf("DiffTest %s at pc=" FMT_WORD ": invalid observation header\n",
        event_name, event_pc);
    return false;
  }
  if (ref->state.valid_fields != RISCV_DIFFTEST_RV32E_STATE_FIELDS ||
      dut->state.valid_fields != RISCV_DIFFTEST_RV32E_STATE_FIELDS ||
      ref->state.gpr_valid_mask != RISCV_DIFFTEST_RV32E_GPR_MASK ||
      dut->state.gpr_valid_mask != RISCV_DIFFTEST_RV32E_GPR_MASK ||
      ref->state.reserved_tail != 0 || dut->state.reserved_tail != 0) {
    printf("DiffTest %s sequence=%" PRIu64 " at pc=" FMT_WORD
        ": invalid RV32E field mask or reserved data\n",
        event_name, dut->sequence, event_pc);
    return false;
  }

  for (size_t i = 0; i < 16; i++) {
    if (!check_u32(event_name, dut->sequence, event_pc, "gpr",
          ref->state.gpr[i], dut->state.gpr[i])) {
      printf("DiffTest mismatching GPR index: %zu\n", i);
      return false;
    }
  }
  for (size_t i = 16; i < RISCV_DIFFTEST_MAX_GPRS; i++) {
    if (ref->state.gpr[i] != 0 || dut->state.gpr[i] != 0) {
      printf("DiffTest %s sequence=%" PRIu64 " at pc=" FMT_WORD
          ": nonzero unimplemented GPR slot %zu\n",
          event_name, dut->sequence, event_pc, i);
      return false;
    }
  }
  for (size_t i = 0; i < RISCV_DIFFTEST_FPRS; i++) {
    if (!check_u64(event_name, dut->sequence, event_pc, "fpr",
          ref->state.fpr[i], dut->state.fpr[i])) {
      printf("DiffTest mismatching FPR index: %zu\n", i);
      return false;
    }
  }

#define CHECK_U32(name) \
  do { \
    if (!check_u32(event_name, dut->sequence, event_pc, #name, \
          ref->state.name, dut->state.name)) return false; \
  } while (0)
  CHECK_U32(pc);
  CHECK_U32(fcsr);
  CHECK_U32(priv);
  CHECK_U32(mstatus);
  CHECK_U32(mtvec);
  CHECK_U32(mepc);
  CHECK_U32(mcause);
  CHECK_U32(satp);
#undef CHECK_U32
  return true;
}
