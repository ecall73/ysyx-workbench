#include <cpu/cpu.h>
#include <difftest-def.h>
#include <isa.h>
#include <memory/paddr.h>
#include <stdio.h>
#include <string.h>
#include <utils.h>

#include "../local-include/difftest.h"

static bool profile_initialized = false;
static uint32_t active_profile_id = 0;
static uint64_t expected_sequence = 0;
static uint64_t last_sequence = UINT64_MAX;

static const uint64_t provided_capabilities =
    RISCV_DIFFTEST_RV32IMAC_REQUIRED_CAPS |
    RISCV_DIFFTEST_CAP_YSYXSOC_MEMORY_MAP;

static int validate_profile(const riscv_difftest_profile_t *profile) {
  if (profile == NULL) return RISCV_DIFFTEST_BAD_ARGUMENT;
  if (profile->abi_version != RISCV_DIFFTEST_ABI_VERSION) {
    return RISCV_DIFFTEST_BAD_ABI_VERSION;
  }
  if (profile->struct_size != sizeof(*profile)) {
    return RISCV_DIFFTEST_BAD_STRUCT_SIZE;
  }
  uint64_t required_capabilities;
  if (profile->profile_id == RISCV_DIFFTEST_PROFILE_RV32IMAC_NPC_NEMU) {
#ifdef CONFIG_RVE
    return RISCV_DIFFTEST_UNSUPPORTED_PROFILE;
#else
    required_capabilities = RISCV_DIFFTEST_RV32IMAC_REQUIRED_CAPS;
#endif
  } else {
    return RISCV_DIFFTEST_UNSUPPORTED_PROFILE;
  }
  if (profile->memory_map == RISCV_DIFFTEST_MEMORY_MAP_YSYXSOC) {
    required_capabilities |= RISCV_DIFFTEST_CAP_YSYXSOC_MEMORY_MAP;
  } else if (profile->memory_map != RISCV_DIFFTEST_MEMORY_MAP_NEMU) {
    return RISCV_DIFFTEST_UNSUPPORTED_PROFILE;
  }
  if (profile->required_capabilities & ~provided_capabilities) {
    return RISCV_DIFFTEST_UNSUPPORTED_CAPABILITY;
  }
  if (profile->xlen != 32 || profile->gpr_count != 32 ||
      profile->fp_kind != RISCV_DIFFTEST_FP_NONE ||
      profile->privilege_modes !=
          (RISCV_DIFFTEST_PRIV_U | RISCV_DIFFTEST_PRIV_S |
           RISCV_DIFFTEST_PRIV_M) ||
      profile->isa_features != RISCV_DIFFTEST_RV32IMAC_FEATURES ||
      profile->required_capabilities != required_capabilities) {
    return RISCV_DIFFTEST_UNSUPPORTED_PROFILE;
  }
  return RISCV_DIFFTEST_OK;
}

static int validate_event_header(uint32_t abi_version, uint32_t struct_size,
    uint32_t expected_size, uint64_t sequence) {
  if (abi_version != RISCV_DIFFTEST_ABI_VERSION) {
    return RISCV_DIFFTEST_BAD_ABI_VERSION;
  }
  if (struct_size != expected_size) return RISCV_DIFFTEST_BAD_STRUCT_SIZE;
  if (sequence != expected_sequence) return RISCV_DIFFTEST_BAD_SEQUENCE;
  return RISCV_DIFFTEST_OK;
}

static void build_observation(riscv_difftest_observation_t *observation) {
  riscv_difftest_build_observation(observation, active_profile_id,
      last_sequence, &cpu);
}

