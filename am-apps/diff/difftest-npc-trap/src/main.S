#define MSTATUS_MIE  (1 << 3)
#define MSTATUS_MPIE (1 << 7)
#define MSTATUS_MPP  (3 << 11)

  .section .text
  .align 2
  .globl main
main:
  addi sp, sp, -16
  sw ra, 12(sp)
  sw s0, 8(sp)

  la t0, trap_handler
  csrw mtvec, t0
  li s0, 1

ecall_site:
  ecall
after_ecall:
  li t0, 2
  bne s0, t0, fail

  csrr t0, mcause
  li t1, 11
  bne t0, t1, fail
  csrr t0, mepc
  la t1, after_ecall
  bne t0, t1, fail
  csrr t0, mstatus
  li t1, MSTATUS_MIE | MSTATUS_MPP
  and t1, t0, t1
  bnez t1, fail
  andi t0, t0, MSTATUS_MPIE
  beqz t0, fail

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
  csrr t0, mcause
  li t1, 11
  bne t0, t1, trap_fail
  csrr t0, mepc
  la t1, ecall_site
  bne t0, t1, trap_fail
  csrr t0, mstatus
  li t1, MSTATUS_MPP
  and t2, t0, t1
  bne t2, t1, trap_fail
  andi t0, t0, MSTATUS_MIE
  bnez t0, trap_fail

  la t0, after_ecall
  csrw mepc, t0
  li s0, 2
  mret

trap_fail:
  li a0, 1
  ebreak
