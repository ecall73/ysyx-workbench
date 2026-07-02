ENTRY(_start)
PHDRS { text PT_LOAD FLAGS(5); ssbl PT_LOAD FLAGS(5); data PT_LOAD FLAGS(6); bss PT_LOAD FLAGS(6); }
MEMORY {
  flash (rx)   : ORIGIN = _pmem_start + _entry_offset, LENGTH = 0x1000000
  sram  (rwx)  : ORIGIN = 0x0f000000, LENGTH = 0x2000
  sdram (rwx)  : ORIGIN = 0xa0000000, LENGTH = 0x2000000
}
SECTIONS {
  . = ORIGIN(flash);
  .entry : { *(entry) } > flash : text
  . = ORIGIN(sram);
  .ssbl : AT(ALIGN(LOADADDR(.entry) + SIZEOF(.entry), 4)) {
    _ssbl_vma_start = .;
    KEEP(*(.ssbl*))
    . = ALIGN(4);
    _ssbl_vma_end = .;
  } > sram : ssbl
  _ssbl_lma_start = LOADADDR(.ssbl);
  _ssbl_lma_end = LOADADDR(.ssbl) + SIZEOF(.ssbl);
  . = ORIGIN(sdram);
  _data_start = .;
  .data : AT(ALIGN(LOADADDR(.ssbl) + SIZEOF(.ssbl), 4)) {
    *(.text*) . = ALIGN(4); *(.rodata*) *(.srodata*) . = ALIGN(4); *(.data*) *(.sdata*) . = ALIGN(4);
  } > sdram : data
  _data_end = .;
  _data_load_start = LOADADDR(.data);
  . = ALIGN(16);
  .bss : { _bss_start = .; *(.bss*) *(.sbss*) *(.scommon) *(COMMON) } > sdram : bss
  . = ALIGN(16);
  _bss_end = .;
  _heap_start = .;
  _stack_pointer = ORIGIN(sdram) + LENGTH(sdram);
  _heap_end = _stack_pointer - 0x4000;
  ASSERT((LOADADDR(.data) + SIZEOF(.data)) <= (ORIGIN(flash) + LENGTH(flash)), "Flash overflow")
  ASSERT(_ssbl_vma_end <= (ORIGIN(sram) + LENGTH(sram)), "SRAM loader overflow")
  ASSERT(_heap_start <= _heap_end, "SDRAM overflow")
  end = .; _end = .;
}
