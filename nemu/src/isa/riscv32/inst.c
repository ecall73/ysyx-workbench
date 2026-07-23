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

#include "local-include/reg.h"
#include <cpu/cpu.h>
#include <cpu/ifetch.h>
#include <cpu/decode.h>

#define R(i) gpr(i)
#define Mr vaddr_read
#define Mw vaddr_write

static inline int rvc_regp(uint16_t c, int lsb) {
  return 8 + ((c >> lsb) & 0x7);
}

static inline word_t rvc_imm_ci(uint16_t c) {
  return SEXT((((c >> 12) & 0x1) << 5) | ((c >> 2) & 0x1f), 6);
}

static inline word_t rvc_imm_cj(uint16_t c) {
  uint32_t imm = (((c >> 12) & 0x1) << 11) |
      (((c >> 11) & 0x1) << 4) | (((c >> 9) & 0x3) << 8) |
      (((c >> 8) & 0x1) << 10) | (((c >> 7) & 0x1) << 6) |
      (((c >> 6) & 0x1) << 7) | (((c >> 3) & 0x7) << 1) |
      (((c >> 2) & 0x1) << 5);
  return SEXT(imm, 12);
}

static inline word_t rvc_imm_cb(uint16_t c) {
  uint32_t imm = (((c >> 12) & 0x1) << 8) |
      (((c >> 10) & 0x3) << 3) | (((c >> 5) & 0x3) << 6) |
      (((c >> 3) & 0x3) << 1) | (((c >> 2) & 0x1) << 5);
  return SEXT(imm, 9);
}

enum {
  RVC_TYPE_CI, RVC_TYPE_CIW, RVC_TYPE_CL, RVC_TYPE_CS,
  RVC_TYPE_CJ, RVC_TYPE_CB, RVC_TYPE_CB_SHIFT, RVC_TYPE_CB_IMM,
  RVC_TYPE_CA, RVC_TYPE_CR, RVC_TYPE_CI_SHIFT, RVC_TYPE_CI16SP,
  RVC_TYPE_CI_LWSP, RVC_TYPE_CSS, RVC_TYPE_N,
};

static void decode_rvc_operand(Decode *s, int *rd, word_t *src1,
    word_t *src2, word_t *imm, int type) {
  uint16_t c = s->isa.inst;
  int rs1 = 0;
  int rs2 = 0;
  *rd = 0;

  switch (type) {
    case RVC_TYPE_CI:
      *rd = (c >> 7) & 0x1f;
      *src1 = R(*rd);
      *imm = rvc_imm_ci(c);
      break;
    case RVC_TYPE_CIW:
      *rd = rvc_regp(c, 2);
      *src1 = R(2);
      *imm = (((c >> 7) & 0xf) << 6) | (((c >> 11) & 0x3) << 4) |
          (((c >> 5) & 0x1) << 3) | (((c >> 6) & 0x1) << 2);
      break;
    case RVC_TYPE_CL:
    case RVC_TYPE_CS:
      rs1 = rvc_regp(c, 7);
      rs2 = rvc_regp(c, 2);
      *rd = rs2;
      *src1 = R(rs1);
      *src2 = R(rs2);
      *imm = (((c >> 10) & 0x7) << 3) |
          (((c >> 5) & 0x1) << 6) | (((c >> 6) & 0x1) << 2);
      break;
    case RVC_TYPE_CJ:
      *imm = rvc_imm_cj(c);
      break;
    case RVC_TYPE_CB:
      rs1 = rvc_regp(c, 7);
      *src1 = R(rs1);
      *imm = rvc_imm_cb(c);
      break;
    case RVC_TYPE_CB_SHIFT:
      *rd = rvc_regp(c, 7);
      *src1 = R(*rd);
      *imm = (c >> 2) & 0x1f;
      break;
    case RVC_TYPE_CB_IMM:
      *rd = rvc_regp(c, 7);
      *src1 = R(*rd);
      *imm = rvc_imm_ci(c);
      break;
    case RVC_TYPE_CA:
      *rd = rvc_regp(c, 7);
      rs2 = rvc_regp(c, 2);
      *src1 = R(*rd);
      *src2 = R(rs2);
      break;
    case RVC_TYPE_CR:
      *rd = (c >> 7) & 0x1f;
      rs2 = (c >> 2) & 0x1f;
      *src1 = R(*rd);
      *src2 = R(rs2);
      break;
    case RVC_TYPE_CI_SHIFT:
      *rd = (c >> 7) & 0x1f;
      *src1 = R(*rd);
      *imm = (c >> 2) & 0x1f;
      break;
    case RVC_TYPE_CI16SP: {
      *rd = 2;
      *src1 = R(2);
      uint32_t nzimm = (((c >> 12) & 0x1) << 9) |
          (((c >> 6) & 0x1) << 4) | (((c >> 5) & 0x1) << 6) |
          (((c >> 3) & 0x3) << 7) | (((c >> 2) & 0x1) << 5);
      *imm = SEXT(nzimm, 10);
      break;
    }
    case RVC_TYPE_CI_LWSP:
      *rd = (c >> 7) & 0x1f;
      *src1 = R(2);
      *imm = (((c >> 12) & 0x1) << 5) |
          (((c >> 4) & 0x7) << 2) | (((c >> 2) & 0x3) << 6);
      break;
    case RVC_TYPE_CSS:
      rs2 = (c >> 2) & 0x1f;
      *src1 = R(2);
      *src2 = R(rs2);
      *imm = (((c >> 9) & 0xf) << 2) | (((c >> 7) & 0x3) << 6);
      break;
    case RVC_TYPE_N:
      break;
    default:
      panic("unsupported RVC type = %d", type);
  }
}

