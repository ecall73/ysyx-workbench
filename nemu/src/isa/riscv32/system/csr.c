#include <isa.h>
#include <cpu/difftest.h>
#include "../local-include/csr.h"
#include "../local-include/fp.h"

#define SSTATUS_MASK \
  (MSTATUS_SIE | MSTATUS_SPIE | MSTATUS_SPP | MSTATUS_FS | \
   MSTATUS_SUM | MSTATUS_MXR | MSTATUS_SD)
#define SSTATUS_WRITABLE (SSTATUS_MASK & ~MSTATUS_SD)
#define MSTATUS_WRITABLE \
  (SSTATUS_WRITABLE | MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPP | MSTATUS_MPRV)
#define MIE_MASK (MIP_SSIP | MIP_STIP | MIP_MTIP | MIP_SEIP)
#define MCOUNTEREN_MASK (1u << 1)
#define MIDELEG_MASK (MIP_SSIP | MIP_STIP | MIP_SEIP)
#define MEDELEG_MASK \
  ((1u << 0) | (1u << 1) | (1u << 2) | (1u << 3) | \
   (1u << 4) | (1u << 5) | (1u << 6) | (1u << 7) | \
   (1u << 8) | (1u << 9) | (1u << 12) | (1u << 13) | (1u << 15))

static word_t normalize_mstatus(word_t value) {
  value = fp_normalize_mstatus(value);
  word_t mpp = (value & MSTATUS_MPP) >> 11;
  if (mpp != MODE_U && mpp != MODE_S && mpp != MODE_M) {
    value = (value & ~MSTATUS_MPP) | (MODE_M << 11);
  }
  return value;
}

