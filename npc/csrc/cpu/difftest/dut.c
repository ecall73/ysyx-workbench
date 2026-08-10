#include <dlfcn.h>

#include <cpu/cpu.h>
#include <difftest-def.h>
#include <isa.h>
#include <platform/platform.h>
#include <utils.h>

#ifdef CONFIG_DIFFTEST

static difftest_load_memory_t ref_load_memory = NULL;
static difftest_query_interface_t ref_query_interface = NULL;
static difftest_init_profile_t ref_init_profile = NULL;
static difftest_get_observation_t ref_get_observation = NULL;
static difftest_set_sync_state_t ref_set_sync_state = NULL;
static difftest_arch_step_t ref_arch_step = NULL;
static difftest_async_intr_t ref_async_intr = NULL;

static riscv_difftest_profile_t profile;
static riscv_difftest_observation_t last_ref_observation;
static uint64_t next_sequence = 0;

static const char *difftest_status_name(int status) {
  switch (status) {
    case RISCV_DIFFTEST_OK: return "ok";
    case RISCV_DIFFTEST_BAD_ARGUMENT: return "bad argument";
    case RISCV_DIFFTEST_BAD_ABI_VERSION: return "bad ABI version";
    case RISCV_DIFFTEST_BAD_STRUCT_SIZE: return "bad structure size";
    case RISCV_DIFFTEST_UNSUPPORTED_CAPABILITY: return "unsupported capability";
    case RISCV_DIFFTEST_UNSUPPORTED_PROFILE: return "unsupported profile";
    case RISCV_DIFFTEST_BAD_SEQUENCE: return "bad event sequence";
    case RISCV_DIFFTEST_BAD_EVENT: return "bad architecture event";
    case RISCV_DIFFTEST_BAD_STATE: return "bad architecture state";
    case RISCV_DIFFTEST_INTERNAL_ERROR: return "reference internal error";
    default: return "unknown status";
  }
}

static void require_ref_status(const char *operation, int status) {
  Assert(status == RISCV_DIFFTEST_OK,
      "DiffTest reference %s failed: status=%d (%s)",
      operation, status, difftest_status_name(status));
}

static void *require_ref_symbol(void *handle, const char *name) {
  void *symbol = dlsym(handle, name);
  Assert(symbol != NULL,
      "DiffTest reference does not implement required RV32 ABI v%u symbol '%s'",
      RISCV_DIFFTEST_ABI_VERSION, name);
  return symbol;
}

static riscv_difftest_profile_t make_profile(void) {
  uint32_t memory_map = platform_difftest_memory_map();
  uint64_t required_capabilities = RISCV_DIFFTEST_RV32IMAC_REQUIRED_CAPS;
  if (memory_map == RISCV_DIFFTEST_MEMORY_MAP_YSYXSOC) {
    required_capabilities |= RISCV_DIFFTEST_CAP_YSYXSOC_MEMORY_MAP;
  }
  return (riscv_difftest_profile_t) {
    .abi_version = RISCV_DIFFTEST_ABI_VERSION,
    .struct_size = sizeof(riscv_difftest_profile_t),
    .profile_id = RISCV_DIFFTEST_PROFILE_RV32IMAC_NPC_NEMU,
    .xlen = 32,
    .gpr_count = 32,
    .fp_kind = RISCV_DIFFTEST_FP_NONE,
    .privilege_modes = RISCV_DIFFTEST_PRIV_U | RISCV_DIFFTEST_PRIV_S |
        RISCV_DIFFTEST_PRIV_M,
    .isa_features = RISCV_DIFFTEST_RV32IMAC_FEATURES,
    .required_capabilities = required_capabilities,
    .reset_pc = platform_reset_pc(),
    .memory_map = memory_map,
  };
}

static void build_arch_state(riscv_difftest_arch_state_t *state) {
  memset(state, 0, sizeof(*state));
  state->valid_fields = RISCV_DIFFTEST_RV32IMAC_STATE_FIELDS;
  state->gpr_valid_mask = RISCV_DIFFTEST_RV32IMAC_GPR_MASK;
  state->pc = cpu.pc;
  for (size_t i = 0; i < profile.gpr_count; i++) {
    state->gpr[i] = cpu.gpr[i];
  }
  state->priv = cpu.priv;
  state->mstatus = cpu.mstatus;
  state->mtvec = cpu.mtvec;
  state->mepc = cpu.mepc;
  state->mcause = cpu.mcause;
  state->mtval = cpu.mtval;
  state->medeleg = cpu.medeleg;
  state->mideleg = cpu.mideleg;
  state->mie = cpu.mie;
  state->stvec = cpu.stvec;
  state->sepc = cpu.sepc;
  state->scause = cpu.scause;
  state->stval = cpu.stval;
  state->sscratch = cpu.sscratch;
  state->satp = cpu.satp;
  state->mscratch = cpu.mscratch;
  state->menvcfgh = cpu.menvcfgh;
  state->mcounteren = cpu.mcounteren;
  state->scounteren = cpu.scounteren;
  state->mcountinhibit = cpu.mcountinhibit;
}

