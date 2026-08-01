/***************************************************************************************
* RISC-V F/D architectural semantics backed by Berkeley SoftFloat.
***************************************************************************************/

#include "local-include/fp.h"
#include <isa.h>
#include <memory/vaddr.h>
#include <softfloat.h>

#define MSTATUS_FS_MASK 0x00006000u
#define MSTATUS_FS_DIRTY MSTATUS_FS_MASK
#define MSTATUS_SD 0x80000000u
#define F32_CANONICAL_NAN 0x7fc00000u
#define F64_CANONICAL_NAN UINT64_C(0x7ff8000000000000)

static void fp_require_enabled(void) {
  if ((cpu.mstatus & MSTATUS_FS_MASK) == 0) {
    riscv_raise_illegal_instruction();
  }
}

word_t fp_normalize_mstatus(word_t value) {
  value &= ~MSTATUS_SD;
  if ((value & MSTATUS_FS_MASK) == MSTATUS_FS_DIRTY) {
    value |= MSTATUS_SD;
  }
  return value;
}

static void fp_mark_dirty(void) {
  cpu.mstatus |= MSTATUS_FS_DIRTY;
  cpu.mstatus = fp_normalize_mstatus(cpu.mstatus);
}

static uint_fast8_t fp_resolve_rm(uint32_t rm) {
  uint_fast8_t mode = rm == 7 ? (cpu.fcsr >> 5) & 0x7 : rm;
  if (mode > 4) riscv_raise_illegal_instruction();
  return mode;
}

static uint_fast8_t fp_begin_rm(uint32_t rm) {
  fp_require_enabled();
  uint_fast8_t mode = fp_resolve_rm(rm);
  softfloat_detectTininess = softfloat_tininess_afterRounding;
  softfloat_roundingMode = mode;
  softfloat_exceptionFlags = 0;
  return mode;
}

static void fp_begin(void) {
  fp_require_enabled();
  softfloat_detectTininess = softfloat_tininess_afterRounding;
  softfloat_exceptionFlags = 0;
}

static void fp_finish(void) {
  uint_fast8_t flags = softfloat_exceptionFlags & 0x1f;
  if (flags != 0) {
    cpu.fcsr = (cpu.fcsr | flags) & 0xff;
    fp_mark_dirty();
  }
  softfloat_exceptionFlags = 0;
}

static float32_t fp_read_s(int reg) {
  uint64_t raw = cpu.fpr[reg];
  uint32_t value = (raw >> 32) == UINT32_MAX ? raw : F32_CANONICAL_NAN;
  return (float32_t){ .v = value };
}

static float64_t fp_read_d(int reg) {
  return (float64_t){ .v = cpu.fpr[reg] };
}

static void fp_write_s(int reg, float32_t value) {
  cpu.fpr[reg] = UINT64_C(0xffffffff00000000) | value.v;
  fp_mark_dirty();
}

static void fp_write_d(int reg, float64_t value) {
  cpu.fpr[reg] = value.v;
  fp_mark_dirty();
}

void fp_init(void) {
  memset(cpu.fpr, 0, sizeof(cpu.fpr));
  cpu.fcsr = 0;
  softfloat_detectTininess = softfloat_tininess_afterRounding;
  softfloat_roundingMode = softfloat_round_near_even;
  softfloat_exceptionFlags = 0;
}

word_t fp_csr_read(uint32_t addr) {
  fp_require_enabled();
  switch (addr) {
    case FP_CSR_FFLAGS: return cpu.fcsr & 0x1f;
    case FP_CSR_FRM:    return (cpu.fcsr >> 5) & 0x7;
    case FP_CSR_FCSR:   return cpu.fcsr & 0xff;
    default: panic("unsupported floating-point CSR 0x%03x", addr);
  }
}

void fp_csr_write(uint32_t addr, word_t value) {
  fp_require_enabled();
  switch (addr) {
    case FP_CSR_FFLAGS:
      cpu.fcsr = (cpu.fcsr & 0xe0) | (value & 0x1f);
      break;
    case FP_CSR_FRM:
      cpu.fcsr = (cpu.fcsr & 0x1f) | ((value & 0x7) << 5);
      break;
    case FP_CSR_FCSR:
      cpu.fcsr = value & 0xff;
      break;
    default:
      panic("unsupported floating-point CSR 0x%03x", addr);
  }
  fp_mark_dirty();
}

