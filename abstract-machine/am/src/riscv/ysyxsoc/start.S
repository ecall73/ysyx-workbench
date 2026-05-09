.section entry, "ax"
.globl _start
.type _start, @function

_start:
  mv s0, zero
  la sp, _stack_pointer

  /* Copy .data init image from MROM load address to SRAM runtime address. */
  la t0, _data_load_start
  la t1, _data_start
  la t2, _data_end
1:
  bgeu t1, t2, 2f
  lw a0, 0(t0)
  sw a0, 0(t1)
  addi t0, t0, 4
  addi t1, t1, 4
  j 1b

  /* Zero .bss in SRAM. */
2:
  la t1, _bss_start
  la t2, _bss_end
  li a0, 0
3:
  bgeu t1, t2, 4f
  sw a0, 0(t1)
  addi t1, t1, 4
  j 3b

4:
  call _trm_init

.size _start, . - _start
