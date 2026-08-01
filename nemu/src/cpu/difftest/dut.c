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

#include <dlfcn.h>

#include <isa.h>
#include <cpu/cpu.h>
#include <memory/paddr.h>
#include <utils.h>
#include <difftest-def.h>

void (*ref_difftest_memcpy)(paddr_t addr, void *buf, size_t n,
    bool direction) = NULL;
void (*ref_difftest_regcpy)(void *dut, bool direction) = NULL;
void (*ref_difftest_exec)(uint64_t n) = NULL;
void (*ref_difftest_raise_intr)(uint64_t NO) = NULL;

#ifdef CONFIG_DIFFTEST

static bool is_attached = true;

#if defined(CONFIG_ISA_riscv)

#include "../../isa/riscv32/local-include/difftest.h"

static difftest_query_interface_t ref_query_interface = NULL;
static difftest_init_profile_t ref_init_profile = NULL;
static difftest_get_observation_t ref_get_observation = NULL;
static difftest_set_sync_state_t ref_set_sync_state = NULL;
static difftest_arch_step_t ref_arch_step = NULL;
static difftest_async_intr_t ref_async_intr = NULL;

static uint64_t next_sequence = 0;
static uint32_t pending_skip_reason = RISCV_DIFFTEST_SKIP_NONE;

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

static riscv_difftest_profile_t make_rv32gc_profile(void) {
  riscv_difftest_profile_t profile = {
    .abi_version = RISCV_DIFFTEST_ABI_VERSION,
    .struct_size = sizeof(profile),
    .profile_id = RISCV_DIFFTEST_PROFILE_RV32GC_NEMU_SPIKE,
    .xlen = 32,
    .gpr_count = 32,
    .fp_kind = RISCV_DIFFTEST_FP_D,
    .privilege_modes = RISCV_DIFFTEST_PRIV_U | RISCV_DIFFTEST_PRIV_S |
        RISCV_DIFFTEST_PRIV_M,
    .pmp_regions = 0,
    .isa_features = RISCV_DIFFTEST_RV32GC_FEATURES,
    .required_capabilities = RISCV_DIFFTEST_RV32GC_REQUIRED_CAPS,
    .optional_capabilities = 0,
    .reset_pc = RESET_VECTOR,
    .memory_map = RISCV_DIFFTEST_MEMORY_MAP_NEMU,
  };
  return profile;
}

static bool check_observation(const riscv_difftest_observation_t *ref,
    uint64_t sequence, const char *event_name, vaddr_t event_pc) {
  riscv_difftest_observation_t dut;
  riscv_difftest_build_observation(&dut,
      RISCV_DIFFTEST_PROFILE_RV32GC_NEMU_SPIKE, sequence, &cpu);
  if (riscv_difftest_check_observation(ref, &dut, event_name, event_pc)) {
    return true;
  }
  nemu_state.state = NEMU_ABORT;
  nemu_state.halt_pc = event_pc;
  isa_reg_display();
  return false;
}

static void sync_reference(const char *reason) {
  riscv_difftest_sync_state_t sync;
  riscv_difftest_observation_t ref;
  riscv_difftest_build_sync_state(&sync,
      RISCV_DIFFTEST_PROFILE_RV32GC_NEMU_SPIKE, &cpu);
  require_ref_status("set_sync_state", ref_set_sync_state(&sync));
  require_ref_status("get_observation", ref_get_observation(&ref));
  uint64_t sequence = next_sequence == 0 ? UINT64_MAX : next_sequence - 1;
  check_observation(&ref, sequence, reason, cpu.pc);
}

void difftest_skip_ref_reason(uint32_t reason) {
  if (!is_attached) return;
  Assert(reason > RISCV_DIFFTEST_SKIP_NONE &&
      reason <= RISCV_DIFFTEST_SKIP_PROFILE_OWNED_STATIC,
      "invalid DiffTest skip reason: %u", reason);
  Assert(pending_skip_reason == RISCV_DIFFTEST_SKIP_NONE ||
      pending_skip_reason == reason,
      "conflicting DiffTest skip reasons in one ARCH_STEP: old=%u new=%u pc="
      FMT_WORD, pending_skip_reason, reason, cpu.pc);
  pending_skip_reason = reason;
}

void difftest_skip_ref(void) {
  panic("untyped DiffTest skip at pc=" FMT_WORD, cpu.pc);
}

void difftest_skip_dut(int nr_ref, int nr_dut) {
  panic("difftest_skip_dut is not part of the versioned RISC-V protocol: "
      "nr_ref=%d nr_dut=%d pc=" FMT_WORD, nr_ref, nr_dut, cpu.pc);
}

void difftest_detach(void) {
  is_attached = false;
}

void difftest_attach(void) {
  ref_difftest_memcpy(PMEM_LEFT, guest_to_host(PMEM_LEFT), CONFIG_MSIZE,
      DIFFTEST_TO_REF);
  sync_reference("ATTACH");
  pending_skip_reason = RISCV_DIFFTEST_SKIP_NONE;
  is_attached = true;
}

