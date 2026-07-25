#include <am.h>
#include <nemu.h>

static uint64_t boot_time_us = 0;

#ifdef __riscv
// NEMU advances mtime once per retired instruction. Match xv6's Sstc period.
#define MTIME_TICKS_PER_IRQ 1000000ull

static uint64_t read_mtime() {
  uint32_t hi, lo, hi2;
  do {
    asm volatile("csrr %0, timeh" : "=r"(hi));
    asm volatile("csrr %0, time" : "=r"(lo));
    asm volatile("csrr %0, timeh" : "=r"(hi2));
  } while (hi != hi2);
  return ((uint64_t)hi << 32) | lo;
}

static void set_next_mtimecmp() {
  uintptr_t old_mstatus;
  uintptr_t mprv = 1u << 17;
  asm volatile("csrrc %0, mstatus, %1"
      : "=r"(old_mstatus) : "r"(mprv) : "memory");

  uint64_t next = read_mtime() + MTIME_TICKS_PER_IRQ;
  volatile uint32_t *mtimecmp = (volatile uint32_t *)CLINT_MTIMECMP;
  mtimecmp[0] = 0xffffffffu;
  mtimecmp[1] = next >> 32;
  mtimecmp[0] = next;

  if (old_mstatus & mprv) {
    asm volatile("csrs mstatus, %0" : : "r"(mprv) : "memory");
  }
}

void __am_timer_irq_init() {
  set_next_mtimecmp();
  asm volatile("csrs mie, %0" : : "r"(1u << 7));
}

void __am_timer_irq_ack() {
  set_next_mtimecmp();
}
#endif

static uint64_t read_rtc_us() {
  return ((uint64_t)inl(RTC_ADDR + 4) << 32) + inl(RTC_ADDR);
}

void __am_timer_init() {
  boot_time_us = read_rtc_us();
}

void __am_timer_uptime(AM_TIMER_UPTIME_T *uptime) {
  uptime->us = read_rtc_us() - boot_time_us;
}

void __am_timer_rtc(AM_TIMER_RTC_T *rtc) {
  rtc->second = 0;
  rtc->minute = 0;
  rtc->hour   = 0;
  rtc->day    = 0;
  rtc->month  = 0;
  rtc->year   = 1900;
}
