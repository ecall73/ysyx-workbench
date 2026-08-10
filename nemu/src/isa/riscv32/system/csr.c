#include <isa.h>
#include <cpu/difftest.h>
#include "../local-include/csr.h"
#include "../local-include/fp.h"
#include "../local-include/state.h"

#define SSTATUS_MASK \
  (MSTATUS_SIE | MSTATUS_SPIE | MSTATUS_SPP | MSTATUS_FS | \
   MSTATUS_SUM | MSTATUS_MXR | MSTATUS_SD)
#define SSTATUS_WRITABLE (SSTATUS_MASK & ~MSTATUS_SD)
#define MSTATUS_WRITABLE \
  (SSTATUS_WRITABLE | MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPP | \
   MSTATUS_MPRV | MSTATUS_TVM | MSTATUS_TW | MSTATUS_TSR)
#define MIE_MASK (MIP_SSIP | MIP_MSIP | MIP_STIP | MIP_MTIP | MIP_SEIP)
#define COUNTEREN_MASK 0x7u
#define MCOUNTINHIBIT_MASK (MCOUNTINHIBIT_CY | MCOUNTINHIBIT_IR)
#define MISA_RV32GC 0x4014112du
#define MIDELEG_MASK (MIP_SSIP | MIP_STIP | MIP_SEIP)
#define MEDELEG_MASK \
  ((1u << 0) | (1u << 1) | (1u << 2) | (1u << 3) | \
   (1u << 4) | (1u << 5) | (1u << 6) | (1u << 7) | \
   (1u << 8) | (1u << 9) | (1u << 12) | (1u << 13) | (1u << 15))

static word_t normalize_mstatus(word_t value) {
  value = fp_normalize_mstatus(value);
  word_t mpp = (value & MSTATUS_MPP) >> 11;
  if (mpp != MODE_U && mpp != MODE_S && mpp != MODE_M) {
    value &= ~MSTATUS_MPP;
  }
  return value;
}

static int counter_access_index(uint32_t addr) {
  switch (addr) {
    case CSR_CYCLE:
    case CSR_CYCLEH:   return 0;
    case CSR_TIME:
    case CSR_TIMEH:    return 1;
    case CSR_INSTRET:
    case CSR_INSTRETH: return 2;
    default:           return -1;
  }
}

static uint64_t replace_counter_half(uint64_t old, word_t value, bool upper) {
  return upper ? ((uint64_t)value << 32) | (uint32_t)old
               : (old & UINT64_C(0xffffffff00000000)) | value;
}

static void csr_check_access(uint32_t addr, bool write) {
  word_t required_priv = (addr >> 8) & 0x3;
  if (cpu.priv < required_priv) riscv_raise_illegal_instruction();
  if (addr == CSR_SATP && cpu.priv == MODE_S &&
      (cpu.mstatus & MSTATUS_TVM)) {
    riscv_raise_illegal_instruction();
  }
  if (write) {
    if (((addr >> 10) & 0x3) == 0x3) riscv_raise_illegal_instruction();
  }
  int counter = counter_access_index(addr);
  if (counter >= 0) {
    bool enabled = cpu.priv == MODE_M ||
        (cpu.priv == MODE_S && (cpu.mcounteren & (1u << counter))) ||
        (cpu.priv == MODE_U && (cpu.mcounteren & (1u << counter)) &&
         (cpu.scounteren & (1u << counter)));
    if (!enabled) riscv_raise_illegal_instruction();
  }
  if ((addr == CSR_STIMECMP || addr == CSR_STIMECMPH) &&
      cpu.priv != MODE_M) {
    if (!(cpu.menvcfgh & MENVCFGH_STCE) ||
        !(cpu.mcounteren & (1u << 1))) {
      riscv_raise_illegal_instruction();
    }
  }
}

void csr_validate_access(uint32_t addr, bool write) {
  csr_check_access(addr, write);
}

