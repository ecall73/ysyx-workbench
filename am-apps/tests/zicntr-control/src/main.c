#include <am.h>
#include <klib.h>
#include <stdint.h>

#define read_csr(csr) ({ \
  uintptr_t value; \
  asm volatile("csrr %0, " #csr : "=r"(value)); \
  value; \
})

#define write_csr(csr, value) \
  asm volatile("csrw " #csr ", %0" :: "rK"((uintptr_t)(value)) : "memory")

static void check(const char *name, uintptr_t actual, uintptr_t expected) {
  if (actual != expected) {
    printf("%s: expected 0x%x, got 0x%x\n", name,
        (unsigned)expected, (unsigned)actual);
    halt(1);
  }
}

int main(void) {
  write_csr(mcounteren, UINT32_MAX);
  write_csr(scounteren, UINT32_MAX);
  write_csr(mcountinhibit, UINT32_MAX);

  check("mcounteren", read_csr(mcounteren), 0x7);
  check("scounteren", read_csr(scounteren), 0x7);
  check("mcountinhibit", read_csr(mcountinhibit), 0x5);

  // Exercise the fixed read-only CSR skip policy.  Their values are platform
  // identifiers/profile declarations and need not match the Spike reference.
  check("misa", read_csr(0x301), 0x4014112d);
  check("mvendorid", read_csr(0xf11), 0x79737978);
  check("marchid", read_csr(0xf12), 26030082);
  check("mimpid", read_csr(0xf13), 0);
  check("mhartid", read_csr(0xf14), 0);
  check("mconfigptr", read_csr(0xf15), 0);
  check("mstatush", read_csr(0x310), 0);

  printf("zicntr-control: PASS\n");
  return 0;
}
