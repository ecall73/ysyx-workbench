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
  CSR_MTVEC   = 0x305,
  CSR_MEPC    = 0x341,
  CSR_MCAUSE  = 0x342,
  CSR_MVENDORID = 0xF11,
  CSR_MARCHID   = 0xF12,
};

enum {
  MSTATUS_MIE  = (1u << 3),
  MSTATUS_MPIE = (1u << 7),
  MSTATUS_MPP  = (3u << 11),
};

static inline word_t csr_read(uint32_t addr) {
  switch (addr) {
    case CSR_MSTATUS: return cpu.mstatus;
    case CSR_MTVEC:   return cpu.mtvec;
    case CSR_MEPC:    return cpu.mepc;
    case CSR_MCAUSE:  return cpu.mcause;
    case CSR_MVENDORID: return 0x79737978;
    case CSR_MARCHID:   return 26030082;
    default:          return 0;
  }
}

static inline void csr_write(uint32_t addr, word_t data) {
  switch (addr) {
    case CSR_MSTATUS: cpu.mstatus = data; break;
    case CSR_MTVEC:   cpu.mtvec   = data; break;
    case CSR_MEPC:    cpu.mepc    = data; break;
    case CSR_MCAUSE:  cpu.mcause  = data; break;
    default: break;
  }
}

#if CONFIG_ETRACE
static inline void etrace_log_mret(vaddr_t target) {
  log_write("etrace: mret -> " FMT_WORD " mstatus=" FMT_WORD "\n", target, cpu.mstatus);
}
#endif

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

#ifdef CONFIG_FTRACE
  INSTPAT("??????? ????? ????? ??? ????? 11011 11", jal    , J,
      R(rd) = s->pc + 4;
      s->dnpc = s->pc + imm;
      if (rd == 1 || rd == 5) {
        ftrace_call(s->pc, s->dnpc);
      }
  );
  INSTPAT("??????? ????? ????? 000 ????? 11001 11", jalr   , I,
      R(rd) = s->pc + 4;
      s->dnpc = (src1 + imm) & ~1;
      int rs1 = BITS(s->isa.inst, 19, 15);
      if (rd == 0 && rs1 == 1 && imm == 0) {
        ftrace_ret(s->pc);
      } else if (rd == 1 || rd == 5) {
        ftrace_call(s->pc, s->dnpc);
      }
  );
#else
  INSTPAT("??????? ????? ????? ??? ????? 11011 11", jal    , J, R(rd) = s->pc + 4, s->dnpc = s->pc + imm);
  INSTPAT("??????? ????? ????? 000 ????? 11001 11", jalr   , I, R(rd) = s->pc + 4, s->dnpc = (src1 + imm) & ~1);
#endif

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
      uint32_t inst = INSTPAT_INST(s);
      uint32_t csr = BITS(inst, 31, 20);
      uint32_t rs1 = BITS(inst, 19, 15);
      word_t old = csr_read(csr);
      csr_write(csr, R(rs1));
      R(rd) = old;
  );
  INSTPAT("??????? ????? ????? 010 ????? 11100 11", csrrs  , N,
      uint32_t inst = INSTPAT_INST(s);
      uint32_t csr = BITS(inst, 31, 20);
      uint32_t rs1 = BITS(inst, 19, 15);
      word_t old = csr_read(csr);
      if (rs1 != 0) {
        csr_write(csr, old | R(rs1));
      }
      R(rd) = old;
  );
  INSTPAT("??????? ????? ????? 011 ????? 11100 11", csrrc  , N,
      uint32_t inst = INSTPAT_INST(s);
      uint32_t csr = BITS(inst, 31, 20);
      uint32_t rs1 = BITS(inst, 19, 15);
      word_t old = csr_read(csr);
      if (rs1 != 0) {
        csr_write(csr, old & ~R(rs1));
      }
      R(rd) = old;
  );
  INSTPAT("??????? ????? ????? 101 ????? 11100 11", csrrwi , N,
      uint32_t inst = INSTPAT_INST(s);
      uint32_t csr = BITS(inst, 31, 20);
      word_t zimm = BITS(inst, 19, 15);
      word_t old = csr_read(csr);
      csr_write(csr, zimm);
      R(rd) = old;
  );
  INSTPAT("??????? ????? ????? 110 ????? 11100 11", csrrsi , N,
      uint32_t inst = INSTPAT_INST(s);
      uint32_t csr = BITS(inst, 31, 20);
      word_t zimm = BITS(inst, 19, 15);
      word_t old = csr_read(csr);
      if (zimm != 0) {
        csr_write(csr, old | zimm);
      }
      R(rd) = old;
  );
  INSTPAT("??????? ????? ????? 111 ????? 11100 11", csrrci , N,
      uint32_t inst = INSTPAT_INST(s);
      uint32_t csr = BITS(inst, 31, 20);
      word_t zimm = BITS(inst, 19, 15);
      word_t old = csr_read(csr);
      if (zimm != 0) {
        csr_write(csr, old & ~zimm);
      }
      R(rd) = old;
  );

  INSTPAT("0000000 00000 00000 000 00000 11100 11", ecall  , N, s->dnpc = isa_raise_intr(11, s->pc));
  INSTPAT("0011000 00010 00000 000 00000 11100 11", mret   , N,
      word_t mstatus = cpu.mstatus;
      word_t mpie = (mstatus & MSTATUS_MPIE) ? 1 : 0;
      mstatus = (mstatus & ~MSTATUS_MIE) | (mpie ? MSTATUS_MIE : 0); // MIE <- MPIE
      mstatus |= MSTATUS_MPIE;                                        // MPIE <- 1
      mstatus &= ~MSTATUS_MPP;                                        // MPP <- U(0)
      cpu.mstatus = mstatus;
      s->dnpc = cpu.mepc;
      IFONE(CONFIG_ETRACE, etrace_log_mret(s->dnpc));
  );
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

  INSTPAT("??????? ????? ????? ??? ????? ????? ??", inv    , N, INV(s->pc));
  INSTPAT_END();

  R(0) = 0; // reset $zero to 0

  return 0;
}

int isa_exec_once(Decode *s) {
  s->isa.inst = inst_fetch(&s->snpc, 4);
  return decode_exec(s);
}
