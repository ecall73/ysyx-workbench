#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/time.h>

static uint64_t get_time_us(void) {
  struct timeval tv;
  assert(gettimeofday(&tv, NULL) == 0);
  return (uint64_t)tv.tv_sec * 1000000 + tv.tv_usec;
}

int main() {
  uint64_t next = get_time_us() + 500000;
  int count = 1;

  while (1) {
    if (get_time_us() >= next) {
      printf("timer-test: %d\n", count++);
      next += 500000;
    }
  }
}