__EXPORT int difftest_query_interface(uint32_t requested_abi,
    riscv_difftest_interface_t *interface) {
  if (interface == NULL) return RISCV_DIFFTEST_BAD_ARGUMENT;
  if (requested_abi != RISCV_DIFFTEST_ABI_VERSION ||
      interface->abi_version != requested_abi) {
    return RISCV_DIFFTEST_BAD_ABI_VERSION;
  }
  if (interface->struct_size != sizeof(*interface)) {
    return RISCV_DIFFTEST_BAD_STRUCT_SIZE;
  }

  memset(interface, 0, sizeof(*interface));
  interface->abi_version = RISCV_DIFFTEST_ABI_VERSION;
  interface->struct_size = sizeof(*interface);
  interface->provided_capabilities = provided_capabilities;
  interface->supported_isa_features = 0;
#ifndef CONFIG_RVE
  interface->supported_isa_features |= RISCV_DIFFTEST_RV32IMAC_FEATURES;
#endif
  snprintf(interface->implementation_id, sizeof(interface->implementation_id),
      "nemu-rv32-ref-abi2-rv32imac-svade");
  interface->observation_size = sizeof(riscv_difftest_observation_t);
  interface->sync_state_size = sizeof(riscv_difftest_sync_state_t);
  interface->arch_step_size = sizeof(riscv_difftest_arch_step_t);
  interface->async_intr_size = sizeof(riscv_difftest_async_intr_t);
  interface->profile_size = sizeof(riscv_difftest_profile_t);
  interface->max_gpr_count = RISCV_DIFFTEST_MAX_GPRS;
  return RISCV_DIFFTEST_OK;
}

__EXPORT int difftest_init_profile(const riscv_difftest_profile_t *profile) {
  int status = validate_profile(profile);
  if (status != RISCV_DIFFTEST_OK) return status;
  if (profile_initialized) return RISCV_DIFFTEST_BAD_STATE;
  if (!difftest_select_memory_map(profile->memory_map, profile->reset_pc)) {
    return RISCV_DIFFTEST_UNSUPPORTED_PROFILE;
  }

  void init_mem(void);
  init_mem();
  init_isa();
  cpu.pc = profile->reset_pc;
  nemu_state.state = NEMU_STOP;
  active_profile_id = profile->profile_id;
  expected_sequence = 0;
  last_sequence = UINT64_MAX;
  profile_initialized = true;
  return RISCV_DIFFTEST_OK;
}

__EXPORT int difftest_get_observation(
    riscv_difftest_observation_t *observation) {
  if (observation == NULL) return RISCV_DIFFTEST_BAD_ARGUMENT;
  if (!profile_initialized) return RISCV_DIFFTEST_BAD_STATE;
  build_observation(observation);
  return RISCV_DIFFTEST_OK;
}

__EXPORT int difftest_set_sync_state(
    const riscv_difftest_sync_state_t *sync) {
  if (!profile_initialized) return RISCV_DIFFTEST_BAD_STATE;
  if (sync == NULL) return RISCV_DIFFTEST_BAD_ARGUMENT;
  if (sync->state.valid_fields != RISCV_DIFFTEST_RV32IMAC_STATE_FIELDS ||
      sync->state.gpr_valid_mask != RISCV_DIFFTEST_RV32IMAC_GPR_MASK) {
    return RISCV_DIFFTEST_BAD_STATE;
  }
  return riscv_difftest_apply_sync_state(&cpu, active_profile_id, sync);
}

