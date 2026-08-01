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
  IFDEF(CONFIG_ISA_riscv, riscv_raise_memory_fault(addr, type, true));
  assert(0);
}

static paddr_t checked_translate(vaddr_t addr, int len, int type) {
#ifdef CONFIG_ISA_riscv
  Assert(len == 1 || len == 2 || len == 4 || len == 8,
      "invalid RISC-V access length: addr=" FMT_WORD " len=%d type=%d",
      addr, len, type);
  if (type != MEM_TYPE_IFETCH && (addr & (len - 1)) != 0) {
    riscv_raise_exception(type == MEM_TYPE_READ ? 4 : 6, addr, type);
  }
#endif

  paddr_t paddr = vaddr_translate(addr, len, type);
#ifdef CONFIG_ISA_riscv
  bool mapped = type == MEM_TYPE_IFETCH
      ? paddr_is_memory(paddr, len) : paddr_is_mapped(paddr, len);
  if (!mapped) riscv_raise_memory_fault(addr, type, false);
#endif
  return paddr;
}

void vaddr_check_access(vaddr_t addr, int len, int type) {
  (void)checked_translate(addr, len, type);
}

word_t vaddr_ifetch(vaddr_t addr, int len) {
  paddr_t paddr = checked_translate(addr, len, MEM_TYPE_IFETCH);
#ifdef CONFIG_ISA_riscv
  word_t data = 0;
  if (!paddr_try_read(paddr, len, &data)) {
    riscv_raise_memory_fault(addr, MEM_TYPE_IFETCH, false);
  }
  return data;
#else
  return paddr_read(paddr, len);
#endif
}

word_t vaddr_read(vaddr_t addr, int len) {
  paddr_t paddr = checked_translate(addr, len, MEM_TYPE_READ);
#ifdef CONFIG_ISA_riscv
  word_t data = 0;
  if (!paddr_try_read(paddr, len, &data)) {
    riscv_raise_memory_fault(addr, MEM_TYPE_READ, false);
  }
#else
  word_t data = paddr_read(paddr, len);
#endif
#ifdef CONFIG_MTRACE
  if ((MTRACE_COND)) {
    mtrace_write("R " FMT_WORD " len=%d data=" FMT_WORD "\n", addr, len, data);
  }
#endif
  return data;
}

void vaddr_write(vaddr_t addr, int len, word_t data) {
  paddr_t paddr = checked_translate(addr, len, MEM_TYPE_WRITE);
#ifdef CONFIG_ISA_riscv
  if (!paddr_try_write(paddr, len, data)) {
    riscv_raise_memory_fault(addr, MEM_TYPE_WRITE, false);
  }
#else
  paddr_write(paddr, len, data);
#endif
#ifdef CONFIG_MTRACE
  if ((MTRACE_COND)) {
    mtrace_write("W " FMT_WORD " len=%d data=" FMT_WORD "\n", addr, len, data);
  }
#endif
}
