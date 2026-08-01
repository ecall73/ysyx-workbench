#define EXPECT_FAULT(cause, tval, fault, recovery) \
  li s0, cause; \
  li s1, tval; \
  la s2, recovery; \
  la s3, fault; \
  li s4, 0

  .section .text
  .align 2
  .globl main
main:
  addi sp, sp, -40
  sw ra, 36(sp)
  sw s0, 32(sp)
  sw s1, 28(sp)
  sw s2, 24(sp)
  sw s3, 20(sp)
  sw s4, 16(sp)
  sw s5, 12(sp)
  sw s6, 8(sp)

  la t0, trap_handler
  csrw mtvec, t0

  la s5, test_data
  EXPECT_FAULT(4, 0, fault_load_misaligned, after_load_misaligned)
  addi s1, s5, 1
  li s6, 0x13579bdf
fault_load_misaligned:
  lh s6, 1(s5)
after_load_misaligned:
  bnez s4, fail
  li t0, 0x13579bdf
  bne s6, t0, fail

  EXPECT_FAULT(6, 0, fault_store_misaligned, after_store_misaligned)
  addi s1, s5, 1
fault_store_misaligned:
  sh zero, 1(s5)
after_store_misaligned:
  bnez s4, fail
  lw t0, 0(s5)
  li t1, 0x44332211
  bne t0, t1, fail

  li s5, 0x40000000
  EXPECT_FAULT(5, 0x40000000, fault_load_access, after_load_access)
  li s6, 0x2468ace0
fault_load_access:
  lw s6, 0(s5)
after_load_access:
  bnez s4, fail
  li t0, 0x2468ace0
  bne s6, t0, fail

  EXPECT_FAULT(7, 0x40000000, fault_store_access, after_store_access)
fault_store_access:
  sw zero, 0(s5)
after_store_access:
  bnez s4, fail

  EXPECT_FAULT(2, 0xffffffff, fault_illegal, after_illegal)
fault_illegal:
  .word 0xffffffff
after_illegal:
  bnez s4, fail

  EXPECT_FAULT(2, 0, fault_bad_csr, after_bad_csr)
  la t0, fault_bad_csr
  lw s1, 0(t0)
  .align 2
fault_bad_csr:
  csrr t0, 0x7ff
after_bad_csr:
  bnez s4, fail

  EXPECT_FAULT(11, 0, fault_m_ecall, after_m_ecall)
fault_m_ecall:
  ecall
after_m_ecall:
  bnez s4, fail

  li s5, 0x40000000
  EXPECT_FAULT(1, 0x40000000, after_instruction_access,
      after_instruction_access)
  li s3, 0x40000000
  jalr zero, s5, 0
after_instruction_access:
  bnez s4, fail

  /* A U-mode ecall is delegated to S; a later U-mode illegal CSR returns M. */
  la t0, supervisor_trap_handler
  csrw stvec, t0
  li t0, 1 << 8
  csrw medeleg, t0
  la t0, user_illegal_exit
  lw s1, 0(t0)
  la s2, after_user_traps
  la s3, user_illegal_exit
  li s5, 1
  li t0, 3 << 11
  csrc mstatus, t0
  la t0, fault_u_ecall
  csrw mepc, t0
  mret
after_user_traps:
  li t0, 2
  bne s5, t0, fail

  /* An undelegated S-mode ecall traps directly to M. */
  csrwi medeleg, 0
  la s2, after_s_ecall
  la s3, fault_s_ecall
  li s5, 3
  li t0, 3 << 11
  csrc mstatus, t0
  li t0, 1 << 11
  csrs mstatus, t0
  csrw mepc, s3
  mret
after_s_ecall:
  li t0, 4
  bne s5, t0, fail

  li a0, 0
  j done
fail:
  li a0, 1
done:
  lw s6, 8(sp)
  lw s5, 12(sp)
  lw s4, 16(sp)
  lw s3, 20(sp)
  lw s2, 24(sp)
  lw s1, 28(sp)
  lw s0, 32(sp)
  lw ra, 36(sp)
  addi sp, sp, 40
  ret

  .align 2
trap_handler:
  li t0, 1
  beq s5, t0, machine_from_user_illegal
  li t0, 3
  beq s5, t0, machine_from_supervisor_ecall
  csrr t0, mcause
  bne t0, s0, trap_fail
  csrr t0, mtval
  bne t0, s1, trap_fail
  csrr t0, mepc
  bne t0, s3, trap_fail
  li t0, 3
  csrr t1, mstatus
  srli t1, t1, 11
  andi t1, t1, 3
  bne t0, t1, trap_fail
  csrw mepc, s2
  mret
trap_fail:
  li s4, 1
  csrw mepc, s2
  mret

machine_from_user_illegal:
  csrr t0, mcause
  li t1, 2
  bne t0, t1, trap_fail_terminal
  csrr t0, mtval
  bne t0, s1, trap_fail_terminal
  csrr t0, mepc
  bne t0, s3, trap_fail_terminal
  csrr t0, mstatus
  srli t0, t0, 11
  andi t0, t0, 3
  bnez t0, trap_fail_terminal
  csrw mepc, s2
  li t0, 3 << 11
  csrs mstatus, t0
  li s5, 2
  mret

machine_from_supervisor_ecall:
  csrr t0, mcause
  li t1, 9
  bne t0, t1, trap_fail_terminal
  csrr t0, mtval
  bnez t0, trap_fail_terminal
  csrr t0, mepc
  bne t0, s3, trap_fail_terminal
  csrr t0, mstatus
  srli t0, t0, 11
  andi t0, t0, 3
  li t1, 1
  bne t0, t1, trap_fail_terminal
  csrw mepc, s2
  li t0, 3 << 11
  csrs mstatus, t0
  li s5, 4
  mret

trap_fail_terminal:
  li a0, 1
  ebreak

  .align 2
supervisor_trap_handler:
  csrr t0, scause
  li t1, 8
  bne t0, t1, trap_fail_terminal
  csrr t0, stval
  bnez t0, trap_fail_terminal
  csrr t0, sepc
  la t1, fault_u_ecall
  bne t0, t1, trap_fail_terminal
  csrr t0, sstatus
  li t1, 1 << 8
  and t0, t0, t1
  bnez t0, trap_fail_terminal
  csrw sepc, s3
  sret

  .align 2
fault_u_ecall:
  ecall

  .align 2
user_illegal_exit:
  csrr t0, mstatus

  .align 2
fault_s_ecall:
  ecall

  .section .data
  .align 3
test_data:
  .word 0x44332211
