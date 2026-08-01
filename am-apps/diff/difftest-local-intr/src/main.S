#define MSTATUS_SIE  (1 << 1)
#define MSTATUS_MIE  (1 << 3)
#define MSTATUS_MPP  (3 << 11)
#define MSTATUS_MPP_S (1 << 11)

#define MIP_SSIP (1 << 1)
#define MIP_MSIP (1 << 3)
#define MIP_STIP (1 << 5)
#define MIP_MTIP (1 << 7)

#define CLINT_MSIP     0x02000000
#define CLINT_MTIMECMP 0x02004000

  .section .text
  .align 2
  .globl main
main:
  addi sp, sp, -16
  sw ra, 12(sp)
  sw s0, 8(sp)
  sw s1, 4(sp)
  li s0, 0
  li s1, 0

  la t0, machine_trap
  csrw mtvec, t0
  la t0, supervisor_trap
  csrw stvec, t0

  /* MSIP and MTIP cannot be delegated; SSIP and STIP can. */
  li t0, MIP_SSIP | MIP_MSIP | MIP_STIP | MIP_MTIP
  csrw mideleg, t0
  csrr t1, mideleg
  li t2, MIP_SSIP | MIP_STIP
  bne t1, t2, fail

  /* Hold both machine interrupts pending, then prove MSIP wins over MTIP. */
  li t0, MSTATUS_MIE
  csrc mstatus, t0
  li t0, MIP_MSIP | MIP_MTIP
  csrw mie, t0

  li t0, CLINT_MTIMECMP
  sw zero, 0(t0)
  sw zero, 4(t0)
  li t0, CLINT_MSIP
  li t1, 1
  sw t1, 0(t0)

  csrr t0, mip
  li t1, MIP_MSIP | MIP_MTIP
  and t0, t0, t1
  bne t0, t1, fail

  li s0, 1
  li t0, MSTATUS_MIE
  csrs mstatus, t0
machine_priority_boundary:
  li t0, 3
  bne s0, t0, fail
  csrr t0, mip
  li t1, MIP_MSIP | MIP_MTIP
  and t0, t0, t1
  bnez t0, fail

  /* Hold both delegated supervisor interrupts pending. */
  li t0, MSTATUS_MIE | MSTATUS_SIE
  csrc mstatus, t0
  li t0, MIP_SSIP | MIP_STIP
  csrw mideleg, t0
  csrw mie, t0

  li t0, 1 << 31
  csrs 0x31a, t0                 /* menvcfgh.STCE */
  li t0, 1 << 1
  csrs mcounteren, t0            /* TM */
  csrw 0x14d, zero               /* stimecmp */
  csrw 0x15d, zero               /* stimecmph */
  li t0, MIP_SSIP
  csrs mip, t0

  csrr t0, mip
  li t1, MIP_SSIP | MIP_STIP
  and t0, t0, t1
  bne t0, t1, fail
  csrr t0, sip
  and t0, t0, t1
  bne t0, t1, fail

  li t0, MSTATUS_SIE
  csrs mstatus, t0
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  li t0, MSTATUS_MPP_S
  csrs mstatus, t0
  la t0, supervisor_priority_boundary
  csrw mepc, t0
  li s0, 10
  mret

supervisor_priority_boundary:
  li t0, 12
  bne s0, t0, fail_trap
  li s0, 20
supervisor_return_ecall:
  ecall

machine_resume:
  li t0, 21
  bne s0, t0, fail
  csrwi mie, 0
  csrwi mideleg, 0

  li a0, 0
  j done
fail:
  li s1, 1
  li a0, 1
done:
  lw s1, 4(sp)
  lw s0, 8(sp)
  lw ra, 12(sp)
  addi sp, sp, 16
  ret

fail_trap:
  li a0, 1
  ebreak

  .align 2
machine_trap:
  li t0, 1
  beq s0, t0, machine_msip
  li t0, 2
  beq s0, t0, machine_mtip
  li t0, 20
  beq s0, t0, machine_from_supervisor
  j fail_trap

machine_msip:
  csrr t0, mcause
  li t1, 0x80000003
  bne t0, t1, fail_trap
  csrr t0, mepc
  la t1, machine_priority_boundary
  bne t0, t1, fail_trap
  csrr t0, mstatus
  srli t0, t0, 11
  andi t0, t0, 3
  li t1, 3
  bne t0, t1, fail_trap
  li t0, CLINT_MSIP
  sw zero, 0(t0)
  li s0, 2
  mret

machine_mtip:
  csrr t0, mcause
  li t1, 0x80000007
  bne t0, t1, fail_trap
  csrr t0, mepc
  la t1, machine_priority_boundary
  bne t0, t1, fail_trap
  li t0, CLINT_MTIMECMP
  li t1, -1
  sw t1, 0(t0)
  sw t1, 4(t0)
  li s0, 3
  mret

machine_from_supervisor:
  csrr t0, mcause
  li t1, 9
  bne t0, t1, fail_trap
  csrr t0, mepc
  la t1, supervisor_return_ecall
  bne t0, t1, fail_trap
  csrr t0, mstatus
  srli t0, t0, 11
  andi t0, t0, 3
  li t1, 1
  bne t0, t1, fail_trap
  la t0, machine_resume
  csrw mepc, t0
  li t0, MSTATUS_MPP
  csrs mstatus, t0
  li s0, 21
  mret

  .align 2
supervisor_trap:
  li t0, 10
  beq s0, t0, supervisor_ssip
  li t0, 11
  beq s0, t0, supervisor_stip
  j fail_trap

supervisor_ssip:
  csrr t0, scause
  li t1, 0x80000001
  bne t0, t1, fail_trap
  csrr t0, sepc
  la t1, supervisor_priority_boundary
  bne t0, t1, fail_trap
  csrr t0, sstatus
  li t1, 1 << 8                 /* SPP */
  and t0, t0, t1
  beqz t0, fail_trap
  li t0, MIP_SSIP
  csrc sip, t0
  li s0, 11
  sret

supervisor_stip:
  csrr t0, scause
  li t1, 0x80000005
  bne t0, t1, fail_trap
  csrr t0, sepc
  la t1, supervisor_priority_boundary
  bne t0, t1, fail_trap
  li t0, -1
  csrw 0x14d, t0               /* stimecmp */
  csrw 0x15d, t0               /* stimecmph */
  li s0, 12
  sret