bool difftest_is_attached(void) {
  return is_attached;
}

void init_difftest(char *ref_so_file, long img_size, int port) {
  (void)port;
  Assert(ref_so_file != NULL, "DiffTest is enabled but ref_so_file is NULL");
  Assert(img_size >= 0,
      "DiffTest image size is negative: img_size=%ld reset_vector=" FMT_PADDR,
      img_size, RESET_VECTOR);
  Assert((uint64_t)img_size <=
      (uint64_t)PMEM_RIGHT - (uint64_t)RESET_VECTOR + 1,
      "DiffTest image is too large: img_size=%ld reset_vector=" FMT_PADDR
      " pmem=[" FMT_PADDR ", " FMT_PADDR "]",
      img_size, RESET_VECTOR, PMEM_LEFT, PMEM_RIGHT);

  void *handle = dlopen(ref_so_file, RTLD_LAZY);
  Assert(handle != NULL, "Can not open DiffTest reference '%s': %s",
      ref_so_file, dlerror());

  ref_query_interface = (difftest_query_interface_t)
      require_ref_symbol(handle, "difftest_query_interface");
  ref_init_profile = (difftest_init_profile_t)
      require_ref_symbol(handle, "difftest_init_profile");
  ref_difftest_memcpy = (void (*)(paddr_t, void *, size_t, bool))
      require_ref_symbol(handle, "difftest_memcpy");
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
  Assert(interface.observation_size == sizeof(riscv_difftest_observation_t) &&
      interface.sync_state_size == sizeof(riscv_difftest_sync_state_t) &&
      interface.arch_step_size == sizeof(riscv_difftest_arch_step_t) &&
      interface.async_intr_size == sizeof(riscv_difftest_async_intr_t) &&
      interface.profile_size == sizeof(riscv_difftest_profile_t) &&
      interface.max_gpr_count == RISCV_DIFFTEST_MAX_GPRS,
      "DiffTest interface payload-size mismatch");

  riscv_difftest_profile_t profile = make_rv32gc_profile();
  uint64_t missing_caps = profile.required_capabilities &
      ~interface.provided_capabilities;
  uint64_t missing_features = profile.isa_features &
      ~interface.supported_isa_features;
  Assert(missing_caps == 0,
      "DiffTest reference lacks required capabilities: missing=0x%016" PRIx64,
      missing_caps);
  Assert(missing_features == 0,
      "DiffTest reference lacks required ISA features: missing=0x%016" PRIx64,
      missing_features);
  require_ref_status("init_profile", ref_init_profile(&profile));

  ref_difftest_memcpy(RESET_VECTOR, guest_to_host(RESET_VECTOR), img_size,
      DIFFTEST_TO_REF);
  next_sequence = 0;
  pending_skip_reason = RISCV_DIFFTEST_SKIP_NONE;
  is_attached = true;
  sync_reference("INITIAL_SYNC");

  Log("Differential testing: %s", ANSI_FMT("ON", ANSI_FG_GREEN));
  Log("RV32 DiffTest ABI v%u profile=%u reference=%s",
      RISCV_DIFFTEST_ABI_VERSION, profile.profile_id,
      interface.implementation_id);
}

void difftest_step(vaddr_t pc, uint32_t instruction_bits,
    uint32_t instruction_length, bool instruction_valid) {
  if (!is_attached) return;

  riscv_difftest_arch_step_t event = {
    .abi_version = RISCV_DIFFTEST_ABI_VERSION,
    .struct_size = sizeof(event),
    .sequence = next_sequence,
    .instruction_pc = pc,
    .instruction_bits = instruction_bits,
    .instruction_length = instruction_length,
    .instruction_valid = instruction_valid,
    .disposition = pending_skip_reason == RISCV_DIFFTEST_SKIP_NONE
        ? RISCV_DIFFTEST_STEP_EXECUTE : RISCV_DIFFTEST_STEP_SKIP_REF,
    .skip_reason = pending_skip_reason,
  };
  riscv_difftest_sync_state_t sync;
  const riscv_difftest_sync_state_t *sync_ptr = NULL;
  if (event.disposition == RISCV_DIFFTEST_STEP_SKIP_REF) {
    int status = riscv_difftest_build_skip_sync_state(&sync,
        event.skip_reason, event.instruction_bits, event.instruction_length,
        &cpu);
    Assert(status == RISCV_DIFFTEST_OK,
        "DiffTest skip reason=%u does not support instruction bits=0x%08x "
        "length=%u at pc=" FMT_WORD,
        event.skip_reason, event.instruction_bits, event.instruction_length,
        event.instruction_pc);
    sync_ptr = &sync;
  }

  riscv_difftest_observation_t ref;
  require_ref_status("ARCH_STEP", ref_arch_step(&event, sync_ptr, &ref));
  pending_skip_reason = RISCV_DIFFTEST_SKIP_NONE;
  next_sequence++;
  check_observation(&ref, event.sequence, "ARCH_STEP", pc);
}