static int finish_exec(Decode *s) {
  R(0) = 0;
  Assert((s->dnpc & 0x1) == 0,
      "unaligned dnpc after execute: pc=" FMT_WORD " inst=0x%08x dnpc=" FMT_WORD,
      s->pc, s->isa.inst, s->dnpc);
  return 0;
}

static int decode_exec_rvc(Decode *s) {
  s->dnpc = s->snpc;

#define INSTPAT_INST(s) ((s)->isa.inst)
#define INSTPAT_MATCH(s, name, type, ... /* execute body */ ) { \
  int rd = 0; \
  word_t src1 = 0, src2 = 0, imm = 0; \
  decode_rvc_operand(s, &rd, &src1, &src2, &imm, concat(RVC_TYPE_, type)); \
  __VA_ARGS__ ; \
}

  INSTPAT_START();
  // Quadrant 0
  INSTPAT("000 ???????? ??? 00", c_addi4spn, CIW,
      if (imm == 0) INV(s->pc); else R(rd) = src1 + imm);
  INSTPAT("010 ??? ??? ?? ??? 00", c_lw, CL, R(rd) = Mr(src1 + imm, 4));
  INSTPAT("110 ??? ??? ?? ??? 00", c_sw, CS, Mw(src1 + imm, 4, src2));

  // Quadrant 1
  INSTPAT("000 ? ????? ????? 01", c_addi, CI, R(rd) = src1 + imm);
  INSTPAT("001 ??????????? 01", c_jal, CJ,
      R(1) = s->snpc;
      s->dnpc = s->pc + imm;
#ifdef CONFIG_FTRACE
      ftrace_call(s->pc, s->dnpc);
#endif
  );
  INSTPAT("010 ? ????? ????? 01", c_li, CI, R(rd) = imm);
  INSTPAT("011 ? 00010 ????? 01", c_addi16sp, CI16SP,
      if (imm == 0) INV(s->pc); else R(2) = src1 + imm);
  INSTPAT("011 ? ????? ????? 01", c_lui, CI,
      if (imm == 0) INV(s->pc); else if (rd != 0) R(rd) = imm << 12);
  // For RV32, shamt[5]=1 is custom encoding space and is not implemented.
  INSTPAT("100 0 00??? ????? 01", c_srli, CB_SHIFT, R(rd) = src1 >> imm);
  INSTPAT("100 0 01??? ????? 01", c_srai, CB_SHIFT, R(rd) = (sword_t)src1 >> imm);
  INSTPAT("100 ? 10??? ????? 01", c_andi, CB_IMM, R(rd) = src1 & imm);
  INSTPAT("100 0 11??? 00??? 01", c_sub, CA, R(rd) = src1 - src2);
  INSTPAT("100 0 11??? 01??? 01", c_xor, CA, R(rd) = src1 ^ src2);
  INSTPAT("100 0 11??? 10??? 01", c_or, CA, R(rd) = src1 | src2);
  INSTPAT("100 0 11??? 11??? 01", c_and, CA, R(rd) = src1 & src2);
  INSTPAT("101 ??????????? 01", c_j, CJ, s->dnpc = s->pc + imm);
  INSTPAT("110 ??? ??? ????? 01", c_beqz, CB,
      if (src1 == 0) s->dnpc = s->pc + imm);
  INSTPAT("111 ??? ??? ????? 01", c_bnez, CB,
      if (src1 != 0) s->dnpc = s->pc + imm);

  // Quadrant 2. RV32 shamt[5]=1 belongs to custom encoding space.
  INSTPAT("000 0 ????? ????? 10", c_slli, CI_SHIFT, R(rd) = src1 << imm);
  INSTPAT("010 ? ????? ????? 10", c_lwsp, CI_LWSP,
      if (rd == 0) INV(s->pc); else R(rd) = Mr(src1 + imm, 4));
  INSTPAT("100 0 ????? 00000 10", c_jr, CR,
      if (rd == 0) {
        INV(s->pc);
      } else {
        s->dnpc = src1 & ~1u;
#ifdef CONFIG_FTRACE
        if (rd == 1) ftrace_ret(s->pc);
#endif
      }
  );
  INSTPAT("100 0 ????? ????? 10", c_mv, CR, R(rd) = src2);
  INSTPAT("100 1 00000 00000 10", c_ebreak, N, NEMUTRAP(s->pc, R(10)));
  INSTPAT("100 1 ????? 00000 10", c_jalr, CR,
      R(1) = s->snpc;
      s->dnpc = src1 & ~1u;
#ifdef CONFIG_FTRACE
      ftrace_call(s->pc, s->dnpc);
#endif
  );
  INSTPAT("100 1 ????? ????? 10", c_add, CR, R(rd) = src1 + src2);
  INSTPAT("110 ?????? ????? 10", c_swsp, CSS, Mw(src1 + imm, 4, src2));

  INSTPAT("????????????????", inv, N, INV(s->pc));
  INSTPAT_END();

