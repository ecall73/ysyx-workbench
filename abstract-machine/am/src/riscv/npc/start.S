.section entry, "ax"
.globl _start
.type _start, @function

_start:
  li ra, 0
  li sp, 0
  li gp, 0
  li tp, 0
  li t0, 0
  li t1, 0
  li t2, 0
  mv s0, zero
  mv s1, zero
  mv a0, zero
  mv a1, zero
  mv a2, zero
  mv a3, zero
  mv a4, zero
  mv a5, zero
  la sp, _stack_pointer
  call _trm_init

.size _start, . - _start