word_t csr_read(uint32_t addr) {
  csr_check_access(addr, false);
  switch (addr) {
    case CSR_FFLAGS:
    case CSR_FRM:
    case CSR_FCSR:       return fp_csr_read(addr);
    case CSR_SSTATUS:    return cpu.mstatus & SSTATUS_MASK;
    case CSR_SIE:        return cpu.mie & cpu.mideleg;
    case CSR_STVEC:      return cpu.stvec;
    case CSR_SCOUNTEREN: return cpu.scounteren;
    case CSR_SSCRATCH:   return cpu.sscratch;
    case CSR_SEPC:       return cpu.sepc;
    case CSR_SCAUSE:     return cpu.scause;
    case CSR_STVAL:      return cpu.stval;
    case CSR_SIP:
      // Pending interrupts are DUT-owned and delivered to the reference only
      // through ASYNC_INTR events.
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_PENDING_OWNED);
      return riscv_sip_value();
    case CSR_STIMECMP:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_TIMER_OWNED);
      return (word_t)cpu.stimecmp;
    case CSR_STIMECMPH:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_TIMER_OWNED);
      return (word_t)(cpu.stimecmp >> 32);
    case CSR_SATP:       return cpu.satp;
    case CSR_MSTATUS:    return cpu.mstatus;
    case CSR_MEDELEG:    return cpu.medeleg;
    case CSR_MIDELEG:    return cpu.mideleg;
    case CSR_MIE:        return cpu.mie;
    case CSR_MTVEC:      return cpu.mtvec;
    case CSR_MCOUNTEREN: return cpu.mcounteren;
    case CSR_MCOUNTINHIBIT: return cpu.mcountinhibit;
    case CSR_MENVCFG:    return 0;
    case CSR_MENVCFGH:   return cpu.menvcfgh;
    case CSR_MSCRATCH:   return cpu.mscratch;
    case CSR_MEPC:       return cpu.mepc;
    case CSR_MCAUSE:     return cpu.mcause;
    case CSR_MTVAL:      return cpu.mtval;
    case CSR_MIP:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_PENDING_OWNED);
      return riscv_mip_value();
    case CSR_TIME:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_TIMER_OWNED);
      return (word_t)cpu.mtime;
    case CSR_TIMEH:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_TIMER_OWNED);
      return (word_t)(cpu.mtime >> 32);
    case CSR_CYCLE:     return (word_t)cpu.mcycle;
    case CSR_CYCLEH:    return (word_t)(cpu.mcycle >> 32);
    case CSR_INSTRET:   return (word_t)cpu.minstret;
    case CSR_INSTRETH:  return (word_t)(cpu.minstret >> 32);
    case CSR_MCYCLE:    return (word_t)cpu.mcycle;
    case CSR_MCYCLEH:   return (word_t)(cpu.mcycle >> 32);
    case CSR_MINSTRET:  return (word_t)cpu.minstret;
    case CSR_MINSTRETH: return (word_t)(cpu.minstret >> 32);
    // Profile-owned fixed CSRs may differ across implementations. Return the
    // local value, then synchronize the instruction's architectural effects.
    case CSR_MISA:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_PROFILE_OWNED_MISA);
      return MISA_RV32GC;
    case CSR_MVENDORID:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_PROFILE_OWNED_STATIC);
      return 0x79737978;
    case CSR_MARCHID:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_PROFILE_OWNED_STATIC);
      return 26030082;
    case CSR_MIMPID:
    case CSR_MHARTID:
    case CSR_MCONFIGPTR:
    case CSR_MSTATUSH:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_PROFILE_OWNED_STATIC);
      return 0;
    default:
      riscv_raise_illegal_instruction();
  }
}