static void build_observation(riscv_difftest_observation_t *observation,
    uint64_t sequence) {
  memset(observation, 0, sizeof(*observation));
  observation->abi_version = RISCV_DIFFTEST_ABI_VERSION;
  observation->struct_size = sizeof(*observation);
  observation->sequence = sequence;
  build_arch_state(&observation->state);
}

static void build_sync_state(riscv_difftest_sync_state_t *sync) {
  memset(sync, 0, sizeof(*sync));
  sync->abi_version = RISCV_DIFFTEST_ABI_VERSION;
  sync->struct_size = sizeof(*sync);
  build_arch_state(&sync->state);
}

static bool check_observation(const riscv_difftest_observation_t *ref,
    uint64_t sequence, const char *event_name, vaddr_t event_pc) {
  riscv_difftest_observation_t dut;
  build_observation(&dut, sequence);
  if (isa_difftest_check_observation(ref, &dut, event_name, event_pc)) {
    return true;
  }
  npc_state.state = NPC_ABORT;
  npc_state.halt_pc = event_pc;
  isa_reg_display();
  return false;
}

static bool memory_access_info(uint32_t inst, uint32_t instruction_length,
    uint32_t *base_register, sword_t *offset, uint32_t *access_length) {
  Assert(base_register != NULL && offset != NULL && access_length != NULL,
      "memory_access_info received a null output pointer");
  *base_register = 0;
  *offset = 0;
  *access_length = 0;

  if (instruction_length == 2) {
    uint32_t quadrant = inst & 0x3u;
    uint32_t funct3 = BITS(inst, 15, 13);
    if (quadrant == 0 && (funct3 == 2 || funct3 == 6)) {
      *base_register = 8u + BITS(inst, 9, 7);
      *offset = (BITS(inst, 5, 5) << 6) |
          (BITS(inst, 12, 10) << 3) | (BITS(inst, 6, 6) << 2);
      *access_length = 4;
      return true;
    }
    if (quadrant == 2 && funct3 == 2 && BITS(inst, 11, 7) != 0) {
      *base_register = 2;
      *offset = (BITS(inst, 3, 2) << 6) |
          (BITS(inst, 12, 12) << 5) | (BITS(inst, 6, 4) << 2);
      *access_length = 4;
      return true;
    }
    if (quadrant == 2 && funct3 == 6) {
      *base_register = 2;
      *offset = (BITS(inst, 8, 7) << 6) | (BITS(inst, 12, 9) << 2);
      *access_length = 4;
      return true;
    }
    return false;
  }

  if (instruction_length != 4) return false;
  uint32_t opcode = inst & 0x7fu;
  uint32_t funct3 = BITS(inst, 14, 12);
  int length = 0;
  if (opcode == 0x03u) {
    switch (funct3) {
      case 0: case 4: length = 1; break;
      case 1: case 5: length = 2; break;
      case 2: length = 4; break;
      default: return false;
    }
    *offset = (sword_t)(int32_t)(inst & 0xfff00000u) >> 20;
  } else if (opcode == 0x23u) {
    switch (funct3) {
      case 0: length = 1; break;
      case 1: length = 2; break;
      case 2: length = 4; break;
      default: return false;
    }
    *offset = (sword_t)(int32_t)((inst & 0xfe000000u) |
        ((inst & 0x00000f80u) << 13)) >> 20;
  } else {
    return false;
  }
  *base_register = BITS(inst, 19, 15);
  *access_length = length;
  return true;
}

static bool csr_instruction_writes(uint32_t inst) {
  uint32_t funct3 = BITS(inst, 14, 12);
  uint32_t source = BITS(inst, 19, 15);
  return funct3 == 1 || funct3 == 5 ||
      ((funct3 == 2 || funct3 == 3 || funct3 == 6 || funct3 == 7) &&
       source != 0);
}