void fp_load_s(int rd, vaddr_t addr) {
  fp_require_enabled();
  fp_write_s(rd, (float32_t){ .v = vaddr_read(addr, 4) });
}

void fp_store_s(int rs2, vaddr_t addr) {
  fp_require_enabled();
  vaddr_write(addr, 4, (uint32_t)cpu.fpr[rs2]);
}

void fp_load_d(int rd, vaddr_t addr) {
  fp_require_enabled();
  vaddr_check_access(addr, 8, MEM_TYPE_READ);
  uint64_t value = vaddr_read(addr, 4);
  value |= (uint64_t)vaddr_read(addr + 4, 4) << 32;
  fp_write_d(rd, (float64_t){ .v = value });
}

void fp_store_d(int rs2, vaddr_t addr) {
  fp_require_enabled();
  vaddr_check_access(addr, 8, MEM_TYPE_WRITE);
  uint64_t value = cpu.fpr[rs2];
  vaddr_write(addr, 4, (uint32_t)value);
  vaddr_write(addr + 4, 4, value >> 32);
}

void fp_binary_s(int rd, int rs1, int rs2, uint32_t rm, fp_binary_op_t op) {
  fp_begin_rm(rm);
  float32_t a = fp_read_s(rs1);
  float32_t b = fp_read_s(rs2);
  float32_t result;
  switch (op) {
    case FP_BIN_ADD: result = f32_add(a, b); break;
    case FP_BIN_SUB: result = f32_sub(a, b); break;
    case FP_BIN_MUL: result = f32_mul(a, b); break;
    case FP_BIN_DIV: result = f32_div(a, b); break;
    default: panic("invalid binary F operation %d", op);
  }
  fp_write_s(rd, result);
  fp_finish();
}

void fp_binary_d(int rd, int rs1, int rs2, uint32_t rm, fp_binary_op_t op) {
  fp_begin_rm(rm);
  float64_t a = fp_read_d(rs1);
  float64_t b = fp_read_d(rs2);
  float64_t result;
  switch (op) {
    case FP_BIN_ADD: result = f64_add(a, b); break;
    case FP_BIN_SUB: result = f64_sub(a, b); break;
    case FP_BIN_MUL: result = f64_mul(a, b); break;
    case FP_BIN_DIV: result = f64_div(a, b); break;
    default: panic("invalid binary D operation %d", op);
  }
  fp_write_d(rd, result);
  fp_finish();
}

void fp_sqrt_s(int rd, int rs1, uint32_t rm) {
  fp_begin_rm(rm);
  fp_write_s(rd, f32_sqrt(fp_read_s(rs1)));
  fp_finish();
}

void fp_sqrt_d(int rd, int rs1, uint32_t rm) {
  fp_begin_rm(rm);
  fp_write_d(rd, f64_sqrt(fp_read_d(rs1)));
  fp_finish();
}

void fp_fma_s(int rd, int rs1, int rs2, int rs3, uint32_t rm,
    bool negate_product, bool negate_addend) {
  fp_begin_rm(rm);
  float32_t a = fp_read_s(rs1);
  float32_t b = fp_read_s(rs2);
  float32_t c = fp_read_s(rs3);
  if (negate_product) a.v ^= UINT32_C(0x80000000);
  if (negate_addend) c.v ^= UINT32_C(0x80000000);
  fp_write_s(rd, f32_mulAdd(a, b, c));
  fp_finish();
}

void fp_fma_d(int rd, int rs1, int rs2, int rs3, uint32_t rm,
    bool negate_product, bool negate_addend) {
  fp_begin_rm(rm);
  float64_t a = fp_read_d(rs1);
  float64_t b = fp_read_d(rs2);
  float64_t c = fp_read_d(rs3);
  if (negate_product) a.v ^= UINT64_C(0x8000000000000000);
  if (negate_addend) c.v ^= UINT64_C(0x8000000000000000);
  fp_write_d(rd, f64_mulAdd(a, b, c));
  fp_finish();
}

