.section entry, "ax"
.globl _start
.type _start, @function

_start:
  mv s0, zero
  la sp, _stack_pointer

  /* Copy .data init image from flash(LMA) to SRAM(VMA). */
  la t0, _data_load_start
  la t1, _data_start
  la t2, _data_end
1:
  beq t1, t2, 2f
  bltu t1, t2, 3f
  j 2f
3:
  lb a0, 0(t0)
  sb a0, 0(t1)
  addi t0, t0, 1
  addi t1, t1, 1
  j 1b

  /* Zero .bss in SRAM. */
2:
  la t1, _bss_start
  la t2, _bss_end
  li a0, 0
4:
  beq t1, t2, 4f
  bltu t1, t2, 5f
  j 4f
5:
  sb a0, 0(t1)
  addi t1, t1, 1
  j 4b

4:
  call _trm_init

.size _start, . - _start