#undef INSTPAT_MATCH
#undef INSTPAT_INST

  return finish_exec(s);
}

enum {
  TYPE_I, TYPE_U, TYPE_S, TYPE_J, TYPE_B, TYPE_R,
  TYPE_N, // none
};

#define src1R() do { *src1 = R(rs1); } while (0)
#define src2R() do { *src2 = R(rs2); } while (0)
#define immI() do { *imm = SEXT(BITS(i, 31, 20), 12); } while(0)
#define immU() do { *imm = SEXT(BITS(i, 31, 12), 20) << 12; } while(0)
#define immS() do { *imm = (SEXT(BITS(i, 31, 25), 7) << 5) | BITS(i, 11, 7); } while(0)
#define immJ() do { *imm = (SEXT(BITS(i, 31, 31), 1) << 20) | (BITS(i, 19, 12) << 12) | (BITS(i, 20, 20) << 11) | (BITS(i, 30, 21) << 1); } while(0)
#define immB() do { *imm = (SEXT(BITS(i, 31, 31), 1) << 12) | (BITS(i, 7, 7) << 11) | (BITS(i, 30, 25) << 5) | (BITS(i, 11, 8) << 1); } while(0)

static void decode_operand(Decode *s, int *rd, word_t *src1, word_t *src2, word_t *imm, int type) {
  uint32_t i = s->isa.inst;
  int rs1 = BITS(i, 19, 15);
  int rs2 = BITS(i, 24, 20);
  *rd     = BITS(i, 11, 7);
  switch (type) {
    case TYPE_I: src1R();          immI(); break;
    case TYPE_U:                   immU(); break;
    case TYPE_S: src1R(); src2R(); immS(); break;
    case TYPE_J:                   immJ(); break;
    case TYPE_B: src1R(); src2R(); immB(); break;
    case TYPE_R: src1R(); src2R();         break;
    case TYPE_N: break;
    default: panic("unsupported type = %d", type);
  }
}

