#ifndef __RISCV32_CSR_H__
#define __RISCV32_CSR_H__

#include <common.h>

enum {
  CSR_FFLAGS      = 0x001,
  CSR_FRM         = 0x002,
  CSR_FCSR        = 0x003,
  CSR_SSTATUS     = 0x100,
  CSR_SIE         = 0x104,
  CSR_STVEC       = 0x105,
  CSR_SCOUNTEREN  = 0x106,
  CSR_SSCRATCH    = 0x140,
  CSR_SEPC        = 0x141,
  CSR_SCAUSE      = 0x142,
  CSR_STVAL       = 0x143,
  CSR_SIP         = 0x144,
  CSR_STIMECMP    = 0x14d,
  CSR_STIMECMPH   = 0x15d,
  CSR_SATP        = 0x180,
  CSR_MSTATUS     = 0x300,
  CSR_MISA        = 0x301,
  CSR_MEDELEG     = 0x302,
  CSR_MIDELEG     = 0x303,
  CSR_MIE         = 0x304,
  CSR_MTVEC       = 0x305,
  CSR_MCOUNTEREN  = 0x306,
  CSR_MENVCFG     = 0x30a,
  CSR_MSTATUSH    = 0x310,
  CSR_MENVCFGH    = 0x31a,
  CSR_MCOUNTINHIBIT = 0x320,
  CSR_MSCRATCH    = 0x340,
  CSR_MEPC        = 0x341,
  CSR_MCAUSE      = 0x342,
  CSR_MTVAL       = 0x343,
  CSR_MIP         = 0x344,
  CSR_MCYCLE      = 0xb00,
  CSR_MINSTRET    = 0xb02,
  CSR_MCYCLEH     = 0xb80,
  CSR_MINSTRETH   = 0xb82,
  CSR_CYCLE       = 0xc00,
  CSR_TIME        = 0xc01,
  CSR_INSTRET     = 0xc02,
  CSR_CYCLEH      = 0xc80,
  CSR_TIMEH       = 0xc81,
  CSR_INSTRETH    = 0xc82,
  CSR_MVENDORID   = 0xf11,
  CSR_MARCHID     = 0xf12,
  CSR_MIMPID      = 0xf13,
  CSR_MHARTID     = 0xf14,
  CSR_MCONFIGPTR  = 0xf15,
};

enum {
  MSTATUS_SIE  = 1u << 1,
  MSTATUS_MIE  = 1u << 3,
  MSTATUS_SPIE = 1u << 5,
  MSTATUS_MPIE = 1u << 7,
  MSTATUS_SPP  = 1u << 8,
  MSTATUS_MPP  = 3u << 11,
  MSTATUS_FS   = 3u << 13,
  MSTATUS_MPRV = 1u << 17,
  MSTATUS_SUM  = 1u << 18,
  MSTATUS_MXR  = 1u << 19,
  MSTATUS_TVM  = 1u << 20,
  MSTATUS_TW   = 1u << 21,
  MSTATUS_TSR  = 1u << 22,
  MSTATUS_SD   = 1u << 31,
};

enum {
  IRQ_SSIP = 1,
  IRQ_MSIP = 3,
  IRQ_MTIP = 7,
  IRQ_STIP = 5,
  IRQ_SEIP = 9,
};

#define MIP_SSIP (1u << IRQ_SSIP)
#define MIP_MSIP (1u << IRQ_MSIP)
#define MIP_STIP (1u << IRQ_STIP)
#define MIP_MTIP (1u << IRQ_MTIP)
#define MIP_SEIP (1u << IRQ_SEIP)

#define MENVCFGH_STCE (1u << 31)

#define MCOUNTINHIBIT_CY (1u << 0)
#define MCOUNTINHIBIT_IR (1u << 2)

word_t csr_read(uint32_t addr);
void csr_write(uint32_t addr, word_t data);
void csr_validate_access(uint32_t addr, bool write);

#endif
