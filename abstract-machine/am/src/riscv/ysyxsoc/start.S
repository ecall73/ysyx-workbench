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
  sub a1, t2, t1
  andi a1, a1, -4
  add a2, t1, a1
1: /* word copy loop */
  bgeu t1, a2, 2f
  lw a0, 0(t0)
  sw a0, 0(t1)
  addi t0, t0, 4
  addi t1, t1, 4
  j 1b
2: /* tail byte copy */
  bgeu t1, t2, 3f
  lb a0, 0(t0)
  sb a0, 0(t1)
  addi t0, t0, 1
  addi t1, t1, 1
  j 2b

  /* Zero .bss in SRAM. */
3:
  la t1, _bss_start
  la t2, _bss_end
  sub a1, t2, t1
  andi a1, a1, -4
  add a2, t1, a1
4: /* word clear loop */
  bgeu t1, a2, 5f
  sw zero, 0(t1)
  addi t1, t1, 4
  j 4b
5: /* tail byte clear */
  bgeu t1, t2, 6f
  sb zero, 0(t1)
  addi t1, t1, 1
  j 5b

6:
  call _trm_init

.size _start, . - _start
