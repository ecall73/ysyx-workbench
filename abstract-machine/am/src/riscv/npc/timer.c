#include <am.h>
#include "include/npc.h"

static uint64_t boot_time = 0;

static uint64_t get_time_us() {
  return ((uint64_t)inl(RTC_ADDR + 4) << 32) + inl(RTC_ADDR);
}

static int is_leap_year(int year) {
  return (year % 400 == 0) || (year % 4 == 0 && year % 100 != 0);
}

static int days_in_month(int year, int month) {
  static const int mdays[12] = {
    31, 28, 31, 30, 31, 30,
    31, 31, 30, 31, 30, 31
  };
  if (month == 2 && is_leap_year(year)) return 29;
  return mdays[month - 1];
}

// Convert Unix epoch seconds to UTC calendar date/time.
static void epoch_to_utc(uint64_t sec, AM_TIMER_RTC_T *rtc) {
  uint64_t days = sec / 86400;
  uint64_t rem  = sec % 86400;

  rtc->hour   = rem / 3600;
  rem        %= 3600;
  rtc->minute = rem / 60;
  rtc->second = rem % 60;

  int year = 1970;
  while (1) {
    int diy = is_leap_year(year) ? 366 : 365;
    if (days < (uint64_t)diy) break;
    days -= diy;
    year++;
  }

  int month = 1;
  while (1) {
    int dim = days_in_month(year, month);
    if (days < (uint64_t)dim) break;
    days -= dim;
    month++;
  }

  rtc->year = year;
  rtc->month = month;
  rtc->day = (int)days + 1;
}

void __am_timer_init() {
  boot_time = get_time_us();
}

void __am_timer_uptime(AM_TIMER_UPTIME_T *uptime) {
  uptime->us = get_time_us() - boot_time;
}

void __am_timer_rtc(AM_TIMER_RTC_T *rtc) {
  epoch_to_utc(get_time_us() / 1000000, rtc);
}
