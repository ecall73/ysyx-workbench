#define MIP_SSIP (1 << 1)
#define MIP_MSIP (1 << 3)
#define MENVCFGH_STCE (1 << 31)
#define CLINT_MSIP     0x02000000
#define CLINT_MTIMECMP 0x02004000
#define CLINT_MTIME    0x0200bff8

  .section .text
  .align 2
  .globl main
main:
  addi sp, sp, -16
  sw ra, 12(sp)

  csrwi mie, 0
  csrwi mideleg, 0

  /* Profile-owned identification CSRs return DUT values through typed skip. */
  csrr t0, misa
  li t1, 0x4014112d
  bne t0, t1, fail
  csrrw t0, misa, zero
  bne t0, t1, fail
  csrr t0, misa
  bne t0, t1, fail
  csrr t0, mvendorid
  li t1, 0x79737978
  bne t0, t1, fail
  csrr t0, marchid
  li t1, 26030082
  bne t0, t1, fail

  /* Pending sources and their mip/sip projections remain DUT-owned. */
  li t0, CLINT_MSIP
  li t1, 1
  sw t1, 0(t0)
  lw t2, 0(t0)
  bne t1, t2, fail
  csrr t2, mip
  andi t2, t2, MIP_MSIP
  beqz t2, fail
  sw zero, 0(t0)

  li t0, MIP_SSIP
  csrw mideleg, t0
  csrs mip, t0
  csrr t1, sip
  and t1, t1, t0
  beqz t1, fail
  csrc sip, t0
  csrr t1, mip
  and t1, t1, t0
  bnez t1, fail

  /* Timer comparators preserve both RV32 halves exactly. */
  li t0, CLINT_MTIMECMP
  li t1, 0x89abcdef
  sw t1, 0(t0)
  li t1, 0x12345678
  sw t1, 4(t0)
  lw t2, 0(t0)
  li t3, 0x89abcdef
  bne t2, t3, fail
  lw t2, 4(t0)
  li t3, 0x12345678
  bne t2, t3, fail

  li t0, MENVCFGH_STCE
  csrs 0x31a, t0
  li t0, 1 << 1
  csrs mcounteren, t0
  li t0, 0x76543210
  csrw 0x14d, t0
  li t0, 0xfedcba98
  csrw 0x15d, t0
  csrr t1, 0x14d
  li t2, 0x76543210
  bne t1, t2, fail
  csrr t1, 0x15d
  li t2, 0xfedcba98
  bne t1, t2, fail

  /* mtime and time share one monotonic 64-bit source. */
  li t0, CLINT_MTIME
  li t1, 0x12345678
  sw t1, 4(t0)
  li t1, 0x10000000
  sw t1, 0(t0)
  lw t1, 4(t0)
  li t2, 0x12345678
  bne t1, t2, fail
  lw t1, 0(t0)
  li t2, 0x10000000
  bltu t1, t2, fail
  csrr t1, timeh
  li t2, 0x12345678
  bne t1, t2, fail
  csrr t1, time
  li t2, 0x10000000
  bltu t1, t2, fail

  li a0, 0
  j done
fail:
  li a0, 1
done:
  lw ra, 12(sp)
  addi sp, sp, 16
  ret