void fp_sgnj_s(int rd, int rs1, int rs2, fp_sgnj_op_t op) {
  fp_begin();
  uint32_t a = fp_read_s(rs1).v;
  uint32_t b = fp_read_s(rs2).v;
  uint32_t sign;
  switch (op) {
    case FP_SGNJ_COPY:   sign = b; break;
    case FP_SGNJ_NEGATE: sign = ~b; break;
    case FP_SGNJ_XOR:    sign = a ^ b; break;
    default: panic("invalid F sign-injection operation %d", op);
  }
  fp_write_s(rd, (float32_t){ .v = (a & UINT32_C(0x7fffffff)) |
      (sign & UINT32_C(0x80000000)) });
  fp_finish();
}

void fp_sgnj_d(int rd, int rs1, int rs2, fp_sgnj_op_t op) {
  fp_begin();
  uint64_t a = fp_read_d(rs1).v;
  uint64_t b = fp_read_d(rs2).v;
  uint64_t sign;
  switch (op) {
    case FP_SGNJ_COPY:   sign = b; break;
    case FP_SGNJ_NEGATE: sign = ~b; break;
    case FP_SGNJ_XOR:    sign = a ^ b; break;
    default: panic("invalid D sign-injection operation %d", op);
  }
  fp_write_d(rd, (float64_t){ .v = (a & UINT64_C(0x7fffffffffffffff)) |
      (sign & UINT64_C(0x8000000000000000)) });
  fp_finish();
}

static bool f32_is_nan_bits(uint32_t value) {
  return (value & UINT32_C(0x7fffffff)) > UINT32_C(0x7f800000);
}

static bool f64_is_nan_bits(uint64_t value) {
  return (value & UINT64_C(0x7fffffffffffffff)) > UINT64_C(0x7ff0000000000000);
}

void fp_minmax_s(int rd, int rs1, int rs2, bool is_max) {
  fp_begin();
  float32_t a = fp_read_s(rs1);
  float32_t b = fp_read_s(rs2);
  bool nan_a = f32_is_nan_bits(a.v);
  bool nan_b = f32_is_nan_bits(b.v);
  if ((nan_a && f32_isSignalingNaN(a)) || (nan_b && f32_isSignalingNaN(b))) {
    softfloat_exceptionFlags |= softfloat_flag_invalid;
  }

  float32_t result;
  if (nan_a && nan_b) {
    result.v = F32_CANONICAL_NAN;
  } else if (nan_a) {
    result = b;
  } else if (nan_b) {
    result = a;
  } else if (((a.v | b.v) << 1) == 0) {
    result.v = is_max ? (a.v & b.v) : (a.v | b.v);
  } else {
    bool a_less = f32_lt(a, b);
    result = is_max ? (a_less ? b : a) : (a_less ? a : b);
  }
  fp_write_s(rd, result);
  fp_finish();
}

void fp_minmax_d(int rd, int rs1, int rs2, bool is_max) {
  fp_begin();
  float64_t a = fp_read_d(rs1);
  float64_t b = fp_read_d(rs2);
  bool nan_a = f64_is_nan_bits(a.v);
  bool nan_b = f64_is_nan_bits(b.v);
  if ((nan_a && f64_isSignalingNaN(a)) || (nan_b && f64_isSignalingNaN(b))) {
    softfloat_exceptionFlags |= softfloat_flag_invalid;
  }

  float64_t result;
  if (nan_a && nan_b) {
    result.v = F64_CANONICAL_NAN;
  } else if (nan_a) {
    result = b;
  } else if (nan_b) {
    result = a;
  } else if (((a.v | b.v) << 1) == 0) {
    result.v = is_max ? (a.v & b.v) : (a.v | b.v);
  } else {
    bool a_less = f64_lt(a, b);
    result = is_max ? (a_less ? b : a) : (a_less ? a : b);
  }
  fp_write_d(rd, result);
  fp_finish();
}

word_t fp_compare_s(int rs1, int rs2, fp_compare_op_t op) {
  fp_begin();
  float32_t a = fp_read_s(rs1);
  float32_t b = fp_read_s(rs2);
  word_t result;
  switch (op) {
    case FP_CMP_EQ: result = f32_eq(a, b); break;
    case FP_CMP_LT: result = f32_lt(a, b); break;
    case FP_CMP_LE: result = f32_le(a, b); break;
    default: panic("invalid F comparison %d", op);
  }
  fp_finish();
  return result;
}

