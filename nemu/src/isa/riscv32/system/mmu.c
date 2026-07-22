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

paddr_t isa_mmu_translate(vaddr_t vaddr, int len, int type) {
  assert((vaddr & PAGE_MASK) + len <= PAGE_SIZE);

  paddr_t pdir = cpu.satp << PAGE_SHIFT;
  word_t pde = paddr_read(pdir + (((vaddr >> 22) & 0x3ff) << 2), 4);
  assert(pde & 0x1);
  assert((pde & 0xe) == 0);

  paddr_t ptable = (pde >> 10) << PAGE_SHIFT;
  word_t pte = paddr_read(ptable + (((vaddr >> 12) & 0x3ff) << 2), 4);
  assert(pte & 0x1);
  assert(pte & 0xe);

  (void)type;
  return ((pte >> 10) << PAGE_SHIFT) | (vaddr & PAGE_MASK);
}
