/***************************************************************************************
* Copyright (c) 2014-2024 Zihao Yu, Nanjing University
*
* NEMU is licensed under Mulan PSL v2.
* You can use this software according to the terms and conditions of the Mulan PSL v2.
* You may obtain a copy of the License at:
*          http://license.coscl.org.cn/MulanPSL2
*
* THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
* EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
* MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
* See the Mulan PSL v2 for more details.
***************************************************************************************/

#include "mmu.h"
#include "sim.h"
#include "../../include/common.h"
#include <difftest-def.h>
#include <cstdio>
#include <cstring>

#ifndef SPIKE_DIFFTEST_IMPLEMENTATION_ID
#define SPIKE_DIFFTEST_IMPLEMENTATION_ID "spike-unidentified"
#endif

static std::vector<std::pair<reg_t, abstract_device_t*>> difftest_plugin_devices;
static std::vector<std::string> difftest_htif_args;
static std::vector<std::pair<reg_t, mem_t*>> difftest_mem(
    1, std::make_pair(reg_t(DRAM_BASE), new mem_t(CONFIG_MSIZE)));
static debug_module_config_t difftest_dm_config = {
  .progbufsize = 2,
  .max_sba_data_width = 0,
  .require_authentication = false,
  .abstract_rti = 0,
  .support_hasel = true,
  .support_abstract_csr_access = true,
  .support_abstract_fpr_access = true,
  .support_haltgroups = true,
  .support_impebreak = true
};

static const uint64_t provided_capabilities =
    RISCV_DIFFTEST_RV32GC_REQUIRED_CAPS;
static const uint64_t supported_isa_features =
    RISCV_DIFFTEST_RV32GC_FEATURES;
static const reg_t passive_pending_mask =
    MIP_MSIP | MIP_SSIP | MIP_MTIP | MIP_STIP;

static sim_t* s = nullptr;
static processor_t *p = nullptr;
static state_t *state = nullptr;
static uint64_t expected_sequence = 0;
static uint64_t last_sequence = UINT64_MAX;

static bool profile_is_rv32gc(const riscv_difftest_profile_t *profile) {
  return profile->profile_id == RISCV_DIFFTEST_PROFILE_RV32GC_NEMU_SPIKE &&
      profile->xlen == 32 && profile->gpr_count == 32 &&
      profile->fp_kind == RISCV_DIFFTEST_FP_D &&
      profile->privilege_modes == (RISCV_DIFFTEST_PRIV_U |
          RISCV_DIFFTEST_PRIV_S | RISCV_DIFFTEST_PRIV_M) &&
      profile->isa_features == RISCV_DIFFTEST_RV32GC_FEATURES &&
      profile->reset_pc == DRAM_BASE &&
      profile->memory_map == RISCV_DIFFTEST_MEMORY_MAP_NEMU;
}

static int validate_profile(const riscv_difftest_profile_t *profile) {
  if (profile == nullptr) return RISCV_DIFFTEST_BAD_ARGUMENT;
  if (profile->abi_version != RISCV_DIFFTEST_ABI_VERSION) {
    return RISCV_DIFFTEST_BAD_ABI_VERSION;
  }
  if (profile->struct_size != sizeof(*profile)) {
    return RISCV_DIFFTEST_BAD_STRUCT_SIZE;
  }
  if (profile->required_capabilities & ~provided_capabilities) {
    return RISCV_DIFFTEST_UNSUPPORTED_CAPABILITY;
  }
  if (profile->isa_features & ~supported_isa_features) {
    return RISCV_DIFFTEST_UNSUPPORTED_PROFILE;
  }
  return profile_is_rv32gc(profile) ? RISCV_DIFFTEST_OK
                                    : RISCV_DIFFTEST_UNSUPPORTED_PROFILE;
}

