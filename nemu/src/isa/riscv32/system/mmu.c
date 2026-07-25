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
  assert((vaddr & PAGE_MASK) + len <= PAGE_SIZE);

  paddr_t table = (cpu.satp & 0x003fffffu) << PAGE_SHIFT;
  word_t mode = effective_priv(type);
  for (int level = 1; level >= 0; level--) {
    word_t vpn = (vaddr >> (PAGE_SHIFT + level * 10)) & 0x3ff;
    paddr_t pte_addr = table + vpn * 4;
    word_t pte = paddr_read(pte_addr, 4);

    assert((pte & PTE_V) && !(!(pte & PTE_R) && (pte & PTE_W)));
    if (pte & (PTE_R | PTE_X)) {
      bool user = pte & PTE_U;
      assert(mode == MODE_U || mode == MODE_S);
      assert(mode != MODE_U || user);
      assert(mode != MODE_S || !user ||
          (type != MEM_TYPE_IFETCH && (cpu.mstatus & MSTATUS_SUM)));
      if (type == MEM_TYPE_IFETCH) assert(pte & PTE_X);
      else if (type == MEM_TYPE_READ)
        assert((pte & PTE_R) || ((cpu.mstatus & MSTATUS_MXR) && (pte & PTE_X)));
      else assert(pte & PTE_W);

      word_t ad = PTE_A | (type == MEM_TYPE_WRITE ? PTE_D : 0);
      if ((pte & ad) != ad) {
        assert(cpu.menvcfgh & MENVCFGH_ADUE);
        pte |= ad;
        paddr_write(pte_addr, 4, pte);
      }

      word_t ppn = pte >> 10;
      if (level == 1) {
        assert((ppn & 0x3ff) == 0);
        return (ppn << PAGE_SHIFT) | (vaddr & 0x003fffff);
      }
      return (ppn << PAGE_SHIFT) | (vaddr & PAGE_MASK);
    }

    assert((pte & (PTE_U | PTE_A | PTE_D)) == 0);
    table = (pte >> 10) << PAGE_SHIFT;
  }
  assert(0);
  return 0;
}
