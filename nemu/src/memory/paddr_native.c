#include <device/mmio.h>
#include <isa.h>
#include <memory/paddr_internal.h>

static bool native_read(paddr_t addr, int len, word_t *data) {
  if (nemu_in_region_range(addr, len, CONFIG_MBASE, CONFIG_MSIZE)) {
    *data = nemu_host_read_region(nemu_pmem_base(), addr, CONFIG_MBASE, len);
    return true;
  }
  IFDEF(CONFIG_DEVICE, {
    *data = mmio_read(addr, len);
    return true;
  });
  return false;
}

static bool native_write(paddr_t addr, int len, word_t data) {
  if (nemu_in_region_range(addr, len, CONFIG_MBASE, CONFIG_MSIZE)) {
    nemu_host_write_region(nemu_pmem_base(), addr, CONFIG_MBASE, len, data);
    return true;
  }
  IFDEF(CONFIG_DEVICE, {
    mmio_write(addr, len, data);
    return true;
  });
  return false;
}

static void native_log_ranges(void) {
  Log("physical memory area [" FMT_PADDR ", " FMT_PADDR "]", PMEM_LEFT, PMEM_RIGHT);
}

static void native_out_of_bound(paddr_t addr) {
  panic("address = " FMT_PADDR " is out of bound for native backend. valid ranges: pmem[" FMT_PADDR ", " FMT_PADDR "], pc = " FMT_WORD,
      addr, PMEM_LEFT, PMEM_RIGHT, cpu.pc);
}

const NemuPaddrBackendOps *nemu_native_paddr_backend(void) {
  static const NemuPaddrBackendOps ops = {
    .name = "native",
    .init = NULL,
    .read = native_read,
    .write = native_write,
    .log_ranges = native_log_ranges,
    .out_of_bound = native_out_of_bound,
  };
  return &ops;
}