static void csr_check_access(uint32_t addr, bool write) {
  word_t required_priv = (addr >> 8) & 0x3;
  Assert(cpu.priv >= required_priv,
      "CSR privilege violation: pc=" FMT_WORD " priv=%u csr=0x%03x",
      cpu.pc, cpu.priv, addr);
  if (write) {
    Assert(((addr >> 10) & 0x3) != 0x3,
        "write read-only CSR: pc=" FMT_WORD " csr=0x%03x", cpu.pc, addr);
  }
  if (addr == CSR_TIME || addr == CSR_TIMEH) {
    Assert(cpu.priv == MODE_M ||
        (cpu.priv == MODE_S && (cpu.mcounteren & MCOUNTEREN_MASK)),
        "counter access disabled: pc=" FMT_WORD " priv=%u csr=0x%03x",
        cpu.pc, cpu.priv, addr);
  }
  if ((addr == CSR_STIMECMP || addr == CSR_STIMECMPH) &&
      cpu.priv != MODE_M) {
    Assert((cpu.menvcfgh & MENVCFGH_STCE) &&
        (cpu.mcounteren & MCOUNTEREN_MASK),
        "stimecmp access disabled: pc=" FMT_WORD " csr=0x%03x",
        cpu.pc, addr);
  }
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
    case CSR_SSCRATCH:   return cpu.sscratch;
    case CSR_SEPC:       return cpu.sepc;
    case CSR_SCAUSE:     return cpu.scause;
    case CSR_STVAL:      return cpu.stval;
    case CSR_SIP:
      // Pending interrupts are owned by NEMU and injected into Spike through
      // difftest_raise_intr(), rather than through Spike's timer model.
      difftest_skip_ref();
      return cpu.mip & cpu.mideleg;
    case CSR_STIMECMP:   return (word_t)cpu.stimecmp;
    case CSR_STIMECMPH:  return (word_t)(cpu.stimecmp >> 32);
    case CSR_SATP:       return cpu.satp;
    case CSR_MSTATUS:    return cpu.mstatus;
    case CSR_MEDELEG:    return cpu.medeleg;
    case CSR_MIDELEG:    return cpu.mideleg;
    case CSR_MIE:        return cpu.mie;
    case CSR_MTVEC:      return cpu.mtvec;
    case CSR_MCOUNTEREN: return cpu.mcounteren;
    case CSR_MENVCFG:    return 0;
    case CSR_MENVCFGH:   return cpu.menvcfgh;
    case CSR_MSCRATCH:   return cpu.mscratch;
    case CSR_MEPC:       return cpu.mepc;
    case CSR_MCAUSE:     return cpu.mcause;
    case CSR_MTVAL:      return cpu.mtval;
    case CSR_MIP:
      difftest_skip_ref();
      return cpu.mip;
    // This NEMU configuration implements zero PMP entries.
    case CSR_PMPCFG0:
    case CSR_PMPADDR0:   return 0;
    case CSR_TIME:
      difftest_skip_ref();
      return (word_t)cpu.mtime;
    case CSR_TIMEH:
      difftest_skip_ref();
      return (word_t)(cpu.mtime >> 32);
    case CSR_MVENDORID:  return 0x79737978;
    case CSR_MARCHID:    return 26030082;
    case CSR_MHARTID:    return 0;
    default:
      Assert(0, "read unsupported CSR: pc=" FMT_WORD " csr=0x%03x", cpu.pc, addr);
      return 0;
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
    case CSR_STVEC:      cpu.stvec = data; break;
    case CSR_SSCRATCH:   cpu.sscratch = data; break;
    case CSR_SEPC:       cpu.sepc = data & ~1u; break;
    case CSR_SCAUSE:     cpu.scause = data; break;
    case CSR_STVAL:      cpu.stval = data; break;
    case CSR_SIP: {
      word_t writable = cpu.mideleg & MIP_SSIP;
      cpu.mip = (cpu.mip & ~writable) | (data & writable);
      break;
    }
    case CSR_STIMECMP:
      cpu.stimecmp = (cpu.stimecmp & ~UINT64_C(0xffffffff)) | data;
      break;
    case CSR_STIMECMPH:
      cpu.stimecmp = ((uint64_t)data << 32) | (uint32_t)cpu.stimecmp;
      break;
    case CSR_SATP:       cpu.satp = data; break;
    case CSR_MSTATUS:
      cpu.mstatus = normalize_mstatus(data & MSTATUS_WRITABLE);
      break;
    case CSR_MEDELEG:    cpu.medeleg = data & MEDELEG_MASK; break;
    case CSR_MIDELEG:    cpu.mideleg = data & MIDELEG_MASK; break;
    case CSR_MIE:        cpu.mie = data & MIE_MASK; break;
    case CSR_MTVEC:      cpu.mtvec = data; break;
    case CSR_MCOUNTEREN: cpu.mcounteren = data & MCOUNTEREN_MASK; break;
    case CSR_MENVCFG:    break;
    case CSR_MENVCFGH:
      cpu.menvcfgh = data & (MENVCFGH_ADUE | MENVCFGH_STCE);
      break;
    case CSR_MSCRATCH:   cpu.mscratch = data; break;
    case CSR_MEPC:       cpu.mepc = data & ~1u; break;
    case CSR_MCAUSE:     cpu.mcause = data; break;
    case CSR_MTVAL:      cpu.mtval = data; break;
    case CSR_MIP:
      cpu.mip = (cpu.mip & ~MIP_SSIP) | (data & MIP_SSIP);
      break;
    case CSR_PMPCFG0:
    case CSR_PMPADDR0:   break;
    case CSR_MVENDORID:
    case CSR_MARCHID:
    case CSR_MHARTID:
    case CSR_TIME:
    case CSR_TIMEH:
      Assert(0, "write read-only CSR: pc=" FMT_WORD " csr=0x%03x data=" FMT_WORD,
          cpu.pc, addr, data);
      break;
    default:
      Assert(0, "write unsupported CSR: pc=" FMT_WORD " csr=0x%03x data=" FMT_WORD,
          cpu.pc, addr, data);
      break;
  }
}
