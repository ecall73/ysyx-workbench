#include <isa.h>

static bool check_u32(const char *event_name, uint64_t sequence,
    vaddr_t event_pc, const char *field, uint32_t ref, uint32_t dut) {
  if (ref == dut) return true;
  printf("DiffTest %s sequence=%" PRIu64 " at pc=" FMT_WORD
      ": %s mismatch, ref=" FMT_WORD ", dut=" FMT_WORD "\n",
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
  if (ref->state.valid_fields != RISCV_DIFFTEST_RV32IMAC_STATE_FIELDS ||
      dut->state.valid_fields != RISCV_DIFFTEST_RV32IMAC_STATE_FIELDS ||
      ref->state.gpr_valid_mask != RISCV_DIFFTEST_RV32IMAC_GPR_MASK ||
      dut->state.gpr_valid_mask != RISCV_DIFFTEST_RV32IMAC_GPR_MASK) {
    printf("DiffTest %s sequence=%" PRIu64 " at pc=" FMT_WORD
        ": invalid RV32IMAC field mask\n",
        event_name, dut->sequence, event_pc);
    return false;
  }

  for (size_t i = 0; i < RISCV_DIFFTEST_MAX_GPRS; i++) {
    if (!check_u32(event_name, dut->sequence, event_pc, "gpr",
          ref->state.gpr[i], dut->state.gpr[i])) {
      printf("DiffTest mismatching GPR index: %zu\n", i);
      return false;
    }
  }
#define CHECK_U32(name) \
  do { \
    if (!check_u32(event_name, dut->sequence, event_pc, #name, \
          ref->state.name, dut->state.name)) return false; \
  } while (0)
  CHECK_U32(pc);
  CHECK_U32(priv);
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
#undef CHECK_U32
  return true;
}
