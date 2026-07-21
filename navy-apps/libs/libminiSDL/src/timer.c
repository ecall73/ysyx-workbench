#include <NDL.h>
#include <sdl-timer.h>
#include <stdio.h>

SDL_TimerID SDL_AddTimer(uint32_t interval, SDL_NewTimerCallback callback, void *param) {
  return NULL;
}

int SDL_RemoveTimer(SDL_TimerID id) {
  return 1;
}

uint32_t SDL_GetTicks() {
  static uint32_t init_time = 0;
  static int initialized = 0;
  uint32_t now = NDL_GetTicks();
  if (!initialized) {
    init_time = now;
    initialized = 1;
  }
  return now - init_time;
}

void SDL_Delay(uint32_t ms) {
  uint32_t start = NDL_GetTicks();
  while (NDL_GetTicks() - start < ms);
}