static void create_spike() {
  const char *isa = "RV32IMAFDC_Zicsr_Zifencei_Zicntr_Sstc_Svadu";
  cfg_t *cfg = new cfg_t(/*default_initrd_bounds=*/std::make_pair((reg_t)0, (reg_t)0),
            /*default_bootargs=*/nullptr,
            /*default_isa=*/isa,
            /*default_priv=*/DEFAULT_PRIV,
            /*default_varch=*/DEFAULT_VARCH,
            /*default_misaligned=*/false,
            /*default_endianness=*/endianness_little,
            /*default_pmpregions=*/0,
            /*default_mem_layout=*/std::vector<mem_cfg_t>(),
            /*default_hartids=*/std::vector<size_t>(1),
            /*default_real_time_clint=*/false,
            /*default_trigger_count=*/4);
  s = new sim_t(cfg, false,
      difftest_mem, difftest_plugin_devices, difftest_htif_args,
      difftest_dm_config, nullptr, false, NULL,
      false, NULL, true);
  s->diff_init(0);
  expected_sequence = 0;
  last_sequence = UINT64_MAX;
}

static reg_t read_csr(reg_t address) {
  auto it = state->csrmap.find(address);
  assert(it != state->csrmap.end());
  return it->second->read();
}

static void write_csr(reg_t address, reg_t value) {
  auto it = state->csrmap.find(address);
  assert(it != state->csrmap.end());
  it->second->write(value);
}

static void build_arch_state(riscv_difftest_arch_state_t *dest) {
  std::memset(dest, 0, sizeof(*dest));
  dest->valid_fields = RISCV_DIFFTEST_RV32GC_STATE_FIELDS;
  dest->gpr_valid_mask = UINT32_MAX;
  dest->pc = state->pc;
  for (size_t i = 0; i < RISCV_DIFFTEST_MAX_GPRS; i++) {
    dest->gpr[i] = state->XPR[i];
  }
  dest->fcsr = (state->frm->read() << 5) | state->fflags->read();
  dest->priv = state->prv;
  for (size_t i = 0; i < RISCV_DIFFTEST_FPRS; i++) {
    dest->fpr[i] = state->FPR[i].v[0];
  }
  dest->mcycle = state->mcycle->read();
  dest->minstret = state->minstret->read();
  dest->mstatus = state->mstatus->read();
  dest->mtvec = state->mtvec->read();
  dest->mepc = state->mepc->read();
  dest->mcause = state->mcause->read();
  dest->mtval = state->mtval->read();
  dest->medeleg = state->medeleg->read();
  dest->mideleg = state->mideleg->read();
  dest->mie = state->mie->read();
  dest->stvec = state->stvec->read();
  dest->sepc = state->sepc->read();
  dest->scause = state->scause->read();
  dest->stval = state->stval->read();
  dest->sscratch = read_csr(CSR_SSCRATCH);
  dest->satp = state->satp->read();
  dest->mscratch = read_csr(CSR_MSCRATCH);
  dest->menvcfgh = state->menvcfg->read() >> 32;
  dest->mcounteren = state->mcounteren->read();
  dest->scounteren = state->scounteren->read();
  dest->mcountinhibit = read_csr(CSR_MCOUNTINHIBIT);
}

static void build_observation(riscv_difftest_observation_t *dest) {
  std::memset(dest, 0, sizeof(*dest));
  dest->abi_version = RISCV_DIFFTEST_ABI_VERSION;
  dest->struct_size = sizeof(*dest);
  dest->sequence = last_sequence;
  build_arch_state(&dest->state);
}

static int validate_sync_state(const riscv_difftest_sync_state_t *sync) {
  if (sync == nullptr) return RISCV_DIFFTEST_BAD_ARGUMENT;
  if (sync->abi_version != RISCV_DIFFTEST_ABI_VERSION) {
    return RISCV_DIFFTEST_BAD_ABI_VERSION;
  }
  if (sync->struct_size != sizeof(*sync)) {
    return RISCV_DIFFTEST_BAD_STRUCT_SIZE;
  }
  if (sync->state.valid_fields == 0 ||
      (sync->state.valid_fields & ~RISCV_DIFFTEST_RV32GC_STATE_FIELDS) != 0 ||
      ((sync->state.valid_fields & RISCV_DIFFTEST_FIELD_GPR) == 0 &&
       sync->state.gpr_valid_mask != 0) ||
      ((sync->state.gpr_valid_mask & 1u) != 0 &&
       sync->state.gpr[0] != 0) ||
      ((sync->state.valid_fields & RISCV_DIFFTEST_FIELD_PRIV) &&
       sync->state.priv != PRV_U && sync->state.priv != PRV_S &&
       sync->state.priv != PRV_M)) {
    return RISCV_DIFFTEST_BAD_STATE;
  }
  return RISCV_DIFFTEST_OK;
}

