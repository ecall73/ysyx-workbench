#ifndef __RISCV_DIFFTEST_H__
#define __RISCV_DIFFTEST_H__

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

#define RISCV_DIFFTEST_ABI_VERSION 1u
#define RISCV_DIFFTEST_MAX_GPRS 32u
#define RISCV_DIFFTEST_FPRS 32u
#define RISCV_DIFFTEST_IMPLEMENTATION_ID_SIZE 96u

enum riscv_difftest_status {
  RISCV_DIFFTEST_OK = 0,
  RISCV_DIFFTEST_BAD_ARGUMENT = 1,
  RISCV_DIFFTEST_BAD_ABI_VERSION = 2,
  RISCV_DIFFTEST_BAD_STRUCT_SIZE = 3,
  RISCV_DIFFTEST_UNSUPPORTED_CAPABILITY = 4,
  RISCV_DIFFTEST_UNSUPPORTED_PROFILE = 5,
  RISCV_DIFFTEST_BAD_SEQUENCE = 6,
  RISCV_DIFFTEST_BAD_EVENT = 7,
  RISCV_DIFFTEST_BAD_STATE = 8,
  RISCV_DIFFTEST_BAD_MEMORY = 9,
  RISCV_DIFFTEST_INTERNAL_ERROR = 10,
};

enum riscv_difftest_profile_id {
  RISCV_DIFFTEST_PROFILE_RV32GC_NEMU_SPIKE = 1,
  RISCV_DIFFTEST_PROFILE_RV32IMAC_NPC_NEMU = 2,
};

enum riscv_difftest_fp_kind {
  RISCV_DIFFTEST_FP_NONE = 0,
  RISCV_DIFFTEST_FP_F = 1,
  RISCV_DIFFTEST_FP_D = 2,
};

enum riscv_difftest_memory_map {
  RISCV_DIFFTEST_MEMORY_MAP_NEMU = 0,
  RISCV_DIFFTEST_MEMORY_MAP_YSYXSOC = 1,
};

enum riscv_difftest_privilege {
  RISCV_DIFFTEST_PRIV_U = 1u << 0,
  RISCV_DIFFTEST_PRIV_S = 1u << 1,
  RISCV_DIFFTEST_PRIV_M = 1u << 3,
};

enum riscv_difftest_capability {
  RISCV_DIFFTEST_CAP_ARCH_STEP = UINT64_C(1) << 0,
  RISCV_DIFFTEST_CAP_ASYNC_INTR_CAUSE_ONLY = UINT64_C(1) << 1,
  RISCV_DIFFTEST_CAP_TYPED_SKIP = UINT64_C(1) << 2,
  RISCV_DIFFTEST_CAP_PURE_OBSERVATION = UINT64_C(1) << 3,
  RISCV_DIFFTEST_CAP_SYNC_STATE = UINT64_C(1) << 4,
  RISCV_DIFFTEST_CAP_PRECISE_EXCEPTIONS = UINT64_C(1) << 5,
  RISCV_DIFFTEST_CAP_LOCAL_INTERRUPTS = UINT64_C(1) << 6,
  RISCV_DIFFTEST_CAP_DETERMINISTIC_ZICNTR = UINT64_C(1) << 7,
  RISCV_DIFFTEST_CAP_WFI_AS_NOP = UINT64_C(1) << 8,
  RISCV_DIFFTEST_CAP_YSYXSOC_MEMORY_MAP = UINT64_C(1) << 9,
};

enum riscv_difftest_isa_feature {
  RISCV_DIFFTEST_ISA_I = UINT64_C(1) << 0,
  RISCV_DIFFTEST_ISA_E = UINT64_C(1) << 1,
  RISCV_DIFFTEST_ISA_M = UINT64_C(1) << 2,
  RISCV_DIFFTEST_ISA_A = UINT64_C(1) << 3,
  RISCV_DIFFTEST_ISA_F = UINT64_C(1) << 4,
  RISCV_DIFFTEST_ISA_D = UINT64_C(1) << 5,
  RISCV_DIFFTEST_ISA_C = UINT64_C(1) << 6,
  RISCV_DIFFTEST_ISA_ZICSR = UINT64_C(1) << 7,
  RISCV_DIFFTEST_ISA_ZIFENCEI = UINT64_C(1) << 8,
  RISCV_DIFFTEST_ISA_ZICNTR = UINT64_C(1) << 9,
  RISCV_DIFFTEST_ISA_SSTC = UINT64_C(1) << 10,
  RISCV_DIFFTEST_ISA_SVADU = UINT64_C(1) << 11,
  RISCV_DIFFTEST_ISA_SV32 = UINT64_C(1) << 12,
};

