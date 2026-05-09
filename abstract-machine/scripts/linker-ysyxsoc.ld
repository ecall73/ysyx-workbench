ENTRY(_start)
PHDRS { text PT_LOAD; data PT_LOAD; }

SECTIONS {
  /* _pmem_start and _entry_offset are defined in LDFLAGS */
  . = _pmem_start + _entry_offset;
  .text : {
    *(entry)
    *(.text*)
  } : text
  etext = .;
  _etext = .;

  .rodata : {
    *(.rodata*)
  } : text

  /* Keep heap in SRAM lower 4KB */
  _heap_start = 0x0f000000;
  _heap_end = 0x0f001000;

  /* Place writable sections in SRAM upper 4KB */
  . = 0x0f001000;
  _data_start = .;
  .data : AT (LOADADDR(.rodata) + SIZEOF(.rodata)) {
    *(.data*)
    *(.sdata*)
  } : data
  _data_end = .;
  _data_load_start = LOADADDR(.data);
  edata = .;
  _data = .;

  .bss : {
    _bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(.scommon)
    *(COMMON)
  }
  _bss_end = .;

  _stack_pointer = 0x0f002000;
  end = .;
  _end = .;
}
