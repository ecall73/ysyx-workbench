#define MSTATUS_MIE (1 << 3)
#define MSTATUS_MPP (3 << 11)
#define MIP_MSIP    (1 << 3)
#define CLINT_MSIP  0x02000000
#define CLINT_MTIME 0x0200bff8

  .section .text
  .align 2
  .globl main
main:
  la s0, word_a
  la s1, word_b
  la t0, machine_trap
  csrw mtvec, t0

  /* SC without a reservation fails and leaves memory unchanged. */
  li t0, 0x11111111
  sw t0, 0(s0)
  li t1, 0x22222222
  sc.w t2, t1, (s0)
  li t3, 1
  bne t2, t3, fail
  lw t2, 0(s0)
  bne t2, t0, fail

  /* A matching LR/SC succeeds; every completed SC then clears reservation. */
  lr.w t0, (s0)
  li t1, 0x33333333
  sc.w t2, t1, (s0)
  bnez t2, fail
  lw t2, 0(s0)
  bne t2, t1, fail
  li t1, 0x44444444
  sc.w t2, t1, (s0)
  li t3, 1
  bne t2, t3, fail

  /* A wrong-address SC fails and also consumes the reservation. */
  lr.w t0, (s0)
  sc.w t2, t0, (s1)
  li t3, 1
  bne t2, t3, fail
  sc.w t2, t0, (s0)
  bne t2, t3, fail

  /* A newer LR replaces the older physical-word reservation. */
  lr.w t0, (s0)
  lr.w t1, (s1)
  sc.w t2, t0, (s0)
  li t3, 1
  bne t2, t3, fail
  lr.w t1, (s1)
  li t0, 0x55555555
  sc.w t2, t0, (s1)
  bnez t2, fail

  /* Same-hart stores and AMOs preserve this profile's reservation. */
  lr.w t0, (s0)
  li t1, 0x66666666
  sw t1, 0(s0)
  li t1, 0x77777777
  sc.w t2, t1, (s0)
  bnez t2, fail
  lw t2, 0(s0)
  bne t2, t1, fail

  lr.w t0, (s0)
  li t1, 1
  amoadd.w t2, t1, (s0)
  bne t2, t0, fail
  li t1, 0x88888888
  sc.w t2, t1, (s0)
  bnez t2, fail
  lw t2, 0(s0)
  bne t2, t1, fail

  /* A faulting LR or SC is not an architecturally completed invalidation. */
  li s2, 5
  lr.w t0, (s0)
  addi t1, s0, 1
faulting_lr:
  lr.w t2, (t1)
after_faulting_lr:
  li t0, 6
  bne s2, t0, fail
  li t1, 0x89898989
  sc.w t2, t1, (s0)
  bnez t2, fail

  li s2, 7
  lr.w t0, (s0)
  addi t1, s0, 1
faulting_sc:
  sc.w t2, t0, (t1)
after_faulting_sc:
  li t0, 8
  bne s2, t0, fail
  li t1, 0x8a8a8a8a
  sc.w t2, t1, (s0)
  bnez t2, fail

  /* A synchronous M trap and mret preserve reservation. */
  li s2, 1
  lr.w t0, (s0)
m_ecall:
  ecall
m_ecall_resume:
  li t1, 0x99999999
  sc.w t2, t1, (s0)
  bnez t2, fail
  li t0, 2
  bne s2, t0, fail

  /* Authorized CSR and timer skips preserve model-private reservation state. */
  lr.w t0, (s0)
  csrr t1, misa
  li t1, 0xaaaaaaaa
  sc.w t2, t1, (s0)
  bnez t2, fail

  lr.w t0, (s0)
  li t1, CLINT_MTIME
  lw t2, 0(t1)
  li t1, 0xbbbbbbbb
  sc.w t2, t1, (s0)
  bnez t2, fail

  /* Cause-only MSIP delivery and its typed MMIO clear preserve reservation. */
  li t0, MIP_MSIP
  csrw mie, t0
  li s2, 3
  lr.w t0, (s0)
  li t1, CLINT_MSIP
  li t2, 1
  sw t2, 0(t1)
  li t1, MSTATUS_MIE
  csrs mstatus, t1
after_msip:
  li t0, 4
  bne s2, t0, fail
  li t1, 0xcccccccc
  sc.w t2, t1, (s0)
  bnez t2, fail

  /* Finish in U mode after proving a delegated trap and sret preserve it. */
  la t0, supervisor_trap
  csrw stvec, t0
  li t0, 1 << 8
  csrw medeleg, t0
  la t0, user_test
  csrw mepc, t0
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  mret

machine_trap:
  csrr t0, mcause
  li t1, 11
  beq t0, t1, handle_m_ecall
  li t1, 0x80000003
  beq t0, t1, handle_msip
  li t1, 4
  beq t0, t1, handle_faulting_lr
  li t1, 6
  beq t0, t1, handle_faulting_sc
  j fail

handle_m_ecall:
  li t0, 1
  bne s2, t0, fail
  csrr t0, mepc
  la t1, m_ecall
  bne t0, t1, fail
  addi t0, t0, 4
  csrw mepc, t0
  li s2, 2
  mret

handle_msip:
  li t0, 3
  bne s2, t0, fail
  li t0, CLINT_MSIP
  sw zero, 0(t0)
  li t0, MSTATUS_MIE
  csrc mstatus, t0
  li s2, 4
  mret

handle_faulting_lr:
  li t0, 5
  bne s2, t0, fail
  csrr t0, mepc
  la t1, faulting_lr
  bne t0, t1, fail
  addi t0, t0, 4
  csrw mepc, t0
  li s2, 6
  mret

handle_faulting_sc:
  li t0, 7
  bne s2, t0, fail
  csrr t0, mepc
  la t1, faulting_sc
  bne t0, t1, fail
  addi t0, t0, 4
  csrw mepc, t0
  li s2, 8
  mret

  .align 2
supervisor_trap:
  csrr t0, scause
  li t1, 8
  bne t0, t1, fail
  csrr t0, sepc
  la t1, u_ecall
  bne t0, t1, fail
  addi t0, t0, 4
  csrw sepc, t0
  sret

user_test:
  lr.w t0, (s0)
u_ecall:
  ecall
  li t1, 0xdddddddd
  sc.w t2, t1, (s0)
  bnez t2, fail
  lw t2, 0(s0)
  bne t2, t1, fail
  li a0, 0
  ebreak

fail:
  li a0, 1
  ebreak

  .section .data
  .align 2
word_a:
  .word 0
word_b:
  .word 0x13579bdf
