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
#include <memory/paddr.h>

paddr_t vaddr_translate(vaddr_t addr, int len, int type) {
  int mode = isa_mmu_check(addr, len, type);
  if (mode == MMU_DIRECT) return addr;
  if (mode == MMU_TRANSLATE) return isa_mmu_translate(addr, len, type);
  assert(0);
}

word_t vaddr_ifetch(vaddr_t addr, int len) {
  return paddr_read(vaddr_translate(addr, len, MEM_TYPE_IFETCH), len);
}

word_t vaddr_read(vaddr_t addr, int len) {
  word_t data = paddr_read(vaddr_translate(addr, len, MEM_TYPE_READ), len);
#ifdef CONFIG_MTRACE
  if ((MTRACE_COND)) {
    mtrace_write("R " FMT_WORD " len=%d data=" FMT_WORD "\n", addr, len, data);
  }
#endif
  return data;
}

void vaddr_write(vaddr_t addr, int len, word_t data) {
  paddr_write(vaddr_translate(addr, len, MEM_TYPE_WRITE), len, data);
#ifdef CONFIG_MTRACE
  if ((MTRACE_COND)) {
    mtrace_write("W " FMT_WORD " len=%d data=" FMT_WORD "\n", addr, len, data);
  }
#endif
}
