#include <ioe_diag.h>

static bool rtc_valid(AM_TIMER_RTC_T r) {
  return r.year >= 1970
      && r.month >= 1 && r.month <= 12
      && r.day >= 1 && r.day <= 31
      && r.hour >= 0 && r.hour <= 23
      && r.minute >= 0 && r.minute <= 59
      && r.second >= 0 && r.second <= 60;
}

int main(const char *args) {
  (void)args;
  ioe_init();

  AM_TIMER_CONFIG_T cfg = io_read(AM_TIMER_CONFIG);
  AM_INPUT_CONFIG_T icfg = io_read(AM_INPUT_CONFIG);
  printf("[timer][CONFIG] timer.present=%d has_rtc=%d input.present=%d\n",
      cfg.present, cfg.has_rtc, icfg.present);
  if (!cfg.present) {
    printf("[timer][FAIL] timer not present\n");
    return 1;
  }

  printf("[timer][EXPECT] one line per second; delta should be about 1000000us; Esc exits when input exists\n");
  uint64_t last_print = io_read(AM_TIMER_UPTIME).us;
  uint64_t last_uptime = last_print;
  int rounds = 0;

  while (rounds < 30) {
    AM_TIMER_UPTIME_T now = io_read(AM_TIMER_UPTIME);
    if (now.us - last_print >= 1000000ull) {
      uint64_t delta = now.us - last_uptime;
      printf("[timer][UPTIME] round=%d us=%llu delta=%llu status=%s ",
          rounds,
          (unsigned long long)now.us,
          (unsigned long long)delta,
          (delta >= 800000ull && delta <= 1200000ull) ? "OK" : "CHECK");

      if (cfg.has_rtc) {
        AM_TIMER_RTC_T rtc = io_read(AM_TIMER_RTC);
        printf("rtc=");
        diag_print_rtc(rtc);
        printf(" rtc_status=%s", rtc_valid(rtc) ? "OK" : "CHECK");
      } else {
        printf("rtc=absent");
      }
      printf("\n");

      last_print = now.us;
      last_uptime = now.us;
      rounds++;
    }

    if (diag_poll_exit()) {
      printf("[timer][DONE] Esc pressed\n");
      return 0;
    }
  }

  printf("[timer][DONE] fixed rounds complete\n");
  return 0;
}
