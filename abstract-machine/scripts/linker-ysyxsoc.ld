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

  . = ALIGN(4);
  .rodata : {
    *(.rodata*)
  } : text
  . = ALIGN(4);

  /* ysyxSoC SRAM实际可用窗口: 0x0f000000 ~ 0x0f001fff (8KB) */
  __sram_start = 0x0f000000;
  __sram_size  = 0x00002000;
  __sram_end   = __sram_start + __sram_size;

  . = __sram_start;
  _data_start = .;
  .data : AT (LOADADDR(.rodata) + SIZEOF(.rodata)) {
    *(.data*)
    *(.sdata*)
  } : data
  _data_end = .;
  _data_load_start = LOADADDR(.data);
  edata = .;
  _data = .;

  . = ALIGN(16);
  .bss : {
    _bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(.scommon)
    *(COMMON)
  } : data
  . = ALIGN(16);
  _bss_end = .;

  _heap_start = .;
  _stack_pointer = __sram_end;
  _heap_end = _stack_pointer;

  ASSERT(_heap_start <= _heap_end, "SRAM overflow: .data/.bss overlap stack")

  end = .;
  _end = .;
}
