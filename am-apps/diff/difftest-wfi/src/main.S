#define MSTATUS_MPP (3 << 11)
#define MSTATUS_MPP_S (1 << 11)
#define MSTATUS_TW (1 << 21)

  .section .text
  .align 2
  .globl main
main:
  addi sp, sp, -16
  sw ra, 12(sp)
  sw s0, 8(sp)

  la t0, trap_handler
  csrw mtvec, t0
  csrwi medeleg, 0

  /* Legal M-mode WFI is an ordinary NOP ARCH_STEP. */
  wfi

  /* Legal S-mode WFI is also a NOP; ecall returns control to M. */
  li t0, MSTATUS_TW | MSTATUS_MPP
  csrc mstatus, t0
  li t0, MSTATUS_MPP_S
  csrs mstatus, t0
  la t0, supervisor_wfi
  csrw mepc, t0
  li s0, 1
  mret
supervisor_wfi:
  wfi
supervisor_ecall:
  ecall
after_supervisor_wfi:
  li t0, 2
  bne s0, t0, fail

  /* mstatus.TW makes S-mode WFI an illegal instruction. */
  li t0, MSTATUS_TW
  csrs mstatus, t0
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  li t0, MSTATUS_MPP_S
  csrs mstatus, t0
  la t0, supervisor_tw_wfi
  csrw mepc, t0
  li s0, 3
  mret
supervisor_tw_wfi:
  wfi
after_supervisor_tw_wfi:
  li t0, 4
  bne s0, t0, fail

  /* U-mode WFI is always an illegal instruction. */
  li t0, MSTATUS_TW | MSTATUS_MPP
  csrc mstatus, t0
  la t0, user_wfi
  csrw mepc, t0
  li s0, 5
  mret
user_wfi:
  wfi
after_user_wfi:
  li t0, 6
  bne s0, t0, fail

  li a0, 0
  j done
fail:
  li a0, 1
done:
  lw s0, 8(sp)
  lw ra, 12(sp)
  addi sp, sp, 16
  ret

  .align 2
trap_handler:
  li t0, 1
  beq s0, t0, from_supervisor_ecall
  li t0, 3
  beq s0, t0, from_supervisor_tw_wfi
  li t0, 5
  beq s0, t0, from_user_wfi
  j trap_fail

from_supervisor_ecall:
  csrr t0, mcause
  li t1, 9
  bne t0, t1, trap_fail
  csrr t0, mtval
  bnez t0, trap_fail
  csrr t0, mepc
  la t1, supervisor_ecall
  bne t0, t1, trap_fail
  li t1, 1
  j return_to_machine

from_supervisor_tw_wfi:
  csrr t0, mcause
  li t1, 2
  bne t0, t1, trap_fail
  csrr t0, mtval
  li t1, 0x10500073
  bne t0, t1, trap_fail
  csrr t0, mepc
  la t1, supervisor_tw_wfi
  bne t0, t1, trap_fail
  li t0, MSTATUS_TW
  csrc mstatus, t0
  li t1, 3
  j return_to_machine

from_user_wfi:
  csrr t0, mcause
  li t1, 2
  bne t0, t1, trap_fail
  csrr t0, mtval
  li t1, 0x10500073
  bne t0, t1, trap_fail
  csrr t0, mepc
  la t1, user_wfi
  bne t0, t1, trap_fail
  li t1, 5

return_to_machine:
  csrr t0, mstatus
  srli t0, t0, 11
  andi t0, t0, 3
  li t2, 1
  bne t0, t2, check_user_origin
  li t0, 1
  beq t1, t0, return_after_legal
  li t0, 3
  beq t1, t0, return_after_tw
  j trap_fail
check_user_origin:
  bnez t0, trap_fail
  li t2, 5
  bne t1, t2, trap_fail
  la t0, after_user_wfi
  li s0, 6
  j install_machine_return
return_after_legal:
  la t0, after_supervisor_wfi
  li s0, 2
  j install_machine_return
return_after_tw:
  la t0, after_supervisor_tw_wfi
  li s0, 4
install_machine_return:
  csrw mepc, t0
  li t0, MSTATUS_MPP
  csrs mstatus, t0
  mret

trap_fail:
  li a0, 1
  ebreak
