#define MSTATUS_MPP   (3 << 11)
#define MSTATUS_MPP_S (1 << 11)
#define MSTATUS_FS    (3 << 13)
#define MSTATUS_TVM   (1 << 20)
#define MSTATUS_TW    (1 << 21)
#define MSTATUS_TSR   (1 << 22)
#define MENVCFGH_STCE (1 << 31)
#define STATUS_TEST_MASK (MSTATUS_MPP | MSTATUS_FS | MSTATUS_TVM | MSTATUS_TW | MSTATUS_TSR)

#define ENTER_ILLEGAL(fault, recovery, origin, status_bits) \
  la t0, fault; \
  lw s0, 0(t0); \
  mv s1, t0; \
  la s2, recovery; \
  li s3, origin; \
  li s4, 0; \
  li t0, STATUS_TEST_MASK; \
  csrc mstatus, t0; \
  li t0, status_bits; \
  csrs mstatus, t0; \
  csrw mepc, s1; \
  mret

  .section .text
  .option norvc
  .align 2
  .globl main
main:
  addi sp, sp, -32
  sw ra, 28(sp)
  sw s0, 24(sp)
  sw s1, 20(sp)
  sw s2, 16(sp)
  sw s3, 12(sp)
  sw s4, 8(sp)

  la t0, trap_handler
  csrw mtvec, t0
  csrwi medeleg, 0

  ENTER_ILLEGAL(fault_s_mret, after_s_mret, 1, MSTATUS_MPP_S)
fault_s_mret:
  mret
after_s_mret:
  bnez s4, fail

  ENTER_ILLEGAL(fault_u_sret, after_u_sret, 0, 0)
fault_u_sret:
  sret
after_u_sret:
  bnez s4, fail

  ENTER_ILLEGAL(fault_s_tsr_sret, after_s_tsr_sret, 1,
      MSTATUS_MPP_S | MSTATUS_TSR)
fault_s_tsr_sret:
  sret
after_s_tsr_sret:
  bnez s4, fail

  ENTER_ILLEGAL(fault_s_tvm_sfence, after_s_tvm_sfence, 1,
      MSTATUS_MPP_S | MSTATUS_TVM)
fault_s_tvm_sfence:
  sfence.vma
after_s_tvm_sfence:
  bnez s4, fail

  li a0, 0x13579bdf
  ENTER_ILLEGAL(fault_s_tvm_satp, after_s_tvm_satp, 1,
      MSTATUS_MPP_S | MSTATUS_TVM)
fault_s_tvm_satp:
  csrr a0, satp
after_s_tvm_satp:
  bnez s4, fail
  li t0, 0x13579bdf
  bne a0, t0, fail

  csrwi mcounteren, 0
  li a0, 0x2468ace0
  ENTER_ILLEGAL(fault_s_cycle, after_s_cycle, 1, MSTATUS_MPP_S)
fault_s_cycle:
  csrr a0, cycle
after_s_cycle:
  bnez s4, fail
  li t0, 0x2468ace0
  bne a0, t0, fail

  li a0, 0x55667788
  ENTER_ILLEGAL(fault_s_time, after_s_time, 1, MSTATUS_MPP_S)
fault_s_time:
  csrr a0, time
after_s_time:
  bnez s4, fail
  li t0, 0x55667788
  bne a0, t0, fail

  li t0, 1 << 1
  csrw mcounteren, t0
  li t0, MENVCFGH_STCE
  csrc 0x31a, t0
  li a0, 0x66778899
  ENTER_ILLEGAL(fault_s_stimecmp, after_s_stimecmp, 1, MSTATUS_MPP_S)
fault_s_stimecmp:
  csrr a0, 0x14d
after_s_stimecmp:
  bnez s4, fail
  li t0, 0x66778899
  bne a0, t0, fail

  li t0, 1
  csrw mcounteren, t0
  csrwi scounteren, 0
  li a0, 0x10203040
  ENTER_ILLEGAL(fault_u_cycle, after_u_cycle, 0, 0)
fault_u_cycle:
  csrr a0, cycle
after_u_cycle:
  bnez s4, fail
  li t0, 0x10203040
  bne a0, t0, fail

  /* Encoded read-only identity CSRs reject write intent before any owned read. */
  la t0, fault_mvendorid_write
  lw s0, 0(t0)
  mv s1, t0
  la s2, after_mvendorid_write
  li s3, 3
  li s4, 0
fault_mvendorid_write:
  csrw mvendorid, zero
after_mvendorid_write:
  bnez s4, fail

  /* An FP instruction with FS=Off is illegal and cannot alter its FPR. */
  la t0, fault_m_fp_off
  lw s0, 0(t0)
  mv s1, t0
  la s2, after_m_fp_off
  li s3, 3
  li s4, 0
  li t0, MSTATUS_FS
  csrc mstatus, t0
fault_m_fp_off:
  fadd.s f0, f0, f0
after_m_fp_off:
  bnez s4, fail

  li t0, STATUS_TEST_MASK
  csrc mstatus, t0
  li t0, 1 << 13
  csrs mstatus, t0
  li a0, 0
  j done
fail:
  li a0, 1
done:
  lw s4, 8(sp)
  lw s3, 12(sp)
  lw s2, 16(sp)
  lw s1, 20(sp)
  lw s0, 24(sp)
  lw ra, 28(sp)
  addi sp, sp, 32
  ret

  .align 2
trap_handler:
  csrr t0, mcause
  li t1, 2
  bne t0, t1, trap_fail
  csrr t0, mtval
  bne t0, s0, trap_fail
  csrr t0, mepc
  bne t0, s1, trap_fail
  csrr t0, mstatus
  srli t0, t0, 11
  andi t0, t0, 3
  bne t0, s3, trap_fail
  csrw mepc, s2
  li t0, MSTATUS_MPP
  csrs mstatus, t0
  mret
trap_fail:
  li s4, 1
  csrw mepc, s2
  li t0, MSTATUS_MPP
  csrs mstatus, t0
  mret
