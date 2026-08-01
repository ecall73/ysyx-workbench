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

#define MCOUNTINHIBIT_CY_IR 0x5u

static void check(const char *name, uintptr_t actual, uintptr_t expected) {
  if (actual != expected) {
    printf("%s: expected 0x%x, got 0x%x\n", name,
        (unsigned)expected, (unsigned)actual);
    halt(1);
  }
}

static uintptr_t read_after_enabling_minstret(void) {
  uintptr_t actual;
  uintptr_t inhibit = MCOUNTINHIBIT_CY_IR;
  asm volatile(
      "csrw mcountinhibit, zero\n"
      "csrr %0, minstret\n"
      "csrw mcountinhibit, %1\n"
      : "=&r"(actual)
      : "r"(inhibit)
      : "memory");
  return actual;
}

static uintptr_t read_after_disabling_minstret(void) {
  uintptr_t actual;
  uintptr_t inhibit = MCOUNTINHIBIT_CY_IR;
  asm volatile(
      "csrw mcountinhibit, zero\n"
      "csrw mcountinhibit, %1\n"
      "csrr %0, minstret\n"
      : "=&r"(actual)
      : "r"(inhibit)
      : "memory");
  return actual;
}

static uintptr_t write_then_read_mcycle(uintptr_t value) {
  uintptr_t actual;
  uintptr_t inhibit = MCOUNTINHIBIT_CY_IR;
  asm volatile(
      "csrw mcountinhibit, zero\n"
      "csrw mcycle, %1\n"
      "csrr %0, mcycle\n"
      "csrw mcountinhibit, %2\n"
      : "=&r"(actual)
      : "r"(value), "r"(inhibit)
      : "memory");
  return actual;
}

static uintptr_t write_then_read_minstret(uintptr_t value) {
  uintptr_t actual;
  uintptr_t inhibit = MCOUNTINHIBIT_CY_IR;
  asm volatile(
      "csrw mcountinhibit, zero\n"
      "csrw minstret, %1\n"
      "csrr %0, minstret\n"
      "csrw mcountinhibit, %2\n"
      : "=&r"(actual)
      : "r"(value), "r"(inhibit)
      : "memory");
  return actual;
}

int main(void) {
  write_csr(mcounteren, UINT32_MAX);
  write_csr(scounteren, UINT32_MAX);
  write_csr(mcountinhibit, UINT32_MAX);

  check("mcounteren", read_csr(mcounteren), 0x7);
  check("scounteren", read_csr(scounteren), 0x7);
  check("mcountinhibit", read_csr(mcountinhibit), MCOUNTINHIBIT_CY_IR);

  // With CY and IR inhibited, machine counters and their read-only shadows are
  // stable, including RV32 high-half accesses.
  write_csr(mcycle, 0x89abcdefu);
  write_csr(mcycleh, 0x01234567u);
  write_csr(minstret, 0x76543210u);
  write_csr(minstreth, 0xfedcbadau);
  check("mcycle low", read_csr(mcycle), 0x89abcdefu);
  check("mcycle high", read_csr(mcycleh), 0x01234567u);
  check("cycle low", read_csr(cycle), 0x89abcdefu);
  check("cycle high", read_csr(cycleh), 0x01234567u);
  check("minstret low", read_csr(minstret), 0x76543210u);
  check("minstret high", read_csr(minstreth), 0xfedcbadau);
  check("instret low", read_csr(instret), 0x76543210u);
  check("instret high", read_csr(instreth), 0xfedcbadau);

  // mcountinhibit writes use the value from before the instruction. Enabling
  // does not count itself; disabling does count itself.
  write_csr(minstret, 0x100u);
  write_csr(minstreth, 0);
  check("enable takes effect next instruction",
      read_after_enabling_minstret(), 0x100u);
  write_csr(minstret, 0x200u);
  check("disable counts with old inhibit", read_after_disabling_minstret(),
      0x201u);

  // An explicit machine-counter write wins over that instruction's implicit
  // increment, while the immediately following read still returns the old
  // value before its own retirement increment.
  check("mcycle write precedence", write_then_read_mcycle(0x12345678u),
      0x12345678u);
  check("minstret write precedence", write_then_read_minstret(0x23456789u),
      0x23456789u);

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
