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

#include <isa.h>
#include <memory/vaddr.h>
#include <memory/paddr.h>
#include "../local-include/csr.h"

enum {
  PTE_V = 1u << 0,
  PTE_R = 1u << 1,
  PTE_W = 1u << 2,
  PTE_X = 1u << 3,
  PTE_U = 1u << 4,
  PTE_A = 1u << 6,
  PTE_D = 1u << 7,
};

static word_t effective_priv(int type) {
  if (type != MEM_TYPE_IFETCH && cpu.priv == MODE_M &&
      (cpu.mstatus & MSTATUS_MPRV)) {
    return (cpu.mstatus & MSTATUS_MPP) >> 11;
  }
  return cpu.priv;
}

int riscv32_mmu_check(vaddr_t vaddr, int len, int type) {
  (void)vaddr;
  (void)len;
  return (cpu.satp & 0x80000000u) && effective_priv(type) != MODE_M
      ? MMU_TRANSLATE : MMU_DIRECT;
}

paddr_t isa_mmu_translate(vaddr_t vaddr, int len, int type) {
  if ((vaddr & PAGE_MASK) + len > PAGE_SIZE) {
    riscv_raise_memory_fault(vaddr, type, true);
  }

  uint64_t table = (uint64_t)(cpu.satp & 0x003fffffu) << PAGE_SHIFT;
  word_t mode = effective_priv(type);
  Assert(mode == MODE_U || mode == MODE_S,
      "translated access has invalid effective privilege: mode=%u pc=" FMT_WORD,
      mode, cpu.pc);
  for (int level = 1; level >= 0; level--) {
    word_t vpn = (vaddr >> (PAGE_SHIFT + level * 10)) & 0x3ff;
    uint64_t pte_addr64 = table + vpn * 4;
    if (pte_addr64 > UINT32_MAX) {
      riscv_raise_memory_fault(vaddr, type, false);
    }
    paddr_t pte_addr = pte_addr64;
    word_t pte = 0;
    if (!paddr_is_memory(pte_addr, 4) ||
        !paddr_try_read(pte_addr, 4, &pte)) {
      riscv_raise_memory_fault(vaddr, type, false);
    }

    if (!(pte & PTE_V) || (!(pte & PTE_R) && (pte & PTE_W))) {
      riscv_raise_memory_fault(vaddr, type, true);
    }
    if (pte & (PTE_R | PTE_X)) {
      bool user = pte & PTE_U;
      bool privilege_ok = (mode != MODE_U || user) &&
          (mode != MODE_S || !user ||
           (type != MEM_TYPE_IFETCH && (cpu.mstatus & MSTATUS_SUM)));
      bool permission_ok = type == MEM_TYPE_IFETCH ? (pte & PTE_X) :
          type == MEM_TYPE_READ
              ? ((pte & PTE_R) ||
                 ((cpu.mstatus & MSTATUS_MXR) && (pte & PTE_X)))
              : ((pte & PTE_R) && (pte & PTE_W));
      if (!privilege_ok || !permission_ok) {
        riscv_raise_memory_fault(vaddr, type, true);
      }

      word_t ad = PTE_A | (type == MEM_TYPE_WRITE ? PTE_D : 0);
      if ((pte & ad) != ad) {
        if (!(cpu.menvcfgh & MENVCFGH_ADUE)) {
          riscv_raise_memory_fault(vaddr, type, true);
        }
        pte |= ad;
        if (!paddr_try_write(pte_addr, 4, pte)) {
          riscv_raise_memory_fault(vaddr, type, false);
        }
      }

      word_t ppn = pte >> 10;
      uint64_t phys;
      if (level == 1) {
        if ((ppn & 0x3ff) != 0) {
          riscv_raise_memory_fault(vaddr, type, true);
        }
        phys = ((uint64_t)ppn << PAGE_SHIFT) | (vaddr & 0x003fffff);
      } else {
        phys = ((uint64_t)ppn << PAGE_SHIFT) | (vaddr & PAGE_MASK);
      }
      if (phys > UINT32_MAX) {
        riscv_raise_memory_fault(vaddr, type, false);
      }
      return phys;
    }

    if (pte & (PTE_U | PTE_A | PTE_D)) {
      riscv_raise_memory_fault(vaddr, type, true);
    }
    table = (uint64_t)(pte >> 10) << PAGE_SHIFT;
  }
  riscv_raise_memory_fault(vaddr, type, true);
}