static int apply_sync_state(const riscv_difftest_sync_state_t *sync) {
  int status = validate_sync_state(sync);
  if (status != RISCV_DIFFTEST_OK) return status;

  if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_GPR) {
    for (size_t i = 0; i < RISCV_DIFFTEST_MAX_GPRS; i++) {
      if (sync->state.gpr_valid_mask & (UINT32_C(1) << i)) {
        state->XPR.write(i, (sword_t)sync->state.gpr[i]);
      }
    }
  }
  if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_PC) {
    state->pc = sync->state.pc;
  }

  reg_t synchronized_mstatus = state->mstatus->read();
  if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_MSTATUS) {
    synchronized_mstatus = sync->state.mstatus;
  }
  if (sync->state.valid_fields &
      (RISCV_DIFFTEST_FIELD_FCSR | RISCV_DIFFTEST_FIELD_FPR)) {
    // Spike gates floating-point state writes with mstatus.FS. Enable it only
    // for the restore, then restore the synchronized or preexisting mstatus.
    state->mstatus->write(synchronized_mstatus |
        (MSTATUS_FS & (MSTATUS_FS >> 1)));
    if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_FCSR) {
      state->fflags->write(sync->state.fcsr & 0x1f);
      state->frm->write((sync->state.fcsr >> 5) & 0x7);
    }
    if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_FPR) {
      for (size_t i = 0; i < RISCV_DIFFTEST_FPRS; i++) {
        freg_t value = {};
        value.v[0] = sync->state.fpr[i];
        value.v[1] = UINT64_MAX;
        state->FPR.write(i, value);
      }
    }
    state->mstatus->write(synchronized_mstatus);
  }

  if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_MCYCLE) {
    state->mcycle->bump(sync->state.mcycle - state->mcycle->read());
  }
  if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_MINSTRET) {
    state->minstret->bump(sync->state.minstret - state->minstret->read());
  }
#define APPLY_CSR(bit, object, value) \
  do { \
    if (sync->state.valid_fields & (bit)) (object)->write(value); \
  } while (0)
  APPLY_CSR(RISCV_DIFFTEST_FIELD_MSTATUS, state->mstatus,
      sync->state.mstatus);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_MTVEC, state->mtvec, sync->state.mtvec);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_MEPC, state->mepc, sync->state.mepc);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_MCAUSE, state->mcause, sync->state.mcause);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_MTVAL, state->mtval, sync->state.mtval);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_MEDELEG, state->medeleg,
      sync->state.medeleg);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_MIDELEG, state->mideleg,
      sync->state.mideleg);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_MIE, state->mie, sync->state.mie);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_STVEC, state->stvec, sync->state.stvec);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_SEPC, state->sepc, sync->state.sepc);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_SCAUSE, state->scause, sync->state.scause);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_STVAL, state->stval, sync->state.stval);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_SATP, state->satp, sync->state.satp);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_MCOUNTEREN, state->mcounteren,
      sync->state.mcounteren);
  APPLY_CSR(RISCV_DIFFTEST_FIELD_SCOUNTEREN, state->scounteren,
      sync->state.scounteren);