void csr_write(uint32_t addr, word_t data) {
  csr_check_access(addr, true);
  switch (addr) {
    case CSR_FFLAGS:
    case CSR_FRM:
    case CSR_FCSR:
      fp_csr_write(addr, data);
      break;
    case CSR_SSTATUS:
      cpu.mstatus = normalize_mstatus(
          (cpu.mstatus & ~SSTATUS_WRITABLE) | (data & SSTATUS_WRITABLE));
      break;
    case CSR_SIE:
      cpu.mie = (cpu.mie & ~cpu.mideleg) | (data & cpu.mideleg & MIE_MASK);
      break;
    case CSR_STVEC:      cpu.stvec = data & ~2u; break;
    case CSR_SCOUNTEREN: cpu.scounteren = data & COUNTEREN_MASK; break;
    case CSR_SSCRATCH:   cpu.sscratch = data; break;
    case CSR_SEPC:       cpu.sepc = data & ~1u; break;
    case CSR_SCAUSE:     cpu.scause = data; break;
    case CSR_STVAL:      cpu.stval = data; break;
    case CSR_SIP: {
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_PENDING_OWNED);
      word_t writable = cpu.mideleg & MIP_SSIP;
      if (writable) cpu.ssip = (data & MIP_SSIP) != 0;
      break;
    }
    case CSR_STIMECMP:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_TIMER_OWNED);
      cpu.stimecmp = (cpu.stimecmp & ~UINT64_C(0xffffffff)) | data;
      break;
    case CSR_STIMECMPH:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_TIMER_OWNED);
      cpu.stimecmp = ((uint64_t)data << 32) | (uint32_t)cpu.stimecmp;
      break;
    case CSR_SATP:       cpu.satp = data; break;
    case CSR_MSTATUS:
      cpu.mstatus = normalize_mstatus(data & MSTATUS_WRITABLE);
      break;
    case CSR_MEDELEG:    cpu.medeleg = data & MEDELEG_MASK; break;
    case CSR_MIDELEG:    cpu.mideleg = data & MIDELEG_MASK; break;
    case CSR_MIE:        cpu.mie = data & MIE_MASK; break;
    case CSR_MTVEC:      cpu.mtvec = data & ~2u; break;
    case CSR_MCOUNTEREN: cpu.mcounteren = data & COUNTEREN_MASK; break;
    case CSR_MCOUNTINHIBIT:
      cpu.mcountinhibit = data & MCOUNTINHIBIT_MASK;
      riscv_record_counter_write(addr);
      break;
    case CSR_MENVCFG:    break;
    case CSR_MENVCFGH:
      cpu.menvcfgh = data & MENVCFGH_STCE;
      break;
    case CSR_MSCRATCH:   cpu.mscratch = data; break;
    case CSR_MEPC:       cpu.mepc = data & ~1u; break;
    case CSR_MCAUSE:     cpu.mcause = data; break;
    case CSR_MTVAL:      cpu.mtval = data; break;
    case CSR_MIP:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_PENDING_OWNED);
      cpu.ssip = (data & MIP_SSIP) != 0;
      break;
    case CSR_MISA:
      difftest_skip_ref_reason(RISCV_DIFFTEST_SKIP_PROFILE_OWNED_MISA);
      break;
    case CSR_MCYCLE:
      cpu.mcycle = replace_counter_half(cpu.mcycle, data, false);
      riscv_record_counter_write(addr);
      break;
    case CSR_MCYCLEH:
      cpu.mcycle = replace_counter_half(cpu.mcycle, data, true);
      riscv_record_counter_write(addr);
      break;
    case CSR_MINSTRET:
      cpu.minstret = replace_counter_half(cpu.minstret, data, false);
      riscv_record_counter_write(addr);
      break;
    case CSR_MINSTRETH:
      cpu.minstret = replace_counter_half(cpu.minstret, data, true);
      riscv_record_counter_write(addr);
      break;
    case CSR_MVENDORID:
    case CSR_MARCHID:
    case CSR_MIMPID:
    case CSR_MHARTID:
    case CSR_MCONFIGPTR:
    case CSR_MSTATUSH:
    case CSR_TIME:
    case CSR_TIMEH:
    case CSR_CYCLE:
    case CSR_CYCLEH:
    case CSR_INSTRET:
    case CSR_INSTRETH:
      riscv_raise_illegal_instruction();
    default:
      riscv_raise_illegal_instruction();
  }
}
