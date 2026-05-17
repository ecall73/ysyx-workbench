ENTRY(_start)
PHDRS {
  text PT_LOAD FLAGS(5);
  data PT_LOAD FLAGS(6);
  bss  PT_LOAD FLAGS(6);
}

MEMORY {
  flash (rx)  : ORIGIN = _pmem_start + _entry_offset, LENGTH = 0x1000000
  psram (rwx) : ORIGIN = 0x80000000, LENGTH = 0x400000
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

  . = ORIGIN(psram);
  _data_start = .;
  .data : {
    *(.data*)
    *(.sdata*)
  } > psram AT> flash : data
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
  } > psram : bss
  . = ALIGN(16);
  _bss_end = .;

  _heap_start = .;
  _stack_pointer = ORIGIN(sram) + LENGTH(sram);
  _heap_end = ORIGIN(psram) + LENGTH(psram);

  ASSERT((LOADADDR(.data) + SIZEOF(.data)) <= (ORIGIN(flash) + LENGTH(flash)),
         "Flash overflow: text/rodata/data(LMA) exceed flash capacity")
  ASSERT(_heap_start <= _heap_end,
         "PSRAM overflow: data/bss exceed available PSRAM")
  ASSERT((_stack_pointer >= ORIGIN(sram)) && (_stack_pointer <= (ORIGIN(sram) + LENGTH(sram))),
         "SRAM stack pointer out of SRAM range")

  end = .;
  _end = .;
}