#define RISCV_DIFFTEST_RV32GC_FEATURES \
  (RISCV_DIFFTEST_ISA_I | RISCV_DIFFTEST_ISA_M | RISCV_DIFFTEST_ISA_A | \
   RISCV_DIFFTEST_ISA_F | RISCV_DIFFTEST_ISA_D | RISCV_DIFFTEST_ISA_C | \
   RISCV_DIFFTEST_ISA_ZICSR | RISCV_DIFFTEST_ISA_ZIFENCEI | \
   RISCV_DIFFTEST_ISA_ZICNTR | RISCV_DIFFTEST_ISA_SSTC | \
   RISCV_DIFFTEST_ISA_SVADU | RISCV_DIFFTEST_ISA_SV32)

#define RISCV_DIFFTEST_RV32GC_REQUIRED_CAPS \
  (RISCV_DIFFTEST_CAP_ARCH_STEP | \
   RISCV_DIFFTEST_CAP_ASYNC_INTR_CAUSE_ONLY | \
   RISCV_DIFFTEST_CAP_TYPED_SKIP | \
   RISCV_DIFFTEST_CAP_PURE_OBSERVATION | \
   RISCV_DIFFTEST_CAP_SYNC_STATE | \
   RISCV_DIFFTEST_CAP_PRECISE_EXCEPTIONS | \
   RISCV_DIFFTEST_CAP_LOCAL_INTERRUPTS | \
   RISCV_DIFFTEST_CAP_DETERMINISTIC_ZICNTR | \
   RISCV_DIFFTEST_CAP_WFI_AS_NOP)

#define RISCV_DIFFTEST_RV32IMAC_FEATURES \
  (RISCV_DIFFTEST_ISA_I | RISCV_DIFFTEST_ISA_M | RISCV_DIFFTEST_ISA_A | \
   RISCV_DIFFTEST_ISA_C | RISCV_DIFFTEST_ISA_ZICSR | \
   RISCV_DIFFTEST_ISA_ZIFENCEI | RISCV_DIFFTEST_ISA_SV32)

#define RISCV_DIFFTEST_RV32IMAC_REQUIRED_CAPS \
  (RISCV_DIFFTEST_CAP_ARCH_STEP | \
   RISCV_DIFFTEST_CAP_ASYNC_INTR_CAUSE_ONLY | \
   RISCV_DIFFTEST_CAP_TYPED_SKIP | \
   RISCV_DIFFTEST_CAP_PURE_OBSERVATION | \
   RISCV_DIFFTEST_CAP_SYNC_STATE | \
   RISCV_DIFFTEST_CAP_PRECISE_EXCEPTIONS | \
   RISCV_DIFFTEST_CAP_LOCAL_INTERRUPTS)

enum riscv_difftest_state_field {
  RISCV_DIFFTEST_FIELD_PC = UINT64_C(1) << 0,
  RISCV_DIFFTEST_FIELD_GPR = UINT64_C(1) << 1,
  RISCV_DIFFTEST_FIELD_FPR = UINT64_C(1) << 2,
  RISCV_DIFFTEST_FIELD_FCSR = UINT64_C(1) << 3,
  RISCV_DIFFTEST_FIELD_PRIV = UINT64_C(1) << 4,
  RISCV_DIFFTEST_FIELD_MCYCLE = UINT64_C(1) << 5,
  RISCV_DIFFTEST_FIELD_MINSTRET = UINT64_C(1) << 6,
  RISCV_DIFFTEST_FIELD_MSTATUS = UINT64_C(1) << 7,
  RISCV_DIFFTEST_FIELD_MTVEC = UINT64_C(1) << 8,
  RISCV_DIFFTEST_FIELD_MEPC = UINT64_C(1) << 9,
  RISCV_DIFFTEST_FIELD_MCAUSE = UINT64_C(1) << 10,
  RISCV_DIFFTEST_FIELD_MTVAL = UINT64_C(1) << 11,
  RISCV_DIFFTEST_FIELD_MEDELEG = UINT64_C(1) << 12,
  RISCV_DIFFTEST_FIELD_MIDELEG = UINT64_C(1) << 13,
  RISCV_DIFFTEST_FIELD_MIE = UINT64_C(1) << 14,
  RISCV_DIFFTEST_FIELD_STVEC = UINT64_C(1) << 15,
  RISCV_DIFFTEST_FIELD_SEPC = UINT64_C(1) << 16,
  RISCV_DIFFTEST_FIELD_SCAUSE = UINT64_C(1) << 17,
  RISCV_DIFFTEST_FIELD_STVAL = UINT64_C(1) << 18,
  RISCV_DIFFTEST_FIELD_SSCRATCH = UINT64_C(1) << 19,
  RISCV_DIFFTEST_FIELD_SATP = UINT64_C(1) << 20,
  RISCV_DIFFTEST_FIELD_MSCRATCH = UINT64_C(1) << 21,
  RISCV_DIFFTEST_FIELD_MENVCFGH = UINT64_C(1) << 22,
  RISCV_DIFFTEST_FIELD_MCOUNTEREN = UINT64_C(1) << 23,
  RISCV_DIFFTEST_FIELD_SCOUNTEREN = UINT64_C(1) << 24,
  RISCV_DIFFTEST_FIELD_MCOUNTINHIBIT = UINT64_C(1) << 25,
};