enum {
  CSR_MSTATUS = 0x300,
  CSR_MSCRATCH = 0x340,
  CSR_SATP    = 0x180,
  CSR_MTVEC   = 0x305,
  CSR_MEPC    = 0x341,
  CSR_MCAUSE  = 0x342,
  CSR_MVENDORID = 0xF11,
  CSR_MARCHID   = 0xF12,
};

static inline word_t csr_read(uint32_t addr) {
  switch (addr) {
    case CSR_MSTATUS: return cpu.mstatus;
    case CSR_MSCRATCH: return cpu.mscratch;
    case CSR_SATP:    return cpu.satp;
    case CSR_MTVEC:   return cpu.mtvec;
    case CSR_MEPC:    return cpu.mepc;
    case CSR_MCAUSE:  return cpu.mcause;
    case CSR_MVENDORID: return 0x79737978;
    case CSR_MARCHID:   return 26030082;
    default:
      Assert(0, "read unsupported CSR: pc=" FMT_WORD " csr=0x%03x", cpu.pc, addr);
      return 0;
  }
}

static inline void csr_write(uint32_t addr, word_t data) {
  switch (addr) {
    case CSR_MSTATUS: cpu.mstatus = data; break;
    case CSR_MSCRATCH: cpu.mscratch = data; break;
    case CSR_SATP:    cpu.satp    = data; break;
    case CSR_MTVEC:   cpu.mtvec   = data; break;
    case CSR_MEPC:    cpu.mepc    = data; break;
    case CSR_MCAUSE:  cpu.mcause  = data; break;
    case CSR_MVENDORID:
    case CSR_MARCHID:
      Assert(0, "write read-only CSR: pc=" FMT_WORD " csr=0x%03x data=" FMT_WORD, cpu.pc, addr, data);
      break;
    default:
      Assert(0, "write unsupported CSR: pc=" FMT_WORD " csr=0x%03x data=" FMT_WORD, cpu.pc, addr, data);
      break;
  }
}

static inline uint32_t csr_addr(const Decode *s) {
  return BITS(s->isa.inst, 31, 20);
}

