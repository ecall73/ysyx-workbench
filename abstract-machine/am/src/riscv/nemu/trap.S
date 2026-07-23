#define concat_temp(x, y) x ## y
#define concat(x, y) concat_temp(x, y)
#define MAP(c, f) c(f)

#if __riscv_xlen == 32
#define LOAD  lw
#define STORE sw
#define XLEN  4
#else
#define LOAD  ld
#define STORE sd
#define XLEN  8
#endif

#define REGS_LO16(f) \
      f( 1)       f( 3) f( 4) f( 5) f( 6) f( 7) f( 8) f( 9) \
f(10) f(11) f(12) f(13) f(14) f(15)
#ifndef __riscv_e
#define REGS_HI16(f) \
                                    f(16) f(17) f(18) f(19) \
f(20) f(21) f(22) f(23) f(24) f(25) f(26) f(27) f(28) f(29) \
f(30) f(31)
#define NR_REGS 32
#else
#define REGS_HI16(f)
#define NR_REGS 16
#endif

#define REGS(f) REGS_LO16(f) REGS_HI16(f)

#define PUSH(n) STORE concat(x, n), (n * XLEN)(sp);
#define POP(n)  LOAD  concat(x, n), (n * XLEN)(sp);

#define CONTEXT_SIZE  ((NR_REGS + 3 + 1) * XLEN)
#define OFFSET_SP     ( 2 * XLEN)
#define OFFSET_CAUSE  ((NR_REGS + 0) * XLEN)
#define OFFSET_STATUS ((NR_REGS + 1) * XLEN)
#define OFFSET_EPC    ((NR_REGS + 2) * XLEN)

.align 3
.globl __am_asm_trap
__am_asm_trap:
  # mscratch is 0 in M-mode and holds the kernel stack pointer in U-mode.
  csrrw sp, mscratch, sp
  bnez sp, .Lfrom_user
  csrrw sp, mscratch, zero

  addi sp, sp, -CONTEXT_SIZE
  MAP(REGS, PUSH)
  addi t0, sp, CONTEXT_SIZE
  j .Lcontext_ready
.Lfrom_user:
  addi sp, sp, -CONTEXT_SIZE
  MAP(REGS, PUSH)

  csrrw t0, mscratch, zero
.Lcontext_ready:
  STORE t0, OFFSET_SP(sp)

  csrr t1, mcause
  csrr t2, mstatus
  csrr t3, mepc

  STORE t1, OFFSET_CAUSE(sp)
  STORE t2, OFFSET_STATUS(sp)
  STORE t3, OFFSET_EPC(sp)

  # Use the trapped context's address translation for M-mode data accesses.
  li a0, (1 << 17)
  csrs mstatus, a0

  mv a0, sp
  call __am_irq_handle
  mv sp, a0

  LOAD t1, OFFSET_STATUS(sp)
  LOAD t2, OFFSET_EPC(sp)
  csrw mstatus, t1
  csrw mepc, t2

  srli t0, t1, 11
  andi t0, t0, 3
  bnez t0, .Lreturn_m
  LOAD t0, OFFSET_SP(sp)
  csrw mscratch, t0
  MAP(REGS, POP)
  addi sp, sp, CONTEXT_SIZE
  csrrw sp, mscratch, sp
  mret
.Lreturn_m:
  MAP(REGS, POP)
  LOAD sp, OFFSET_SP(sp)
  mret