__EXPORT int difftest_arch_step(const riscv_difftest_arch_step_t *event,
    const riscv_difftest_sync_state_t *sync,
    riscv_difftest_observation_t *observation) {
  if (event == NULL || observation == NULL) {
    return RISCV_DIFFTEST_BAD_ARGUMENT;
  }
  if (!profile_initialized ||
      active_profile_id != RISCV_DIFFTEST_PROFILE_RV32IMAC_NPC_NEMU) {
    return RISCV_DIFFTEST_BAD_STATE;
  }
  int status = validate_event_header(event->abi_version, event->struct_size,
      sizeof(*event), event->sequence);
  if (status != RISCV_DIFFTEST_OK) return status;
  bool valid_length =
      event->instruction_length == 2 || event->instruction_length == 4;
  bool valid_encoding = event->instruction_length == 2
      ? (event->instruction_bits & 0xffff0003u) != 0x00000003u &&
        (event->instruction_bits & 0xffff0000u) == 0
      : (event->instruction_bits & 0x3u) == 0x3u;
  if (event->instruction_valid > 1 || !valid_length ||
      (event->instruction_valid && !valid_encoding) ||
      event->instruction_pc != cpu.pc) {
    Log("reject ARCH_STEP metadata: sequence=%" PRIu64
        " dut_pc=" FMT_WORD " ref_pc=" FMT_WORD
        " valid=%u length=%u",
        event->sequence, event->instruction_pc, cpu.pc,
        event->instruction_valid, event->instruction_length);
    return RISCV_DIFFTEST_BAD_EVENT;
  }

  bool direct_fetch = isa_mmu_check(event->instruction_pc,
      event->instruction_length, MEM_TYPE_IFETCH) == MMU_DIRECT;
  if (event->instruction_valid && direct_fetch) {
    word_t instruction = 0;
    if (!paddr_try_read(event->instruction_pc, event->instruction_length,
          &instruction)) {
      Log("reject ARCH_STEP instruction fetch: sequence=%" PRIu64
          " pc=" FMT_WORD, event->sequence, event->instruction_pc);
      return RISCV_DIFFTEST_BAD_EVENT;
    }
    uint32_t instruction_mask = event->instruction_length == 2
        ? UINT32_C(0x0000ffff) : UINT32_MAX;
    if ((instruction & instruction_mask) != event->instruction_bits) {
      Log("reject ARCH_STEP instruction mismatch: sequence=%" PRIu64
          " pc=" FMT_WORD " dut=0x%08x ref=0x%08x",
          event->sequence, event->instruction_pc,
          event->instruction_bits, instruction);
      return RISCV_DIFFTEST_BAD_EVENT;
    }
  }

  if (event->disposition == RISCV_DIFFTEST_STEP_EXECUTE) {
    if (sync != NULL || event->skip_reason != RISCV_DIFFTEST_SKIP_NONE) {
      return RISCV_DIFFTEST_BAD_EVENT;
    }
    cpu_exec(1);
    if (nemu_state.state == NEMU_ABORT || nemu_state.state == NEMU_END ||
        nemu_state.state == NEMU_QUIT) {
      return RISCV_DIFFTEST_INTERNAL_ERROR;
    }
  } else if (event->disposition == RISCV_DIFFTEST_STEP_SKIP_REF) {
    if (!event->instruction_valid || sync == NULL ||
        event->skip_reason <= RISCV_DIFFTEST_SKIP_NONE ||
        event->skip_reason > RISCV_DIFFTEST_SKIP_PROFILE_OWNED_STATIC) {
      return RISCV_DIFFTEST_BAD_EVENT;
    }
    uint32_t expected_gpr_mask = 0;
    status = riscv_difftest_skip_gpr_mask(event->skip_reason,
        event->instruction_bits, event->instruction_length,
        &expected_gpr_mask);
    if (status != RISCV_DIFFTEST_OK ||
        (expected_gpr_mask & ~RISCV_DIFFTEST_RV32IMAC_GPR_MASK) != 0) {
      return RISCV_DIFFTEST_BAD_EVENT;
    }
    uint64_t expected_fields = riscv_difftest_skip_sync_fields(
        active_profile_id, event->skip_reason);
    if (expected_gpr_mask == 0) {
      expected_fields &= ~RISCV_DIFFTEST_FIELD_GPR;
    }
    if (sync->state.valid_fields != expected_fields ||
        sync->state.gpr_valid_mask != expected_gpr_mask) {
      return RISCV_DIFFTEST_BAD_STATE;
    }
    status = riscv_difftest_apply_sync_state(&cpu, active_profile_id, sync);
    if (status != RISCV_DIFFTEST_OK) return status;
  } else {
    return RISCV_DIFFTEST_BAD_EVENT;
  }

  last_sequence = event->sequence;
  expected_sequence++;
  build_observation(observation);
  return RISCV_DIFFTEST_OK;
}

__EXPORT int difftest_async_intr(const riscv_difftest_async_intr_t *event,
    riscv_difftest_observation_t *observation) {
  if (event == NULL || observation == NULL) {
    return RISCV_DIFFTEST_BAD_ARGUMENT;
  }
  if (!profile_initialized ||
      active_profile_id != RISCV_DIFFTEST_PROFILE_RV32IMAC_NPC_NEMU) {
    return RISCV_DIFFTEST_UNSUPPORTED_CAPABILITY;
  }
  int status = validate_event_header(event->abi_version, event->struct_size,
      sizeof(*event), event->sequence);
  if (status != RISCV_DIFFTEST_OK) return status;
  if (event->pretrap_pc != cpu.pc ||
      (event->interrupt_code != 1 && event->interrupt_code != 3 &&
       event->interrupt_code != 5 && event->interrupt_code != 7)) {
    return RISCV_DIFFTEST_BAD_EVENT;
  }

  cpu.pc = isa_raise_intr(UINT32_C(0x80000000) | event->interrupt_code,
      event->pretrap_pc);
  last_sequence = event->sequence;
  expected_sequence++;
  build_observation(observation);
  return RISCV_DIFFTEST_OK;
}