static int decode_exec(Decode *s) {
  s->dnpc = s->snpc;

#define INSTPAT_INST(s) ((s)->isa.inst)
#define INSTPAT_MATCH(s, name, type, ... /* execute body */ ) { \
  int rd = 0; \
  word_t src1 = 0, src2 = 0, imm = 0; \
  decode_operand(s, &rd, &src1, &src2, &imm, concat(TYPE_, type)); \
  __VA_ARGS__ ; \
}

  INSTPAT_START();
  // RV32I
  INSTPAT("??????? ????? ????? ??? ????? 01101 11", lui    , U, R(rd) = imm);
  INSTPAT("??????? ????? ????? ??? ????? 00101 11", auipc  , U, R(rd) = s->pc + imm);

  INSTPAT("??????? ????? ????? ??? ????? 11011 11", jal    , J,
      R(rd) = s->snpc;
      s->dnpc = s->pc + imm;
#ifdef CONFIG_FTRACE
      if (rd == 1 || rd == 5) ftrace_call(s->pc, s->dnpc);
#endif
  );
  INSTPAT("??????? ????? ????? 000 ????? 11001 11", jalr   , I,
      R(rd) = s->snpc;
      s->dnpc = (src1 + imm) & ~1;
#ifdef CONFIG_FTRACE
      int rs1 = BITS(s->isa.inst, 19, 15);
      if (rd == 0 && rs1 == 1 && imm == 0) ftrace_ret(s->pc);
      else if (rd == 1 || rd == 5) ftrace_call(s->pc, s->dnpc);
#endif
  );

  INSTPAT("??????? ????? ????? 000 ????? 11000 11", beq    , B, if (src1 == src2) s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? 001 ????? 11000 11", bne    , B, if (src1 != src2) s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? 100 ????? 11000 11", blt    , B, if ((sword_t)src1 < (sword_t)src2) s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? 101 ????? 11000 11", bge    , B, if ((sword_t)src1 >= (sword_t)src2) s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? 110 ????? 11000 11", bltu   , B, if (src1 < src2) s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? 111 ????? 11000 11", bgeu   , B, if (src1 >= src2) s->dnpc = s->pc + imm);

  INSTPAT("??????? ????? ????? 000 ????? 00000 11", lb     , I, R(rd) = SEXT(Mr(src1 + imm, 1), 8));
  INSTPAT("??????? ????? ????? 001 ????? 00000 11", lh     , I, R(rd) = SEXT(Mr(src1 + imm, 2), 16));
  INSTPAT("??????? ????? ????? 010 ????? 00000 11", lw     , I, R(rd) = Mr(src1 + imm, 4));
  INSTPAT("??????? ????? ????? 100 ????? 00000 11", lbu    , I, R(rd) = Mr(src1 + imm, 1));
  INSTPAT("??????? ????? ????? 101 ????? 00000 11", lhu    , I, R(rd) = Mr(src1 + imm, 2));

  INSTPAT("??????? ????? ????? 000 ????? 01000 11", sb     , S, Mw(src1 + imm, 1, src2));
  INSTPAT("??????? ????? ????? 001 ????? 01000 11", sh     , S, Mw(src1 + imm, 2, src2));
  INSTPAT("??????? ????? ????? 010 ????? 01000 11", sw     , S, Mw(src1 + imm, 4, src2));

  INSTPAT("??????? ????? ????? 000 ????? 00100 11", addi   , I, R(rd) = src1 + imm);
  INSTPAT("??????? ????? ????? 010 ????? 00100 11", slti   , I, R(rd) = (sword_t)src1 < (sword_t)imm);
  INSTPAT("??????? ????? ????? 011 ????? 00100 11", sltiu  , I, R(rd) = src1 < imm);
  INSTPAT("??????? ????? ????? 100 ????? 00100 11", xori   , I, R(rd) = src1 ^ imm);
  INSTPAT("??????? ????? ????? 110 ????? 00100 11", ori    , I, R(rd) = src1 | imm);
  INSTPAT("??????? ????? ????? 111 ????? 00100 11", andi   , I, R(rd) = src1 & imm);
  INSTPAT("0000000 ????? ????? 001 ????? 00100 11", slli   , I, R(rd) = src1 << imm);
  INSTPAT("0000000 ????? ????? 101 ????? 00100 11", srli   , I, R(rd) = src1 >> imm);
  INSTPAT("0100000 ????? ????? 101 ????? 00100 11", srai   , I, R(rd) = (sword_t)src1 >> imm);

  INSTPAT("0000000 ????? ????? 000 ????? 01100 11", add    , R, R(rd) = src1 + src2);
  INSTPAT("0100000 ????? ????? 000 ????? 01100 11", sub    , R, R(rd) = src1 - src2);
  INSTPAT("0000000 ????? ????? 001 ????? 01100 11", sll    , R, R(rd) = src1 << src2);
  INSTPAT("0000000 ????? ????? 010 ????? 01100 11", slt    , R, R(rd) = (sword_t)src1 < (sword_t)src2);
  INSTPAT("0000000 ????? ????? 011 ????? 01100 11", sltu   , R, R(rd) = src1 < src2);
  INSTPAT("0000000 ????? ????? 100 ????? 01100 11", xor    , R, R(rd) = src1 ^ src2);
  INSTPAT("0000000 ????? ????? 101 ????? 01100 11", srl    , R, R(rd) = src1 >> src2);
  INSTPAT("0100000 ????? ????? 101 ????? 01100 11", sra    , R, R(rd) = (sword_t)src1 >> src2);
  INSTPAT("0000000 ????? ????? 110 ????? 01100 11", or     , R, R(rd) = src1 | src2);
  INSTPAT("0000000 ????? ????? 111 ????? 01100 11", and    , R, R(rd) = src1 & src2);

  INSTPAT("??????? ????? ????? 001 ????? 11100 11", csrrw  , N,
      uint32_t rs1 = BITS(s->isa.inst, 19, 15);
      uint32_t csr = csr_addr(s);
      word_t old = csr_read(csr);
      csr_write(csr, R(rs1));
      R(rd) = old;
  );
  INSTPAT("??????? ????? ????? 010 ????? 11100 11", csrrs  , N,
      uint32_t rs1 = BITS(s->isa.inst, 19, 15);
      uint32_t csr = csr_addr(s);
      word_t old = csr_read(csr);
      if (rs1 != 0) {
        csr_write(csr, old | R(rs1));
      }
      R(rd) = old;
  );
  INSTPAT("??????? ????? ????? 011 ????? 11100 11", csrrc  , N,
      uint32_t rs1 = BITS(s->isa.inst, 19, 15);
      uint32_t csr = csr_addr(s);
      word_t old = csr_read(csr);
      if (rs1 != 0) {
        csr_write(csr, old & ~R(rs1));
      }
      R(rd) = old;
  );
  INSTPAT("??????? ????? ????? 101 ????? 11100 11", csrrwi , N,
      uint32_t csr = csr_addr(s);
      word_t zimm = BITS(s->isa.inst, 19, 15);
      word_t old = csr_read(csr);
      csr_write(csr, zimm);
      R(rd) = old;
  );
  INSTPAT("??????? ????? ????? 110 ????? 11100 11", csrrsi , N,
      uint32_t csr = csr_addr(s);
      word_t zimm = BITS(s->isa.inst, 19, 15);
      word_t old = csr_read(csr);
      if (zimm != 0) {
        csr_write(csr, old | zimm);
      }
      R(rd) = old;
  );
  INSTPAT("??????? ????? ????? 111 ????? 11100 11", csrrci , N,
      uint32_t csr = csr_addr(s);
      word_t zimm = BITS(s->isa.inst, 19, 15);
      word_t old = csr_read(csr);
      if (zimm != 0) {
        csr_write(csr, old & ~zimm);
      }
      R(rd) = old;
  );

  // MISC-MEM: model fence/fence.i as architectural NOP in the interpreter.
  INSTPAT("??????? ????? ????? 000 ????? 00011 11", fence  , N, );
  INSTPAT("??????? ????? ????? 001 ????? 00011 11", fence_i, N, );

  INSTPAT("0000000 00000 00000 000 00000 11100 11", ecall  , N,
      s->dnpc = isa_raise_intr(cpu.priv == MODE_U ? 8 : 11, s->pc));
  INSTPAT("0011000 00010 00000 000 00000 11100 11", mret   , N, s->dnpc = isa_mret());
  INSTPAT("0000000 00001 00000 000 00000 11100 11", ebreak , N, NEMUTRAP(s->pc, R(10))); // R(10) is $a0

  //RV32M
  INSTPAT("0000001 ????? ????? 000 ????? 01100 11", mul		 , R, R(rd) = src1 * src2);
  INSTPAT("0000001 ????? ????? 001 ????? 01100 11", mulh   , R, R(rd) = ((int64_t)(int32_t)src1 * (int64_t)(int32_t)src2) >> 32);
  INSTPAT("0000001 ????? ????? 010 ????? 01100 11", mulhsu , R, R(rd) = ((int64_t)(int32_t)src1 * (uint64_t)src2) >> 32);
  INSTPAT("0000001 ????? ????? 011 ????? 01100 11", mulhu	 , R, R(rd) = (uint64_t)src1 * (uint64_t)src2 >> 32);
  INSTPAT("0000001 ????? ????? 100 ????? 01100 11", div    , R, R(rd) = src2 ? ((int64_t)(sword_t)src1 / (int64_t)(sword_t)src2) : -1);
  INSTPAT("0000001 ????? ????? 101 ????? 01100 11", divu   , R, R(rd) = src2 ? (src1 / src2) : -1);
  INSTPAT("0000001 ????? ????? 110 ????? 01100 11", rem    , R, R(rd) = src2 ? ((int64_t)(sword_t)src1 % (int64_t)(sword_t)src2) : src1);
  INSTPAT("0000001 ????? ????? 111 ????? 01100 11", remu   , R, R(rd) = src2 ? (src1 % src2) : src1);

  // RV32A. In this single-hart interpreter the aq/rl bits do not require an
  // additional host-memory fence, but they are accepted in every encoding.
  INSTPAT("00010?? 00000 ????? 010 ????? 01011 11", lr_w, R,
      R(rd) = Mr(src1, 4);
      cpu.lr_addr = vaddr_translate(src1, 4, MEM_TYPE_READ);
      cpu.lr_valid = true;
  );
  INSTPAT("00011?? ????? ????? 010 ????? 01011 11", sc_w, R,
      paddr_t addr = vaddr_translate(src1, 4, MEM_TYPE_WRITE);
      bool success = cpu.lr_valid && cpu.lr_addr == addr;
      cpu.lr_valid = false;
      if (success) Mw(src1, 4, src2);
      R(rd) = success ? 0 : 1;
  );
  INSTPAT("00001?? ????? ????? 010 ????? 01011 11", amoswap_w, R,
      word_t old = Mr(src1, 4);
      Mw(src1, 4, src2);
      R(rd) = old;
  );
  INSTPAT("00000?? ????? ????? 010 ????? 01011 11", amoadd_w, R,
      word_t old = Mr(src1, 4);
      Mw(src1, 4, old + src2);
      R(rd) = old;
  );
  INSTPAT("00100?? ????? ????? 010 ????? 01011 11", amoxor_w, R,
      word_t old = Mr(src1, 4);
      Mw(src1, 4, old ^ src2);
      R(rd) = old;
  );
  INSTPAT("01100?? ????? ????? 010 ????? 01011 11", amoand_w, R,
      word_t old = Mr(src1, 4);
      Mw(src1, 4, old & src2);
      R(rd) = old;
  );
  INSTPAT("01000?? ????? ????? 010 ????? 01011 11", amoor_w, R,
      word_t old = Mr(src1, 4);
      Mw(src1, 4, old | src2);
      R(rd) = old;
  );
  INSTPAT("10000?? ????? ????? 010 ????? 01011 11", amomin_w, R,
      word_t old = Mr(src1, 4);
      Mw(src1, 4, (sword_t)old < (sword_t)src2 ? old : src2);
      R(rd) = old;
  );
  INSTPAT("10100?? ????? ????? 010 ????? 01011 11", amomax_w, R,
      word_t old = Mr(src1, 4);
      Mw(src1, 4, (sword_t)old > (sword_t)src2 ? old : src2);
      R(rd) = old;
  );
  INSTPAT("11000?? ????? ????? 010 ????? 01011 11", amominu_w, R,
      word_t old = Mr(src1, 4);
      Mw(src1, 4, old < src2 ? old : src2);
      R(rd) = old;
  );
  INSTPAT("11100?? ????? ????? 010 ????? 01011 11", amomaxu_w, R,
      word_t old = Mr(src1, 4);
      Mw(src1, 4, old > src2 ? old : src2);
      R(rd) = old;
  );

  INSTPAT("??????? ????? ????? ??? ????? ????? ??", inv    , N, INV(s->pc));
  INSTPAT_END();

  return finish_exec(s);
}

int isa_exec_once(Decode *s) {
  Assert((s->pc & 0x1) == 0, "unaligned ifetch pc: pc=" FMT_WORD, s->pc);

  uint32_t raw = inst_fetch(&s->snpc, 2);
  s->isa.inst = raw;
  if ((raw & 0x3) != 0x3) {
    return decode_exec_rvc(s);
  }

  raw |= inst_fetch(&s->snpc, 2) << 16;
  s->isa.inst = raw;
  return decode_exec(s);
}
