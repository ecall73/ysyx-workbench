#include <stdint.h>
#include <stdio.h>
#include <NDL.h>

int main() {
  NDL_Init(0);

  uint32_t next = NDL_GetTicks() + 500;
  int count = 1;

  while (1) {
    if (NDL_GetTicks() >= next) {
      printf("timer-test: %d\n", count++);
      next += 500;
    }
  }
}
