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
  }
  .data : {
    *(.data*)
  } : data
  edata = .;
  _data = .;
  .bss : {
	_bss_start = .;
    *(.bss*)
    *(.sbss*)
    *(.scommon)
  }
  _stack_top = ALIGN(0x1000);
  . = _stack_top + 0x8000;
  _stack_pointer = .;
  end = .;
  _end = .;
  _heap_start = ALIGN(0x1000);

  ASSERT(_heap_start <= (_pmem_start + 0x8000000),
         "PMEM overflow: image+stack exceeds PMEM")
  ASSERT(_stack_top <= _stack_pointer,
         "Stack pointer is below stack top")
  ASSERT((_stack_pointer & 0xf) == 0,
         "Stack pointer is not 16-byte aligned")
  ASSERT((_heap_start & 0xfff) == 0,
         "Heap start is not page aligned")
}
