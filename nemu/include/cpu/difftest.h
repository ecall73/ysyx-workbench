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

#ifndef __CPU_DIFFTEST_H__
#define __CPU_DIFFTEST_H__

#include <common.h>
#include <difftest-def.h>

#ifdef CONFIG_DIFFTEST
void difftest_skip_ref_reason(uint32_t reason);
#if !defined(CONFIG_ISA_riscv)
void difftest_skip_ref(void);
void difftest_skip_dut(int nr_ref, int nr_dut);
#endif
void difftest_step(vaddr_t pc, uint32_t instruction_bits,
    uint32_t instruction_length, bool instruction_valid);
void difftest_raise_intr_event(uint32_t interrupt_code, vaddr_t pretrap_pc);
void difftest_detach();
void difftest_attach();
bool difftest_is_attached();
#else
static inline void difftest_skip_ref_reason(uint32_t reason) {}
static inline void difftest_step(vaddr_t pc, uint32_t instruction_bits,
    uint32_t instruction_length, bool instruction_valid) {}
static inline void difftest_raise_intr_event(uint32_t interrupt_code,
    vaddr_t pretrap_pc) {}
static inline void difftest_detach() {}
static inline void difftest_attach() {}
static inline bool difftest_is_attached() { return false; }
#endif

#if defined(CONFIG_DIFFTEST) && !defined(CONFIG_ISA_riscv)
extern void (*ref_difftest_regcpy)(void *dut, bool direction);
extern void (*ref_difftest_exec)(uint64_t n);
extern void (*ref_difftest_raise_intr)(uint64_t NO);
#endif

#endif