#define RISCV_DIFFTEST_RV32GC_STATE_FIELDS \
  ((UINT64_C(1) << 26) - UINT64_C(1))

#define RISCV_DIFFTEST_RV32IMAC_STATE_FIELDS \
  (RISCV_DIFFTEST_FIELD_PC | RISCV_DIFFTEST_FIELD_GPR | \
   RISCV_DIFFTEST_FIELD_PRIV | RISCV_DIFFTEST_FIELD_MSTATUS | \
   RISCV_DIFFTEST_FIELD_MTVEC | RISCV_DIFFTEST_FIELD_MEPC | \
   RISCV_DIFFTEST_FIELD_MCAUSE | RISCV_DIFFTEST_FIELD_MTVAL | \
   RISCV_DIFFTEST_FIELD_MEDELEG | RISCV_DIFFTEST_FIELD_MIDELEG | \
   RISCV_DIFFTEST_FIELD_MIE | RISCV_DIFFTEST_FIELD_STVEC | \
   RISCV_DIFFTEST_FIELD_SEPC | RISCV_DIFFTEST_FIELD_SCAUSE | \
   RISCV_DIFFTEST_FIELD_STVAL | RISCV_DIFFTEST_FIELD_SSCRATCH | \
   RISCV_DIFFTEST_FIELD_SATP | RISCV_DIFFTEST_FIELD_MSCRATCH | \
   RISCV_DIFFTEST_FIELD_MENVCFGH | RISCV_DIFFTEST_FIELD_MCOUNTEREN | \
   RISCV_DIFFTEST_FIELD_SCOUNTEREN | RISCV_DIFFTEST_FIELD_MCOUNTINHIBIT)

#define RISCV_DIFFTEST_RV32IMAC_GPR_MASK UINT32_MAX

enum riscv_difftest_step_disposition {
  RISCV_DIFFTEST_STEP_EXECUTE = 0,
  RISCV_DIFFTEST_STEP_SKIP_REF = 1,
};

enum riscv_difftest_skip_reason {
  RISCV_DIFFTEST_SKIP_NONE = 0,
  RISCV_DIFFTEST_SKIP_MMIO_DUT_OWNED = 1,
  RISCV_DIFFTEST_SKIP_PENDING_OWNED = 2,
  RISCV_DIFFTEST_SKIP_TIMER_OWNED = 3,
  RISCV_DIFFTEST_SKIP_PROFILE_OWNED_MISA = 4,
  RISCV_DIFFTEST_SKIP_PROFILE_OWNED_STATIC = 5,
};

#define RISCV_DIFFTEST_SKIP_BASE_STATE_FIELDS \
  (RISCV_DIFFTEST_FIELD_PC | RISCV_DIFFTEST_FIELD_GPR | \
   RISCV_DIFFTEST_FIELD_MCYCLE | RISCV_DIFFTEST_FIELD_MINSTRET)

static inline uint64_t riscv_difftest_skip_sync_fields(uint32_t profile_id,
    uint32_t reason) {
  uint64_t base_fields;
  switch (profile_id) {
    case RISCV_DIFFTEST_PROFILE_RV32GC_NEMU_SPIKE:
      base_fields = RISCV_DIFFTEST_SKIP_BASE_STATE_FIELDS;
      break;
    case RISCV_DIFFTEST_PROFILE_RV32IMAC_NPC_NEMU:
      base_fields = RISCV_DIFFTEST_FIELD_PC | RISCV_DIFFTEST_FIELD_GPR;
      break;
    default:
      return 0;
  }

  switch (reason) {
    case RISCV_DIFFTEST_SKIP_MMIO_DUT_OWNED:
    case RISCV_DIFFTEST_SKIP_PENDING_OWNED:
    case RISCV_DIFFTEST_SKIP_TIMER_OWNED:
    case RISCV_DIFFTEST_SKIP_PROFILE_OWNED_MISA:
    case RISCV_DIFFTEST_SKIP_PROFILE_OWNED_STATIC:
      return base_fields;
    default:
      return 0;
  }
}