void difftest_raise_intr_event(uint32_t interrupt_code, vaddr_t pretrap_pc) {
  if (!is_attached) return;
  Assert(pending_skip_reason == RISCV_DIFFTEST_SKIP_NONE,
      "ASYNC_INTR follows an unconsumed skip: reason=%u pc=" FMT_WORD,
      pending_skip_reason, pretrap_pc);

  riscv_difftest_async_intr_t event = {
    .abi_version = RISCV_DIFFTEST_ABI_VERSION,
    .struct_size = sizeof(event),
    .sequence = next_sequence,
    .interrupt_code = interrupt_code,
    .pretrap_pc = pretrap_pc,
  };
  riscv_difftest_observation_t ref;
  require_ref_status("ASYNC_INTR", ref_async_intr(&event, &ref));
  next_sequence++;
  check_observation(&ref, event.sequence, "ASYNC_INTR", pretrap_pc);
}

#else

static bool is_skip_ref = false;
static int skip_dut_nr_inst = 0;

void difftest_skip_ref(void) {
  if (!is_attached) return;
  is_skip_ref = true;
  skip_dut_nr_inst = 0;
}

void difftest_skip_ref_reason(uint32_t reason) {
  (void)reason;
  difftest_skip_ref();
}

void difftest_skip_dut(int nr_ref, int nr_dut) {
  if (!is_attached) return;
  Assert(nr_ref >= 0 && nr_dut >= 0,
      "bad difftest_skip_dut arguments: nr_ref=%d nr_dut=%d",
      nr_ref, nr_dut);
  skip_dut_nr_inst += nr_dut;
  while (nr_ref-- > 0) ref_difftest_exec(1);
}

void difftest_detach(void) { is_attached = false; }

void difftest_attach(void) {
  ref_difftest_memcpy(PMEM_LEFT, guest_to_host(PMEM_LEFT), CONFIG_MSIZE,
      DIFFTEST_TO_REF);
  ref_difftest_regcpy(&cpu, DIFFTEST_TO_REF);
  isa_difftest_attach();
  is_skip_ref = false;
  skip_dut_nr_inst = 0;
  is_attached = true;
}

bool difftest_is_attached(void) { return is_attached; }

void init_difftest(char *ref_so_file, long img_size, int port) {
  Assert(ref_so_file != NULL, "DiffTest is enabled but ref_so_file is NULL");
  void *handle = dlopen(ref_so_file, RTLD_LAZY);
  Assert(handle != NULL, "Can not open DiffTest reference '%s': %s",
      ref_so_file, dlerror());
  ref_difftest_memcpy = dlsym(handle, "difftest_memcpy");
  ref_difftest_regcpy = dlsym(handle, "difftest_regcpy");
  ref_difftest_exec = dlsym(handle, "difftest_exec");
  ref_difftest_raise_intr = dlsym(handle, "difftest_raise_intr");
  void (*ref_difftest_init)(int) = dlsym(handle, "difftest_init");
  Assert(ref_difftest_memcpy && ref_difftest_regcpy && ref_difftest_exec &&
      ref_difftest_raise_intr && ref_difftest_init,
      "Can not load legacy DiffTest reference symbols");
  ref_difftest_init(port);
  ref_difftest_memcpy(RESET_VECTOR, guest_to_host(RESET_VECTOR), img_size,
      DIFFTEST_TO_REF);
  ref_difftest_regcpy(&cpu, DIFFTEST_TO_REF);
}

void difftest_step(vaddr_t pc, uint32_t instruction_bits,
    uint32_t instruction_length, bool instruction_valid) {
  (void)instruction_bits;
  (void)instruction_length;
  (void)instruction_valid;
  if (!is_attached) return;
  CPU_state ref_r;
  if (skip_dut_nr_inst > 0) {
    ref_difftest_regcpy(&ref_r, DIFFTEST_TO_DUT);
    if (ref_r.pc == cpu.pc) {
      skip_dut_nr_inst = 0;
      if (!isa_difftest_checkregs(&ref_r, cpu.pc)) nemu_state.state = NEMU_ABORT;
      return;
    }
    if (--skip_dut_nr_inst == 0) {
      panic("can not catch up with ref.pc at pc=" FMT_WORD, pc);
    }
    return;
  }
  if (is_skip_ref) {
    ref_difftest_regcpy(&cpu, DIFFTEST_TO_REF);
    is_skip_ref = false;
    return;
  }
  ref_difftest_exec(1);
  ref_difftest_regcpy(&ref_r, DIFFTEST_TO_DUT);
  if (!isa_difftest_checkregs(&ref_r, pc)) nemu_state.state = NEMU_ABORT;
}

#endif

#else

void init_difftest(char *ref_so_file, long img_size, int port) {
  (void)ref_so_file;
  (void)img_size;
  (void)port;
}

#endif
