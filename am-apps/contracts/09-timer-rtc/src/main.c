#define CONTRACT_ID "09-timer-rtc"
#include <contract.h>
#include <klib-macros.h>

static uint64_t rtc_key(AM_TIMER_RTC_T r) {
  uint64_t v = (uint64_t)r.year;
  v = v * 13u + (uint64_t)r.month;
  v = v * 32u + (uint64_t)r.day;
  v = v * 24u + (uint64_t)r.hour;
  v = v * 60u + (uint64_t)r.minute;
  v = v * 60u + (uint64_t)r.second;
  return v;
}

static void check_rtc(AM_TIMER_RTC_T r) {
  CONTRACT_CHECK(r.year >= 1970, "rtc-year");
  CONTRACT_CHECK(r.month >= 1 && r.month <= 12, "rtc-month");
  CONTRACT_CHECK(r.day >= 1 && r.day <= 31, "rtc-day");
  CONTRACT_CHECK(r.hour >= 0 && r.hour < 24, "rtc-hour");
  CONTRACT_CHECK(r.minute >= 0 && r.minute < 60, "rtc-minute");
  CONTRACT_CHECK(r.second >= 0 && r.second < 60, "rtc-second");
}

int main(const char *args) {
  (void)args;
  contract_begin();

#if defined(__PLATFORM_NEMU)
  contract_skip("nemu-rtc-stub");
#endif

  CONTRACT_CHECK(ioe_init(), "ioe-init");
  AM_TIMER_RTC_T a = io_read(AM_TIMER_RTC);
  for (volatile unsigned i = 0; i < 200000u; i++) {
  }
  AM_TIMER_RTC_T b = io_read(AM_TIMER_RTC);
  check_rtc(a);
  check_rtc(b);
  CONTRACT_CHECK(rtc_key(b) >= rtc_key(a), "rtc-monotonic");
  contract_pass();
}