#undef APPLY_CSR
  if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_SSCRATCH) {
    write_csr(CSR_SSCRATCH, sync->state.sscratch);
  }
  if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_MSCRATCH) {
    write_csr(CSR_MSCRATCH, sync->state.mscratch);
  }
  if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_MENVCFGH) {
    write_csr(CSR_MENVCFGH, sync->state.menvcfgh);
  }
  if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_MCOUNTINHIBIT) {
    write_csr(CSR_MCOUNTINHIBIT, sync->state.mcountinhibit);
  }
  if (sync->state.valid_fields & RISCV_DIFFTEST_FIELD_PRIV) {
    p->set_privilege(sync->state.priv);
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

void sim_t::diff_init(int port) {
  (void)port;
  p = get_core("0");
  state = p->get_state();
}

void sim_t::diff_step(uint64_t n) {
  while (n-- > 0) {
    state->mip->backdoor_write_with_mask(passive_pending_mask, 0);
    if (p->is_waiting_for_interrupt()) p->resume_from_wfi();
    step(1);
  }
}

void sim_t::diff_memcpy(reg_t dest, void* src, size_t n) {
  assert(!difftest_mem.empty());
  const auto& region = difftest_mem.front();
  assert(dest >= region.first &&
      region.second->store(dest - region.first, n,
        static_cast<const uint8_t *>(src)));
}

extern "C" {

__EXPORT int difftest_query_interface(uint32_t requested_abi,
    riscv_difftest_interface_t *interface) {
  if (interface == nullptr) return RISCV_DIFFTEST_BAD_ARGUMENT;
  if (requested_abi != RISCV_DIFFTEST_ABI_VERSION ||
      interface->abi_version != requested_abi) {
    return RISCV_DIFFTEST_BAD_ABI_VERSION;
  }
  if (interface->struct_size != sizeof(*interface)) {
    return RISCV_DIFFTEST_BAD_STRUCT_SIZE;
  }
  std::memset(interface, 0, sizeof(*interface));
  interface->abi_version = RISCV_DIFFTEST_ABI_VERSION;
  interface->struct_size = sizeof(*interface);
  interface->provided_capabilities = provided_capabilities;
  interface->supported_isa_features = supported_isa_features;
  interface->observation_size = sizeof(riscv_difftest_observation_t);
  interface->sync_state_size = sizeof(riscv_difftest_sync_state_t);
  interface->arch_step_size = sizeof(riscv_difftest_arch_step_t);
  interface->async_intr_size = sizeof(riscv_difftest_async_intr_t);
  interface->profile_size = sizeof(riscv_difftest_profile_t);
  interface->max_gpr_count = RISCV_DIFFTEST_MAX_GPRS;
  std::snprintf(interface->implementation_id,
      sizeof(interface->implementation_id), "%s",
      SPIKE_DIFFTEST_IMPLEMENTATION_ID);
  return RISCV_DIFFTEST_OK;
}

__EXPORT int difftest_init_profile(const riscv_difftest_profile_t *profile) {
  int status = validate_profile(profile);
  if (status != RISCV_DIFFTEST_OK) return status;
  if (s != nullptr) return RISCV_DIFFTEST_BAD_STATE;
  difftest_htif_args.push_back("");
  create_spike();
  return RISCV_DIFFTEST_OK;
}

__EXPORT int difftest_get_observation(riscv_difftest_observation_t *observation) {
  if (observation == nullptr) return RISCV_DIFFTEST_BAD_ARGUMENT;
  if (state == nullptr) return RISCV_DIFFTEST_BAD_STATE;
  build_observation(observation);
  return RISCV_DIFFTEST_OK;
}

__EXPORT int difftest_set_sync_state(const riscv_difftest_sync_state_t *sync) {
  if (state == nullptr) return RISCV_DIFFTEST_BAD_STATE;
  return apply_sync_state(sync);
}

__EXPORT int difftest_arch_step(const riscv_difftest_arch_step_t *event,
    const riscv_difftest_sync_state_t *sync,
    riscv_difftest_observation_t *observation) {
  if (event == nullptr || observation == nullptr || state == nullptr) {
    return RISCV_DIFFTEST_BAD_ARGUMENT;
  }
  int status = validate_event_header(event->abi_version, event->struct_size,
      sizeof(*event), event->sequence);
  if (status != RISCV_DIFFTEST_OK) return status;
  if ((event->instruction_valid != 0 && event->instruction_valid != 1) ||
      (event->instruction_valid && event->instruction_length != 2 &&
       event->instruction_length != 4) ||
      (!event->instruction_valid &&
       (event->instruction_length != 0 || event->instruction_bits != 0)) ||
      uint32_t(state->pc) != event->instruction_pc) {
    std::fprintf(stderr,
        "DiffTest bad ARCH_STEP: seq=%" PRIu64 " expected=%" PRIu64
        " pc=0x%08" PRIx64 " ref_pc=0x%08" PRIx64
        " bits=0x%08x len=%u valid=%u disposition=%u skip=%u\n",
        event->sequence, expected_sequence, uint64_t(event->instruction_pc),
        uint64_t(uint32_t(state->pc)), event->instruction_bits,
        event->instruction_length,
        event->instruction_valid, event->disposition, event->skip_reason);
    return RISCV_DIFFTEST_BAD_EVENT;
  }

  if (event->disposition == RISCV_DIFFTEST_STEP_EXECUTE) {
    if (sync != nullptr || event->skip_reason != RISCV_DIFFTEST_SKIP_NONE) {
      return RISCV_DIFFTEST_BAD_EVENT;
    }
    s->diff_step(1);
  } else if (event->disposition == RISCV_DIFFTEST_STEP_SKIP_REF) {
    if (sync == nullptr || event->skip_reason <= RISCV_DIFFTEST_SKIP_NONE ||
        event->skip_reason > RISCV_DIFFTEST_SKIP_PROFILE_OWNED_STATIC) {
      return RISCV_DIFFTEST_BAD_EVENT;
    }
    uint32_t expected_gpr_mask;
    status = riscv_difftest_skip_gpr_mask(event->skip_reason,
        event->instruction_bits, event->instruction_length,
        &expected_gpr_mask);
    if (status != RISCV_DIFFTEST_OK) return status;
    uint64_t expected_fields =
        riscv_difftest_skip_sync_fields(
            RISCV_DIFFTEST_PROFILE_RV32GC_NEMU_SPIKE, event->skip_reason);
    if (expected_gpr_mask == 0) {
      expected_fields &= ~RISCV_DIFFTEST_FIELD_GPR;
    }
    if (sync->state.valid_fields != expected_fields ||
        sync->state.gpr_valid_mask != expected_gpr_mask) {
      return RISCV_DIFFTEST_BAD_STATE;
    }
    status = apply_sync_state(sync);
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
  if (event == nullptr || observation == nullptr || state == nullptr) {
    return RISCV_DIFFTEST_BAD_ARGUMENT;
  }
  int status = validate_event_header(event->abi_version, event->struct_size,
      sizeof(*event), event->sequence);
  if (status != RISCV_DIFFTEST_OK) return status;
  if (event->pretrap_pc != uint32_t(state->pc) ||
      (event->interrupt_code != 1 && event->interrupt_code != 3 &&
       event->interrupt_code != 5 && event->interrupt_code != 7)) {
    return RISCV_DIFFTEST_BAD_EVENT;
  }

  trap_t trap((UINT64_C(1) << 31) | event->interrupt_code);
  p->take_trap_public(trap, state->pc);
  last_sequence = event->sequence;
  expected_sequence++;
  build_observation(observation);
  return RISCV_DIFFTEST_OK;
}

__EXPORT int difftest_load_memory(uint32_t addr, const void *buf, size_t n) {
  if (s == nullptr) return RISCV_DIFFTEST_BAD_STATE;
  if ((buf == nullptr && n != 0) ||
      uint64_t(n) > UINT64_C(1) + UINT32_MAX - uint64_t(addr)) {
    return RISCV_DIFFTEST_BAD_ARGUMENT;
  }
  if (n == 0) return RISCV_DIFFTEST_OK;
  s->diff_memcpy(addr, const_cast<void *>(buf), n);
  return RISCV_DIFFTEST_OK;
}

}
