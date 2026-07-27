.section entry, "ax"
.globl _start
.type _start, @function

_start:
  mv s0, zero
  la sp, _stack_pointer
#ifdef __riscv_flen
  li t0, (1 << 13)       # mstatus.FS = Initial
  csrs mstatus, t0
  csrwi fcsr, 0
#endif
  call _trm_init

.size _start, . - _start