static bool csr_skip_access_is_legal(uint32_t csr, bool writes,
    const riscv_difftest_observation_t *ref) {
  uint32_t privilege = ref->state.priv;
  uint32_t required_privilege = BITS(csr, 9, 8);
  if (privilege < required_privilege ||
      (writes && BITS(csr, 11, 10) == 3)) {
    return false;
  }

  if ((csr == 0x14du || csr == 0x15du) && privilege != 3 &&
      ((ref->state.menvcfgh & (UINT32_C(1) << 31)) == 0 ||
       (ref->state.mcounteren & (UINT32_C(1) << 1)) == 0)) {
    return false;
  }
  if (csr == 0xc01u || csr == 0xc81u) {
    bool machine_allows = privilege == 3 ||
        (ref->state.mcounteren & (UINT32_C(1) << 1)) != 0;
    bool supervisor_allows = privilege != 0 ||
        (ref->state.scounteren & (UINT32_C(1) << 1)) != 0;
    if (!machine_allows || !supervisor_allows) return false;
  }
  return true;
}

static uint32_t csr_skip_reason(uint32_t inst,
    const riscv_difftest_observation_t *ref) {
  if ((inst & 0x7fu) != 0x73u || BITS(inst, 14, 12) == 0) {
    return RISCV_DIFFTEST_SKIP_NONE;
  }
  uint32_t csr = BITS(inst, 31, 20);
  bool writes = csr_instruction_writes(inst);
  if (!csr_skip_access_is_legal(csr, writes, ref)) {
    return RISCV_DIFFTEST_SKIP_NONE;
  }

  switch (csr) {
    case 0x144u: // sip
    case 0x344u: // mip
      return RISCV_DIFFTEST_SKIP_PENDING_OWNED;
    case 0x14du: // stimecmp
    case 0x15du: // stimecmph
    case 0xc01u: // time
    case 0xc81u: // timeh
      return RISCV_DIFFTEST_SKIP_TIMER_OWNED;
    case 0x301u: // misa
      return RISCV_DIFFTEST_SKIP_PROFILE_OWNED_MISA;
    case 0x310u: // mstatush
    case 0xf11u: // mvendorid
    case 0xf12u: // marchid
    case 0xf13u: // mimpid
    case 0xf14u: // mhartid
    case 0xf15u: // mconfigptr
      return RISCV_DIFFTEST_SKIP_PROFILE_OWNED_STATIC;
    default:
      return RISCV_DIFFTEST_SKIP_NONE;
  }
}

static uint32_t memory_skip_reason(paddr_t addr) {
  switch (addr) {
    case UINT32_C(0x02000000):
      return RISCV_DIFFTEST_SKIP_PENDING_OWNED;
    case UINT32_C(0x02004000):
    case UINT32_C(0x02004004):
    case UINT32_C(0x0200bff8):
    case UINT32_C(0x0200bffc):
      return RISCV_DIFFTEST_SKIP_TIMER_OWNED;
    default:
      return RISCV_DIFFTEST_SKIP_MMIO_DUT_OWNED;
  }
}

static bool data_access_uses_translation(
    const riscv_difftest_observation_t *ref) {
  const uint32_t mstatus_mpp = UINT32_C(3) << 11;
  const uint32_t mstatus_mprv = UINT32_C(1) << 17;
  const uint32_t privilege_m = 3;
  uint32_t effective_privilege = ref->state.priv;
  if (effective_privilege == privilege_m &&
      (ref->state.mstatus & mstatus_mprv) != 0) {
    effective_privilege = (ref->state.mstatus & mstatus_mpp) >> 11;
  }
  return (ref->state.satp & (UINT32_C(1) << 31)) != 0 &&
      effective_privilege != privilege_m;
}

static uint32_t skip_reason_for_instruction(uint32_t inst,
    uint32_t instruction_length,
    const riscv_difftest_observation_t *ref) {
  uint32_t reason = csr_skip_reason(inst, ref);
  if (reason != RISCV_DIFFTEST_SKIP_NONE) return reason;

  uint32_t rs1 = 0;
  uint32_t len = 0;
  sword_t imm = 0;
  if (!memory_access_info(inst, instruction_length, &rs1, &imm, &len)) {
    return RISCV_DIFFTEST_SKIP_NONE;
  }
  if (rs1 >= profile.gpr_count) return RISCV_DIFFTEST_SKIP_NONE;
  vaddr_t addr = ref->state.gpr[rs1] + imm;
  if ((addr & (vaddr_t)(len - 1)) != 0) {
    return RISCV_DIFFTEST_SKIP_NONE;
  }
  // A translated effective address cannot be classified by the physical map.
  if (data_access_uses_translation(ref)) {
    return platform_difftest_in_identity_mmio(addr, len)
        ? memory_skip_reason(addr) : RISCV_DIFFTEST_SKIP_NONE;
  }
  if (platform_in_comparable_mem(addr, len)) {
    return RISCV_DIFFTEST_SKIP_NONE;
  }
  return memory_skip_reason(addr);
}

