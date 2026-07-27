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

#ifndef __DIFFTEST_DEF_H__
#define __DIFFTEST_DEF_H__

#include <stdint.h>
#include <macro.h>
#include <generated/autoconf.h>

#define __EXPORT __attribute__((visibility("default")))
enum { DIFFTEST_TO_DUT, DIFFTEST_TO_REF };

#if defined(CONFIG_ISA_x86)
# define DIFFTEST_REG_SIZE (sizeof(uint32_t) * 9) // GPRs + pc
#elif defined(CONFIG_ISA_mips32)
# define DIFFTEST_REG_SIZE (sizeof(uint32_t) * 38) // GPRs + status + lo + hi + badvaddr + cause + pc
#elif defined(CONFIG_ISA_riscv)
#define RISCV_GPR_TYPE MUXDEF(CONFIG_RV64, uint64_t, uint32_t)
#define RISCV_GPR_NUM  MUXDEF(CONFIG_RVE , 16, 32)
#define RISCV_FPR_NUM  32
#define RISCV_CSR_NUM  20
typedef struct {
  RISCV_GPR_TYPE gpr[RISCV_GPR_NUM];
  RISCV_GPR_TYPE pc;
  RISCV_GPR_TYPE fcsr;
  uint64_t fpr[RISCV_FPR_NUM];
  RISCV_GPR_TYPE mstatus, mtvec, mepc, mcause, mtval;
  RISCV_GPR_TYPE medeleg, mideleg, mie;
  RISCV_GPR_TYPE stvec, sepc, scause, stval, sscratch;
  RISCV_GPR_TYPE satp, mscratch, menvcfgh, mcounteren;
  RISCV_GPR_TYPE scounteren, mcountinhibit;
  RISCV_GPR_TYPE priv;
} riscv_difftest_context_t;
#define DIFFTEST_REG_SIZE sizeof(riscv_difftest_context_t)
#elif defined(CONFIG_ISA_loongarch32r)
# define DIFFTEST_REG_SIZE (sizeof(uint32_t) * 33) // GPRs + pc
#else
# error Unsupport ISA
#endif

#endif