static inline int riscv_difftest_skip_gpr_mask(uint32_t reason,
    uint32_t instruction_bits, uint32_t instruction_length,
    uint32_t *gpr_mask) {
  if (gpr_mask == NULL) return RISCV_DIFFTEST_BAD_ARGUMENT;
  *gpr_mask = 0;

  bool memory_owned = reason == RISCV_DIFFTEST_SKIP_MMIO_DUT_OWNED ||
      reason == RISCV_DIFFTEST_SKIP_PENDING_OWNED ||
      reason == RISCV_DIFFTEST_SKIP_TIMER_OWNED;
  bool csr_owned = reason == RISCV_DIFFTEST_SKIP_PENDING_OWNED ||
      reason == RISCV_DIFFTEST_SKIP_TIMER_OWNED ||
      reason == RISCV_DIFFTEST_SKIP_PROFILE_OWNED_MISA ||
      reason == RISCV_DIFFTEST_SKIP_PROFILE_OWNED_STATIC;

  if (instruction_length == 4 && (instruction_bits & 0x3u) == 0x3u) {
    uint32_t opcode = instruction_bits & 0x7fu;
    uint32_t rd = (instruction_bits >> 7) & 0x1fu;
    if (memory_owned && opcode == 0x03u) {
      if (rd != 0) *gpr_mask = UINT32_C(1) << rd;
      return RISCV_DIFFTEST_OK;
    }
    if (memory_owned && opcode == 0x23u) return RISCV_DIFFTEST_OK;
    if (csr_owned && opcode == 0x73u &&
        ((instruction_bits >> 12) & 0x7u) != 0) {
      if (rd != 0) *gpr_mask = UINT32_C(1) << rd;
      return RISCV_DIFFTEST_OK;
    }
    return RISCV_DIFFTEST_BAD_EVENT;
  }

  if (instruction_length == 2 && (instruction_bits & 0x3u) != 0x3u &&
      memory_owned) {
    uint32_t quadrant = instruction_bits & 0x3u;
    uint32_t funct3 = (instruction_bits >> 13) & 0x7u;
    if (quadrant == 0 && funct3 == 2) {
      *gpr_mask = UINT32_C(1) << (8u + ((instruction_bits >> 2) & 0x7u));
      return RISCV_DIFFTEST_OK;
    }
    if (quadrant == 2 && funct3 == 2) {
      uint32_t rd = (instruction_bits >> 7) & 0x1fu;
      if (rd != 0) *gpr_mask = UINT32_C(1) << rd;
      return RISCV_DIFFTEST_OK;
    }
    if ((quadrant == 0 || quadrant == 2) && funct3 == 6) {
      return RISCV_DIFFTEST_OK;
    }
  }
  return RISCV_DIFFTEST_BAD_EVENT;
}

typedef struct {
  uint32_t abi_version;
  uint32_t struct_size;
  uint32_t profile_id;
  uint32_t xlen;
  uint32_t gpr_count;
  uint32_t fp_kind;
  uint32_t privilege_modes;
  uint32_t pmp_regions;
  uint64_t isa_features;
  uint64_t required_capabilities;
  uint64_t optional_capabilities;
  uint32_t reset_pc;
  uint32_t memory_map;
  uint32_t reserved[4];
} riscv_difftest_profile_t;

typedef struct {
  uint32_t abi_version;
  uint32_t struct_size;
  uint64_t provided_capabilities;
  uint64_t supported_isa_features;
  uint32_t observation_size;
  uint32_t sync_state_size;
  uint32_t arch_step_size;
  uint32_t async_intr_size;
  uint32_t profile_size;
  uint32_t max_gpr_count;
  uint32_t reserved[4];
  char implementation_id[RISCV_DIFFTEST_IMPLEMENTATION_ID_SIZE];
} riscv_difftest_interface_t;