void init_difftest(char *ref_so_file, long img_size, int port) {
  (void)port;
  Assert(ref_so_file != NULL, "DiffTest is enabled but ref_so_file is NULL");
  Assert(img_size >= 0, "DiffTest image size is negative: img_size=%ld",
      img_size);

  void *handle = dlopen(ref_so_file, RTLD_LAZY);
  Assert(handle != NULL, "Can not open DiffTest reference '%s': %s",
      ref_so_file, dlerror());
  ref_query_interface = (difftest_query_interface_t)
      require_ref_symbol(handle, "difftest_query_interface");
  ref_init_profile = (difftest_init_profile_t)
      require_ref_symbol(handle, "difftest_init_profile");
  ref_load_memory = (difftest_load_memory_t)
      require_ref_symbol(handle, "difftest_load_memory");
  ref_get_observation = (difftest_get_observation_t)
      require_ref_symbol(handle, "difftest_get_observation");
  ref_set_sync_state = (difftest_set_sync_state_t)
      require_ref_symbol(handle, "difftest_set_sync_state");
  ref_arch_step = (difftest_arch_step_t)
      require_ref_symbol(handle, "difftest_arch_step");
  ref_async_intr = (difftest_async_intr_t)
      require_ref_symbol(handle, "difftest_async_intr");

  riscv_difftest_interface_t interface = {
    .abi_version = RISCV_DIFFTEST_ABI_VERSION,
    .struct_size = sizeof(interface),
  };
  require_ref_status("query_interface",
      ref_query_interface(RISCV_DIFFTEST_ABI_VERSION, &interface));
  Assert(interface.abi_version == RISCV_DIFFTEST_ABI_VERSION &&
      interface.struct_size == sizeof(interface),
      "DiffTest interface header mismatch: version=%u size=%u",
      interface.abi_version, interface.struct_size);
  Assert(riscv_difftest_string_is_terminated(interface.implementation_id,
          sizeof(interface.implementation_id)),
      "DiffTest interface contains an unterminated implementation ID");
  Assert(interface.observation_size == sizeof(riscv_difftest_observation_t) &&
      interface.sync_state_size == sizeof(riscv_difftest_sync_state_t) &&
      interface.arch_step_size == sizeof(riscv_difftest_arch_step_t) &&
      interface.async_intr_size == sizeof(riscv_difftest_async_intr_t) &&
      interface.profile_size == sizeof(riscv_difftest_profile_t) &&
      interface.max_gpr_count >= 32,
      "DiffTest interface payload-size mismatch");

  profile = make_profile();
  uint64_t missing_capabilities = profile.required_capabilities &
      ~interface.provided_capabilities;
  uint64_t missing_features = profile.isa_features &
      ~interface.supported_isa_features;
  Assert(missing_capabilities == 0,
      "DiffTest reference lacks required capabilities: missing=0x%016" PRIx64,
      missing_capabilities);
  Assert(missing_features == 0,
      "DiffTest reference lacks required ISA features: missing=0x%016" PRIx64,
      missing_features);
  require_ref_status("init_profile", ref_init_profile(&profile));
  require_ref_status("load_memory",
      platform_difftest_memcpy(ref_load_memory));

  riscv_difftest_sync_state_t sync;
  build_sync_state(&sync);
  require_ref_status("set_sync_state", ref_set_sync_state(&sync));
  require_ref_status("get_observation",
      ref_get_observation(&last_ref_observation));
  next_sequence = 0;
  check_observation(&last_ref_observation, UINT64_MAX, "INITIAL_SYNC", cpu.pc);

  Log("Differential testing: %s", ANSI_FMT("ON", ANSI_FG_GREEN));
  Log("RV32 DiffTest ABI v%u profile=%u memory-map=%u reference=%s",
      RISCV_DIFFTEST_ABI_VERSION, profile.profile_id, profile.memory_map,
      interface.implementation_id);
}

