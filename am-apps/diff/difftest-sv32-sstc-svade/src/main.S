#define PTE_V (1 << 0)
#define PTE_R (1 << 1)
#define PTE_W (1 << 2)
#define PTE_X (1 << 3)
#define PTE_A (1 << 6)
#define PTE_D (1 << 7)

#define MSTATUS_MPP  (3 << 11)
#define MSTATUS_MPP_S (1 << 11)
#define MSTATUS_MPRV (1 << 17)
#define MENVCFGH_ADUE (1 << 29)

#define EXPECT_FAULT(cause, tval, fault, recovery, mpp, force_m) \
  li s0, cause; \
  li s1, tval; \
  la s2, recovery; \
  la s3, fault; \
  li s4, 0; \
  li s7, mpp; \
  li s8, force_m

  .section .text
  .align 2
  .globl main
main:
  addi sp, sp, -48
  sw ra, 44(sp)
  sw s0, 40(sp)
  sw s1, 36(sp)
  sw s2, 32(sp)
  sw s3, 28(sp)
  sw s4, 24(sp)
  sw s5, 20(sp)
  sw s6, 16(sp)
  sw s7, 12(sp)
  sw s8, 8(sp)
  sw s9, 4(sp)

  la t0, trap_handler
  csrw mtvec, t0
  csrwi medeleg, 0

  /* Build one identity-mapped 4 MiB superpage containing test_data. */
  la s5, root_page_table
  mv t0, s5
  li t1, 1024
clear_root:
  sw zero, 0(t0)
  addi t0, t0, 4
  addi t1, t1, -1
  bnez t1, clear_root

  la s9, test_data
  srli t0, s9, 22
  slli t0, t0, 2
  add s6, s5, t0
  srli t0, s9, 22
  slli t0, t0, 20
  ori t0, t0, PTE_V | PTE_R | PTE_W | PTE_X
  sw t0, 0(s6)

  srli t0, s5, 12
  li t1, 0x80000000
  or t0, t0, t1
  csrw satp, t0
  sfence.vma

  /* Svade keeps menvcfgh.ADUE read-only zero. */
  li t0, MENVCFGH_ADUE
  csrs 0x31a, t0
  csrr t1, 0x31a
  and t1, t1, t0
  bnez t1, fail

  /* An A=0 load faults and leaves rd/PTE unchanged. */
  li a0, 0x13579bdf
  EXPECT_FAULT(13, 0, fault_load_a_clear, after_load_a_clear, 3, 0)
  mv s1, s9
  li t0, MSTATUS_MPP | MSTATUS_MPRV
  csrc mstatus, t0
  li t0, MSTATUS_MPP_S | MSTATUS_MPRV
  csrs mstatus, t0
fault_load_a_clear:
  lw a0, 0(s9)
after_load_a_clear:
  li t0, MSTATUS_MPRV
  csrc mstatus, t0
  bnez s4, fail
  li t0, 0x13579bdf
  bne a0, t0, fail
  lw t0, 0(s6)
  srli t1, s9, 22
  slli t1, t1, 20
  ori t1, t1, PTE_V | PTE_R | PTE_W | PTE_X
  bne t0, t1, fail

  /* Software sets A and retries the load; D remains clear. */
  lw t0, 0(s6)
  ori t0, t0, PTE_A
  sw t0, 0(s6)
  sfence.vma
  li t0, MSTATUS_MPP | MSTATUS_MPRV
  csrc mstatus, t0
  li t0, MSTATUS_MPP_S | MSTATUS_MPRV
  csrs mstatus, t0
  lw a0, 0(s9)
  li t0, MSTATUS_MPRV
  csrc mstatus, t0
  li t0, 0x44332211
  bne a0, t0, fail
  lw t0, 0(s6)
  srli t1, s9, 22
  slli t1, t1, 20
  ori t1, t1, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A
  bne t0, t1, fail

  /* A D=0 store faults without changing memory or PTE. */
  li a0, 0xdeadbeef
  EXPECT_FAULT(15, 0, fault_store_d_clear, after_store_d_clear, 3, 0)
  mv s1, s9
  li t0, MSTATUS_MPP | MSTATUS_MPRV
  csrc mstatus, t0
  li t0, MSTATUS_MPP_S | MSTATUS_MPRV
  csrs mstatus, t0
fault_store_d_clear:
  sw a0, 0(s9)
after_store_d_clear:
  li t0, MSTATUS_MPRV
  csrc mstatus, t0
  bnez s4, fail
  lw t0, 0(s9)
  li t1, 0x44332211
  bne t0, t1, fail
  lw t0, 0(s6)
  srli t1, s9, 22
  slli t1, t1, 20
  ori t1, t1, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A
  bne t0, t1, fail

  /* Software sets D and retries the store successfully. */
  lw t0, 0(s6)
  ori t0, t0, PTE_D
  sw t0, 0(s6)
  sfence.vma
  li t0, MSTATUS_MPP | MSTATUS_MPRV
  csrc mstatus, t0
  li t0, MSTATUS_MPP_S | MSTATUS_MPRV
  csrs mstatus, t0
  sw a0, 0(s9)
  li t0, MSTATUS_MPRV
  csrc mstatus, t0
  lw t0, 0(s9)
  bne t0, a0, fail
  lw t0, 0(s6)
  srli t1, s9, 22
  slli t1, t1, 20
  ori t1, t1, PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D
  bne t0, t1, fail

  /* An unmapped S-mode instruction fetch reports an invalid-instruction step. */
  EXPECT_FAULT(12, 0x40000000, instruction_page_fault,
      after_instruction_page_fault, 1, 1)
  li s3, 0x40000000
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  li t0, MSTATUS_MPP_S
  csrs mstatus, t0
  li t0, 0x40000000
  csrw mepc, t0
  mret
instruction_page_fault:
after_instruction_page_fault:
  bnez s4, fail
  csrwi satp, 0
  sfence.vma

  li a0, 0
  j done
fail:
  li a0, 1
done:
  lw s9, 4(sp)
  lw s8, 8(sp)
  lw s7, 12(sp)
  lw s6, 16(sp)
  lw s5, 20(sp)
  lw s4, 24(sp)
  lw s3, 28(sp)
  lw s2, 32(sp)
  lw s1, 36(sp)
  lw s0, 40(sp)
  lw ra, 44(sp)
  addi sp, sp, 48
  ret

  .align 2
trap_handler:
  csrr t0, mcause
  bne t0, s0, trap_fail
  csrr t0, mtval
  bne t0, s1, trap_fail
  csrr t0, mepc
  bne t0, s3, trap_fail
  csrr t0, mstatus
  srli t0, t0, 11
  andi t0, t0, 3
  bne t0, s7, trap_fail
  csrw mepc, s2
  beqz s8, trap_return
  li t0, MSTATUS_MPP
  csrs mstatus, t0
trap_return:
  mret
trap_fail:
  li s4, 1
  csrw mepc, s2
  li t0, MSTATUS_MPP
  csrs mstatus, t0
  mret

  .section .data
  .align 2
test_data:
  .word 0x44332211

  .section .bss
  .align 12
root_page_table:
  .space 4096