typedef struct {
  uint64_t valid_fields;
  uint32_t gpr_valid_mask;
  uint32_t pc;
  uint32_t gpr[RISCV_DIFFTEST_MAX_GPRS];
  uint32_t fcsr;
  uint32_t priv;
  uint64_t fpr[RISCV_DIFFTEST_FPRS];
  uint64_t mcycle;
  uint64_t minstret;
  uint32_t mstatus;
  uint32_t mtvec;
  uint32_t mepc;
  uint32_t mcause;
  uint32_t mtval;
  uint32_t medeleg;
  uint32_t mideleg;
  uint32_t mie;
  uint32_t stvec;
  uint32_t sepc;
  uint32_t scause;
  uint32_t stval;
  uint32_t sscratch;
  uint32_t satp;
  uint32_t mscratch;
  uint32_t menvcfgh;
  uint32_t mcounteren;
  uint32_t scounteren;
  uint32_t mcountinhibit;
  uint32_t reserved_tail;
} riscv_difftest_arch_state_t;

typedef struct {
  uint32_t abi_version;
  uint32_t struct_size;
  uint64_t sequence;
  riscv_difftest_arch_state_t state;
} riscv_difftest_observation_t;

typedef struct {
  uint32_t abi_version;
  uint32_t struct_size;
  riscv_difftest_arch_state_t state;
} riscv_difftest_sync_state_t;

typedef struct {
  uint32_t abi_version;
  uint32_t struct_size;
  uint64_t sequence;
  uint32_t instruction_pc;
  uint32_t instruction_bits;
  uint32_t instruction_length;
  uint32_t instruction_valid;
  uint32_t disposition;
  uint32_t skip_reason;
  uint32_t reserved[6];
} riscv_difftest_arch_step_t;

typedef struct {
  uint32_t abi_version;
  uint32_t struct_size;
  uint64_t sequence;
  uint32_t interrupt_code;
  uint32_t pretrap_pc;
  uint32_t reserved[4];
} riscv_difftest_async_intr_t;

typedef int (*difftest_query_interface_t)(uint32_t,
    riscv_difftest_interface_t *);
typedef int (*difftest_init_profile_t)(const riscv_difftest_profile_t *);
typedef int (*difftest_get_observation_t)(riscv_difftest_observation_t *);
typedef int (*difftest_set_sync_state_t)(const riscv_difftest_sync_state_t *);
typedef int (*difftest_arch_step_t)(const riscv_difftest_arch_step_t *,
    const riscv_difftest_sync_state_t *, riscv_difftest_observation_t *);
typedef int (*difftest_async_intr_t)(const riscv_difftest_async_intr_t *,
    riscv_difftest_observation_t *);

#if defined(__cplusplus)
#define RISCV_DIFFTEST_STATIC_ASSERT(cond, message) static_assert(cond, message)
#else
#define RISCV_DIFFTEST_STATIC_ASSERT(cond, message) _Static_assert(cond, message)
#endif

RISCV_DIFFTEST_STATIC_ASSERT(sizeof(riscv_difftest_profile_t) == 80,
    "unexpected DiffTest profile ABI size");
RISCV_DIFFTEST_STATIC_ASSERT(sizeof(riscv_difftest_interface_t) == 160,
    "unexpected DiffTest interface ABI size");
RISCV_DIFFTEST_STATIC_ASSERT(sizeof(riscv_difftest_arch_state_t) == 504,
    "unexpected DiffTest architecture-state ABI size");
RISCV_DIFFTEST_STATIC_ASSERT(sizeof(riscv_difftest_observation_t) == 520,
    "unexpected DiffTest observation ABI size");
RISCV_DIFFTEST_STATIC_ASSERT(sizeof(riscv_difftest_sync_state_t) == 512,
    "unexpected DiffTest sync-state ABI size");
RISCV_DIFFTEST_STATIC_ASSERT(sizeof(riscv_difftest_arch_step_t) == 64,
    "unexpected DiffTest ARCH_STEP ABI size");
RISCV_DIFFTEST_STATIC_ASSERT(sizeof(riscv_difftest_async_intr_t) == 40,
    "unexpected DiffTest ASYNC_INTR ABI size");
RISCV_DIFFTEST_STATIC_ASSERT(offsetof(riscv_difftest_arch_state_t, fpr) == 152,
    "unexpected DiffTest FPR offset");
RISCV_DIFFTEST_STATIC_ASSERT(offsetof(riscv_difftest_arch_state_t, mcycle) == 408,
    "unexpected DiffTest mcycle offset");
RISCV_DIFFTEST_STATIC_ASSERT(offsetof(riscv_difftest_arch_state_t, mstatus) == 424,
    "unexpected DiffTest CSR offset");

#undef RISCV_DIFFTEST_STATIC_ASSERT

#endif