void difftest_step(vaddr_t pc, vaddr_t dnpc, uint32_t inst,
    uint32_t instruction_length, uint32_t instruction_valid) {
  Assert((instruction_length == 2 || instruction_length == 4) &&
      instruction_valid <= 1,
      "DiffTest ARCH_STEP metadata is invalid: pc=" FMT_WORD
      " inst=0x%08x length=%u valid=%u",
      pc, inst, instruction_length, instruction_valid);
  if (instruction_valid) {
    Assert(instruction_length == 2
        ? ((inst & 0xffff0000u) == 0 && (inst & 0x3u) != 0x3u)
        : ((inst & 0x3u) == 0x3u),
        "DiffTest ARCH_STEP encoding disagrees with length: pc=" FMT_WORD
        " inst=0x%08x length=%u", pc, inst, instruction_length);
  }
  Assert((pc & 0x1u) == 0 && (dnpc & 0x1u) == 0 && cpu.pc == dnpc,
      "DiffTest ARCH_STEP boundary mismatch: instruction_pc=" FMT_WORD
      " post_pc=" FMT_WORD " committed_pc=" FMT_WORD " inst=0x%08x",
      pc, dnpc, cpu.pc, inst);
  Assert(last_ref_observation.state.pc == pc,
      "DiffTest pre-state PC mismatch: ref_pc=" FMT_WORD
      " instruction_pc=" FMT_WORD " inst=0x%08x",
      last_ref_observation.state.pc, pc, inst);

  uint32_t skip_reason = instruction_valid
      ? skip_reason_for_instruction(inst, instruction_length,
          &last_ref_observation)
      : RISCV_DIFFTEST_SKIP_NONE;
  bool skip_ref = skip_reason != RISCV_DIFFTEST_SKIP_NONE;
  riscv_difftest_arch_step_t event = {
    .abi_version = RISCV_DIFFTEST_ABI_VERSION,
    .struct_size = sizeof(event),
    .sequence = next_sequence,
    .instruction_pc = pc,
    .instruction_bits = inst,
    .instruction_length = instruction_length,
    .instruction_valid = instruction_valid,
    .disposition = skip_ref ? RISCV_DIFFTEST_STEP_SKIP_REF
                            : RISCV_DIFFTEST_STEP_EXECUTE,
    .skip_reason = skip_reason,
  };

  riscv_difftest_sync_state_t sync;
  const riscv_difftest_sync_state_t *sync_ptr = NULL;
  if (skip_ref) {
    uint32_t gpr_mask = 0;
    int status = riscv_difftest_skip_gpr_mask(event.skip_reason,
        event.instruction_bits, event.instruction_length, &gpr_mask);
    Assert(status == RISCV_DIFFTEST_OK &&
        (gpr_mask & ~RISCV_DIFFTEST_RV32IMAC_GPR_MASK) == 0,
        "DiffTest typed skip reason=%u has invalid GPR effect: pc=" FMT_WORD
        " inst=0x%08x mask=0x%08x status=%d",
        event.skip_reason, pc, inst, gpr_mask, status);
    build_sync_state(&sync);
    sync.state.valid_fields = riscv_difftest_skip_sync_fields(
        profile.profile_id, event.skip_reason);
    sync.state.gpr_valid_mask = gpr_mask;
    if (gpr_mask == 0) {
      sync.state.valid_fields &= ~RISCV_DIFFTEST_FIELD_GPR;
    }
    sync_ptr = &sync;
  }

  riscv_difftest_observation_t ref;
  require_ref_status("ARCH_STEP", ref_arch_step(&event, sync_ptr, &ref));
  last_ref_observation = ref;
  next_sequence++;
  check_observation(&ref, event.sequence, "ARCH_STEP", pc);
}

void difftest_raise_intr(uint32_t cause, vaddr_t pretrap_pc) {
  Assert((cause & 0x80000000u) != 0 && (pretrap_pc & 0x1u) == 0,
      "DiffTest ASYNC_INTR metadata is invalid: cause=" FMT_WORD
      " pretrap_pc=" FMT_WORD, cause, pretrap_pc);
  Assert(last_ref_observation.state.pc == pretrap_pc,
      "DiffTest interrupt pre-state PC mismatch: ref_pc=" FMT_WORD
      " pretrap_pc=" FMT_WORD " cause=" FMT_WORD,
      last_ref_observation.state.pc, pretrap_pc, cause);

  riscv_difftest_async_intr_t event = {
    .abi_version = RISCV_DIFFTEST_ABI_VERSION,
    .struct_size = sizeof(event),
    .sequence = next_sequence,
    .interrupt_code = cause & 0x7fffffffu,
    .pretrap_pc = pretrap_pc,
  };
  riscv_difftest_observation_t ref;
  require_ref_status("ASYNC_INTR", ref_async_intr(&event, &ref));
  last_ref_observation = ref;
  next_sequence++;
  check_observation(&ref, event.sequence, "ASYNC_INTR", pretrap_pc);
}

#else

void init_difftest(char *ref_so_file, long img_size, int port) {
  (void)ref_so_file;
  (void)img_size;
  (void)port;
}

#endif
