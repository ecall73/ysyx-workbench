ENTRY(_start)
PHDRS {
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
}

MEMORY {
  flash (rx)  : ORIGIN = _pmem_start + _entry_offset, LENGTH = 0x1000000
  sram  (rwx) : ORIGIN = 0x0f000000, LENGTH = 0x2000
}

SECTIONS {
  . = ORIGIN(flash);
  .text : {
    *(entry)
    *(.text*)
  } > flash : text
  etext = .;
  _etext = .;

  . = ALIGN(4);
  .rodata : {
    *(.rodata*)
    *(.srodata*)
  } > flash : text
  . = ALIGN(4);

  . = ORIGIN(sram);
  _data_start = .;
  .data : {
    *(.data*)
    *(.sdata*)
  } > sram AT> flash : data
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
  } > sram : data
  . = ALIGN(16);
  _bss_end = .;

  _heap_start = .;
  _stack_pointer = ORIGIN(sram) + LENGTH(sram);
  _heap_end = _stack_pointer;

  ASSERT((LOADADDR(.data) + SIZEOF(.data)) <= (ORIGIN(flash) + LENGTH(flash)),
         "Flash overflow: text/rodata/data(LMA) exceed flash capacity")
  ASSERT(_bss_end <= _stack_pointer,
         "SRAM overflow: data/bss exceed available SRAM")

  end = .;
  _end = .;
}