word_t fp_compare_d(int rs1, int rs2, fp_compare_op_t op) {
  fp_begin();
  float64_t a = fp_read_d(rs1);
  float64_t b = fp_read_d(rs2);
  word_t result;
  switch (op) {
    case FP_CMP_EQ: result = f64_eq(a, b); break;
    case FP_CMP_LT: result = f64_lt(a, b); break;
    case FP_CMP_LE: result = f64_le(a, b); break;
    default: panic("invalid D comparison %d", op);
  }
  fp_finish();
  return result;
}

static word_t classify_f32(uint32_t value) {
  bool sign = value >> 31;
  uint32_t exp = (value >> 23) & 0xff;
  uint32_t frac = value & UINT32_C(0x7fffff);
  if (exp == 0xff) {
    if (frac == 0) return 1u << (sign ? 0 : 7);
    return 1u << ((frac & UINT32_C(0x400000)) ? 9 : 8);
  }
  if (exp == 0) {
    if (frac == 0) return 1u << (sign ? 3 : 4);
    return 1u << (sign ? 2 : 5);
  }
  return 1u << (sign ? 1 : 6);
}

static word_t classify_f64(uint64_t value) {
  bool sign = value >> 63;
  uint32_t exp = (value >> 52) & 0x7ff;
  uint64_t frac = value & UINT64_C(0x000fffffffffffff);
  if (exp == 0x7ff) {
    if (frac == 0) return 1u << (sign ? 0 : 7);
    return 1u << ((frac & UINT64_C(0x0008000000000000)) ? 9 : 8);
  }
  if (exp == 0) {
    if (frac == 0) return 1u << (sign ? 3 : 4);
    return 1u << (sign ? 2 : 5);
  }
  return 1u << (sign ? 1 : 6);
}

word_t fp_classify_s(int rs1) {
  fp_require_enabled();
  return classify_f32(fp_read_s(rs1).v);
}

word_t fp_classify_d(int rs1) {
  fp_require_enabled();
  return classify_f64(fp_read_d(rs1).v);
}

word_t fp_move_x_w(int rs1) {
  fp_require_enabled();
  return (uint32_t)cpu.fpr[rs1];
}

void fp_move_w_x(int rd, word_t value) {
  fp_require_enabled();
  fp_write_s(rd, (float32_t){ .v = value });
}

word_t fp_to_i_s(int rs1, uint32_t rm, bool is_unsigned) {
  uint_fast8_t mode = fp_begin_rm(rm);
  float32_t value = fp_read_s(rs1);
  word_t result = is_unsigned ? (uint32_t)f32_to_ui32(value, mode, true) :
      (uint32_t)f32_to_i32(value, mode, true);
  fp_finish();
  return result;
}

word_t fp_to_i_d(int rs1, uint32_t rm, bool is_unsigned) {
  uint_fast8_t mode = fp_begin_rm(rm);
  float64_t value = fp_read_d(rs1);
  word_t result = is_unsigned ? (uint32_t)f64_to_ui32(value, mode, true) :
      (uint32_t)f64_to_i32(value, mode, true);
  fp_finish();
  return result;
}

void fp_from_i_s(int rd, word_t value, uint32_t rm, bool is_unsigned) {
  fp_begin_rm(rm);
  float32_t result = is_unsigned ? ui32_to_f32(value) : i32_to_f32((int32_t)value);
  fp_write_s(rd, result);
  fp_finish();
}

void fp_from_i_d(int rd, word_t value, uint32_t rm, bool is_unsigned) {
  fp_begin_rm(rm);
  float64_t result = is_unsigned ? ui32_to_f64(value) : i32_to_f64((int32_t)value);
  fp_write_d(rd, result);
  fp_finish();
}

void fp_convert_s_d(int rd, int rs1, uint32_t rm) {
  fp_begin_rm(rm);
  fp_write_s(rd, f64_to_f32(fp_read_d(rs1)));
  fp_finish();
}

void fp_convert_d_s(int rd, int rs1, uint32_t rm) {
  fp_begin_rm(rm);
  fp_write_d(rd, f32_to_f64(fp_read_s(rs1)));
  fp_finish();
}
