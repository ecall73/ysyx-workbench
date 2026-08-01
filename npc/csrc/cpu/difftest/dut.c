#include <dlfcn.h>

#include <cpu/cpu.h>
#include <difftest-def.h>
#include <isa.h>
#include <platform/platform.h>
#include <utils.h>

#ifdef CONFIG_DIFFTEST

static void (*ref_memcpy)(paddr_t, void *, size_t, bool) = NULL;
static difftest_query_interface_t ref_query_interface = NULL;
static difftest_init_profile_t ref_init_profile = NULL;
static difftest_get_observation_t ref_get_observation = NULL;
static difftest_set_sync_state_t ref_set_sync_state = NULL;
static difftest_arch_step_t ref_arch_step = NULL;

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
    case RISCV_DIFFTEST_BAD_MEMORY: return "bad memory operation";
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
      "DiffTest reference does not implement versioned RV32 symbol '%s'; "
      "legacy regcpy fallback is disabled", name);
  return symbol;
}

static riscv_difftest_profile_t make_profile(void) {
  uint32_t memory_map = platform_difftest_memory_map();
  uint64_t required_capabilities = RISCV_DIFFTEST_RV32E_REQUIRED_CAPS;
  if (memory_map == RISCV_DIFFTEST_MEMORY_MAP_YSYXSOC) {
    required_capabilities |= RISCV_DIFFTEST_CAP_YSYXSOC_MEMORY_MAP;
  }
  return (riscv_difftest_profile_t) {
    .abi_version = RISCV_DIFFTEST_ABI_VERSION,
    .struct_size = sizeof(riscv_difftest_profile_t),
    .profile_id = RISCV_DIFFTEST_PROFILE_RV32E_NPC_NEMU,
    .xlen = 32,
    .gpr_count = 16,
    .fp_kind = RISCV_DIFFTEST_FP_NONE,
    .privilege_modes = RISCV_DIFFTEST_PRIV_M,
    .pmp_regions = 0,
    .isa_features = RISCV_DIFFTEST_RV32E_FEATURES,
    .required_capabilities = required_capabilities,
    .optional_capabilities = 0,
    .reset_pc = platform_reset_pc(),
    .memory_map = memory_map,
  };
}

static void build_arch_state(riscv_difftest_arch_state_t *state) {
  memset(state, 0, sizeof(*state));
  state->valid_fields = RISCV_DIFFTEST_RV32E_STATE_FIELDS;
  state->gpr_valid_mask = RISCV_DIFFTEST_RV32E_GPR_MASK;
  state->pc = cpu.pc;
  for (size_t i = 0; i < profile.gpr_count; i++) {
    state->gpr[i] = cpu.gpr[i];
  }
  state->priv = 3;
  state->mstatus = cpu.mstatus;
  state->mtvec = cpu.mtvec;
  state->mepc = cpu.mepc;
  state->mcause = cpu.mcause;
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

static int memory_access_length(uint32_t inst) {
  uint32_t opcode = inst & 0x7fu;
  uint32_t funct3 = BITS(inst, 14, 12);
  if (opcode == 0x03u) {
    switch (funct3) {
      case 0: case 4: return 1;
      case 1: case 5: return 2;
      case 2: return 4;
      default: return 0;
    }
  }
  if (opcode == 0x23u) {
    switch (funct3) {
      case 0: return 1;
      case 1: return 2;
      case 2: return 4;
      default: return 0;
    }
  }
  return 0;
}

static bool should_skip_ref(uint32_t inst,
    const riscv_difftest_observation_t *ref) {
  uint32_t opcode = inst & 0x7fu;
  int len = memory_access_length(inst);
  if (len == 0) return false;

  uint32_t rs1 = BITS(inst, 19, 15);
  if (rs1 >= profile.gpr_count) return false;
  sword_t imm = opcode == 0x03u
      ? (sword_t)(int32_t)(inst & 0xfff00000u) >> 20
      : (sword_t)(int32_t)((inst & 0xfe000000u) |
          ((inst & 0x00000f80u) << 13)) >> 20;
  paddr_t addr = ref->state.gpr[rs1] + imm;
  if ((addr & (paddr_t)(len - 1)) != 0) return false;
  return !platform_in_comparable_mem(addr, len);
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
  ref_memcpy = (void (*)(paddr_t, void *, size_t, bool))
      require_ref_symbol(handle, "difftest_memcpy");
  ref_get_observation = (difftest_get_observation_t)
      require_ref_symbol(handle, "difftest_get_observation");
  ref_set_sync_state = (difftest_set_sync_state_t)
      require_ref_symbol(handle, "difftest_set_sync_state");
  ref_arch_step = (difftest_arch_step_t)
      require_ref_symbol(handle, "difftest_arch_step");

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
  Assert(interface.observation_size == sizeof(riscv_difftest_observation_t) &&
      interface.sync_state_size == sizeof(riscv_difftest_sync_state_t) &&
      interface.arch_step_size == sizeof(riscv_difftest_arch_step_t) &&
      interface.async_intr_size == sizeof(riscv_difftest_async_intr_t) &&
      interface.profile_size == sizeof(riscv_difftest_profile_t) &&
      interface.max_gpr_count >= 16,
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
  platform_difftest_memcpy(ref_memcpy, DIFFTEST_TO_REF);

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

void difftest_step(vaddr_t pc, vaddr_t dnpc, uint32_t inst) {
  Assert((pc & 0x3u) == 0 && (dnpc & 0x3u) == 0 && cpu.pc == dnpc,
      "DiffTest ARCH_STEP boundary mismatch: instruction_pc=" FMT_WORD
      " post_pc=" FMT_WORD " committed_pc=" FMT_WORD " inst=0x%08x",
      pc, dnpc, cpu.pc, inst);
  Assert(last_ref_observation.state.pc == pc,
      "DiffTest pre-state PC mismatch: ref_pc=" FMT_WORD
      " instruction_pc=" FMT_WORD " inst=0x%08x",
      last_ref_observation.state.pc, pc, inst);

  bool skip_ref = should_skip_ref(inst, &last_ref_observation);
  riscv_difftest_arch_step_t event = {
    .abi_version = RISCV_DIFFTEST_ABI_VERSION,
    .struct_size = sizeof(event),
    .sequence = next_sequence,
    .instruction_pc = pc,
    .instruction_bits = inst,
    .instruction_length = 4,
    .instruction_valid = 1,
    .disposition = skip_ref ? RISCV_DIFFTEST_STEP_SKIP_REF
                            : RISCV_DIFFTEST_STEP_EXECUTE,
    .skip_reason = skip_ref ? RISCV_DIFFTEST_SKIP_MMIO_DUT_OWNED
                            : RISCV_DIFFTEST_SKIP_NONE,
  };

  riscv_difftest_sync_state_t sync;
  const riscv_difftest_sync_state_t *sync_ptr = NULL;
  if (skip_ref) {
    uint32_t gpr_mask = 0;
    int status = riscv_difftest_skip_gpr_mask(event.skip_reason,
        event.instruction_bits, event.instruction_length, &gpr_mask);
    Assert(status == RISCV_DIFFTEST_OK &&
        (gpr_mask & ~RISCV_DIFFTEST_RV32E_GPR_MASK) == 0,
        "DiffTest MMIO skip has invalid GPR effect: pc=" FMT_WORD
        " inst=0x%08x mask=0x%08x status=%d",
        pc, inst, gpr_mask, status);
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

#else

void init_difftest(char *ref_so_file, long img_size, int port) {
  (void)ref_so_file;
  (void)img_size;
  (void)port;
}

#endif
